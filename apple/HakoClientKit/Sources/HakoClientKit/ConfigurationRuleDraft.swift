import Foundation

 
 
public enum ConfigurationRuleDocument {
    public static let keys: Set<String> = ["rules", "rule-providers", "sub-rules", "proxy-groups"]

    public static func project(_ document: OrderedJSON) -> OrderedJSON {
        guard case .object(let pairs) = document else { return document }
        var result = OrderedJSON.object(pairs.filter { keys.contains($0.key) })
        let nodes: Set<String>
        if case .array(let values) = document.topLevelValue("proxies") {
            nodes = Set(values.compactMap { value in
                if case .string(let name) = value.topLevelValue("name") { return name }
                return nil
            })
        } else { nodes = [] }
        guard case .array(let groups) = document.topLevelValue("proxy-groups") else { return result }
        result = result.settingTopLevel("proxy-groups", to: .array(groups.map { group in
            var value = group
            var bindsNodes = false
            if case .array(let members) = group.topLevelValue("proxies") {
                let retained = members.filter { member in
                    if case .string(let name) = member, nodes.contains(name) { return false }
                    return true
                }
                bindsNodes = retained.count != members.count
                value = value.settingTopLevel("proxies", to: .array(retained))
            }
            if case .array(let providers) = group.topLevelValue("use"), !providers.isEmpty {
                bindsNodes = true
                value = value.removingTopLevel("use")
            }
            if bindsNodes {
                value = value.settingTopLevel("include-all", to: .scalar("true"))
                if case .string(let selected) = value.topLevelValue("default-selected"), nodes.contains(selected) {
                    value = value.removingTopLevel("default-selected")
                }
            }
            return value
        }))
        return result
    }
}

 
 
public struct ConfigurationRuleDraft: Equatable, Sendable {
    public struct Row: Identifiable, Equatable, Sendable {
        public let id: UUID
        public var raw: String
        public init(id: UUID = UUID(), raw: String) { self.id = id; self.raw = raw }
        public var isFinal: Bool {
            let kind = raw.split(separator: ",", maxSplits: 1).first?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return kind == "MATCH" || kind == "FINAL"
        }
    }
    public struct Group: Identifiable, Equatable, Sendable {
        public let id: UUID
        public var document: OrderedJSON
         
         
        public init(id: UUID = UUID(), document: OrderedJSON) { self.id = id; self.document = document }
        public var name: String { if case .string(let value) = document.topLevelValue("name") { return value }; return "" }
        public var type: String { if case .string(let value) = document.topLevelValue("type") { return value }; return "" }
    }
    public private(set) var groups: [Group]
    private var additionalDocument: OrderedJSON
    public let schemeID: String
    public let version: ConfigurationSourceVersion
    public var label: String
    public private(set) var rows: [Row]
    public let originalDocument: OrderedJSON
    public private(set) var generatedRuleGroups: [String: String]
     
    public private(set) var disabledRules: Set<String>
    public private(set) var notes: [String: String]

    public init(scheme: ConfigurationRuleScheme, payload: ConfigurationSourcePayload) throws {
        schemeID = scheme.id; version = .init(payload.record); label = scheme.label
        generatedRuleGroups = scheme.generatedRuleGroups ?? [:]
        disabledRules = Set(scheme.disabledRules ?? [])
        notes = scheme.ruleNotes ?? [:]
        originalDocument = try OrderedJSON.parse(payload.documentJSON)
        additionalDocument = ConfigurationRuleDocument.project(originalDocument)
        groups = try ConfigurationRuleGroupSnapshot.read(additionalDocument).map { Group(id: UUID(), document: $0.document) }
        guard case .array(let rules) = originalDocument.topLevelValue("rules") else { throw ConfigurationLibraryError.missingRules }
        rows = try rules.map {
            guard case .string(let raw) = $0 else { throw ConfigurationLibraryError.missingRules }
            return Row(raw: raw)
        }
    }
     
    public func preservingIdentity(from previous: Self) -> Self {
        var result = self
        var groupIDs: [String: UUID] = [:]
        for group in previous.groups { groupIDs[group.name] = group.id }
        result.groups = groups.map { Group(id: groupIDs[$0.name] ?? $0.id, document: $0.document) }
        var ruleIDs: [String: [UUID]] = [:]
        for row in previous.rows { ruleIDs[row.raw, default: []].append(row.id) }
        var offsets: [String: Int] = [:]
        result.rows = rows.map { row in
            let index = offsets[row.raw, default: 0]
            offsets[row.raw] = index + 1
            guard let ids = ruleIDs[row.raw], index < ids.count else { return row }
            return Row(id: ids[index], raw: row.raw)
        }
        return result
    }
    public var referencedRuleSets: Set<String> {
        Set(rows.compactMap { row in
            guard row.raw.hasPrefix("RULE-SET,") else { return nil }
            return row.raw.split(separator: ",", maxSplits: 2).dropFirst().first.map(String.init)
        })
    }
    public mutating func reorderGroups(_ orderedIDs: [UUID]) {
        let byID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
        guard orderedIDs.count == groups.count, Set(orderedIDs) == Set(byID.keys) else { return }
        groups = orderedIDs.compactMap { byID[$0] }
    }
    public mutating func setRule(_ raw: String, rowID: UUID?) {
        if let rowID, let index = rows.firstIndex(where: { $0.id == rowID }) { rows[index].raw = raw }
        else if rowID == nil { rows.insert(.init(raw: raw), at: rows.firstIndex(where: \.isFinal) ?? rows.endIndex) }
    }
    public mutating func remove(_ ids: Set<UUID>) {
        rows.removeAll { ids.contains($0.id) && !$0.isFinal }
        let kept = Set(rows.map(\.raw))
        disabledRules = disabledRules.filter { kept.contains($0) }
        notes = notes.filter { kept.contains($0.key) }
    }
     
     
    public mutating func insertRuleFirst(_ raw: String) {
        rows.insert(.init(raw: raw), at: 0)
    }
    public func isEnabled(_ raw: String) -> Bool { !disabledRules.contains(raw) }
    public func note(for raw: String) -> String { notes[raw] ?? "" }
     
    public mutating func setRule(_ raw: String, enabled: Bool, note: String, rowID: UUID?) {
        let previous = rowID.flatMap { id in rows.first { $0.id == id }?.raw }
        setRule(raw, rowID: rowID)
        if let previous, previous != raw, !rows.contains(where: { $0.raw == previous }) {
            disabledRules.remove(previous)
            notes.removeValue(forKey: previous)
        }
        if enabled { disabledRules.remove(raw) } else { disabledRules.insert(raw) }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { notes.removeValue(forKey: raw) } else { notes[raw] = trimmed }
    }
    public mutating func move(_ ids: Set<UUID>, before target: UUID?) {
        let moving = rows.filter { ids.contains($0.id) && !$0.isFinal }
        guard !moving.isEmpty, target.map({ !ids.contains($0) }) ?? true else { return }
        rows.removeAll { ids.contains($0.id) && !$0.isFinal }
        let index = target.flatMap { id in rows.firstIndex { $0.id == id } }
            ?? rows.firstIndex(where: \.isFinal) ?? rows.endIndex
        rows.insert(contentsOf: moving, at: min(index, rows.firstIndex(where: \.isFinal) ?? rows.endIndex))
    }
    public func document() throws -> OrderedJSON {
        guard !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ConfigurationLibraryError.emptyName }
        guard rows.last?.isFinal == true, rows.filter(\.isFinal).count == 1,
              rows.allSatisfy({ !$0.raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw ConfigurationLibraryError.invalidFinalRule
        }
        return currentDocument()
    }
    public func currentDocument() -> OrderedJSON {
        var result = additionalDocument.settingTopLevel("rules", to: .array(rows.map { .string($0.raw) }))
        if !groups.isEmpty || originalDocument.topLevelValue("proxy-groups") != nil {
            result = result.settingTopLevel("proxy-groups", to: .array(groups.map(\.document)))
        }
        return result
    }
}

public struct ConfigurationNewRuleDraft: Equatable, Sendable {
    public var label: String
     
    public var templateID: String?
    public init(label: String, templateID: String? = nil) { self.label = label; self.templateID = templateID }
}

 
 
public struct ConfigurationRuleGroupSnapshot: Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let type: String
    public let members: [String]
    public let providers: [String]
    public let includesAll: Bool
    public let includesAllProxies: Bool
    public let includesAllProviders: Bool
    public let document: OrderedJSON

    public static func read(_ document: OrderedJSON) throws -> [Self] {
        guard let value = document.topLevelValue("proxy-groups") else { return [] }
        guard case .array(let groups) = value else { throw ConfigurationLibraryError.unreadable }
        return try groups.enumerated().map { index, group in
            func string(_ key: String) -> String? {
                guard case .string(let value) = group.topLevelValue(key) else { return nil }
                return value
            }
            func strings(_ key: String) throws -> [String] {
                guard let value = group.topLevelValue(key) else { return [] }
                guard case .array(let items) = value else { throw ConfigurationLibraryError.unreadable }
                return try items.map {
                    guard case .string(let value) = $0 else { throw ConfigurationLibraryError.unreadable }
                    return value
                }
            }
            guard let name = string("name"), let type = string("type") else { throw ConfigurationLibraryError.unreadable }
            return Self(id: index, name: name, type: type, members: try strings("proxies"),
                providers: try strings("use"), includesAll: group.topLevelValue("include-all") == .scalar("true"),
                includesAllProxies: group.topLevelValue("include-all-proxies") == .scalar("true"),
                includesAllProviders: group.topLevelValue("include-all-providers") == .scalar("true"), document: group)
        }
    }
}

public enum ConfigurationRuleGroupError: LocalizedError, Equatable {
    case nameRequired
    case duplicate(String)
    case cycle(String)
    case inUse(String)
    public var errorDescription: String? {
        switch self {
        case .nameRequired: "Group name is required."
        case .duplicate(let name): "Group name is already in use: \(name)"
        case .cycle(let name): "Groups cannot refer back to themselves: \(name)"
        case .inUse(let name): "Change references to this group before deleting it: \(name)"
        }
    }
}

public extension ConfigurationRuleDraft {
     
    mutating func setGroup(_ document: OrderedJSON, groupID: UUID?) throws {
        var candidate = self
        guard case .string(let name) = document.topLevelValue("name"),
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ConfigurationRuleGroupError.nameRequired }
        if let groupID {
            guard let index = candidate.groups.firstIndex(where: { $0.id == groupID }) else { throw ConfigurationLibraryError.staleGeneration }
            let old = candidate.groups[index].name
            candidate.groups[index].document = document
            if name != old { candidate.rewriteReferences(from: old, to: name) }
        } else { candidate.groups.append(.init(id: UUID(), document: document)) }
        try candidate.validateGroupNamesAndCycles()
        self = candidate
    }
    mutating func removeGroups(_ ids: Set<UUID>) throws {
        var candidate = self
        let removed = candidate.groups.filter { ids.contains($0.id) }
        candidate.groups.removeAll { ids.contains($0.id) }
        let before = candidate.currentDocument()
        for group in removed {
            var probe = candidate
            probe.rewriteReferences(from: group.name, to: UUID().uuidString)
            guard probe.currentDocument() == before else { throw ConfigurationRuleGroupError.inUse(group.name) }
        }
        self = candidate
    }
    mutating func moveGroups(_ ids: Set<UUID>, before target: UUID?) {
        guard target.map({ !ids.contains($0) }) ?? true else { return }
        let moving = groups.filter { ids.contains($0.id) }
        groups.removeAll { ids.contains($0.id) }
        let index = target.flatMap { id in groups.firstIndex { $0.id == id } } ?? groups.endIndex
        groups.insert(contentsOf: moving, at: index)
    }
    private func validateGroupNamesAndCycles() throws {
        var names: Set<String> = ["DIRECT", "REJECT", "REJECT-DROP", "PASS", "PASS-RULE", "COMPATIBLE", "GLOBAL"]
        if case .array(let nodes) = additionalDocument.topLevelValue("proxies") {
            for node in nodes { if case .string(let name) = node.topLevelValue("name") { names.insert(name) } }
        }
        for group in groups {
            guard names.insert(group.name).inserted else { throw ConfigurationRuleGroupError.duplicate(group.name) }
        }
        let graph = Dictionary(uniqueKeysWithValues: groups.map { group -> (String, [String]) in
            guard case .array(let values) = group.document.topLevelValue("proxies") else { return (group.name, []) }
            return (group.name, values.compactMap { if case .string(let name) = $0 { return name }; return nil })
        })
        var visiting: Set<String> = [], visited: Set<String> = []
        func visit(_ name: String) throws {
            guard let edges = graph[name], !visited.contains(name) else { return }
            guard visiting.insert(name).inserted else { throw ConfigurationRuleGroupError.cycle(name) }
            for edge in edges { try visit(edge) }
            visiting.remove(name); visited.insert(name)
        }
        for group in groups { try visit(group.name) }
    }
    fileprivate static func validateReplay(_ document: OrderedJSON, baseline: OrderedJSON) throws {
        guard document.topLevelValue("rules") != nil else { return }
        let record = ConfigurationSourceRecord(label: "Replay", origin: .file("replay"))
        let source = ConfigurationSourcePayload(record: record, original: Data(), documentJSON: document.serialized())
        let scheme = ConfigurationRuleScheme(label: "Replay", kind: .custom, sourceID: record.id)
        let draft = try ConfigurationRuleDraft(scheme: scheme, payload: source)
        _ = try draft.document()
        try draft.validateGroupNamesAndCycles()
        let names = Set(draft.groups.map(\.name))
        for group in try ConfigurationRuleGroupSnapshot.read(baseline) where !names.contains(group.name) {
            var probe = draft
            probe.rewriteReferences(from: group.name, to: UUID().uuidString)
            guard probe.currentDocument() == draft.currentDocument() else {
                throw ConfigurationRuleReplay.Conflict(path: ["proxy-groups", group.name])
            }
        }
    }

    private mutating func rewriteReferences(from old: String, to new: String) {
        generatedRuleGroups = generatedRuleGroups.mapValues { $0 == old ? new : $0 }
        func reference(_ value: OrderedJSON) -> OrderedJSON { value == .string(old) ? .string(new) : value }
        func rule(_ raw: String) -> String {
            var fields = raw.components(separatedBy: ",")
            let kind = fields[0].trimmingCharacters(in: .whitespaces).uppercased()
            let index: Int
             
            switch kind {
            case "SUB-RULE": return raw
            case "MATCH", "FINAL": index = 1
            case "NOT", "OR", "AND", "DOMAIN-REGEX", "PROCESS-NAME-REGEX", "PROCESS-PATH-REGEX": index = fields.count - 1
            default: index = 2
            }
            guard fields.indices.contains(index), fields[index].trimmingCharacters(in: .whitespaces) == old else { return raw }
            fields[index] = new
            return fields.joined(separator: ",")
        }
        rows = rows.map { var row = $0; row.raw = rule(row.raw); return row }
        groups = groups.map { group in
            var group = group
            if case .array(let members) = group.document.topLevelValue("proxies") {
                group.document = group.document.settingTopLevel("proxies", to: .array(members.map(reference)))
            }
            for key in ["default-selected", "dialer-proxy"] {
                if let value = group.document.topLevelValue(key) { group.document = group.document.settingTopLevel(key, to: reference(value)) }
            }
            return group
        }
        if case .object(let sets) = additionalDocument.topLevelValue("sub-rules") {
            additionalDocument = additionalDocument.settingTopLevel("sub-rules", to: .object(sets.map { key, value in
                guard case .array(let values) = value else { return (key, value) }
                return (key, .array(values.map { if case .string(let raw) = $0 { return .string(rule(raw)) }; return $0 }))
            }))
        }
        for (key, field) in [("proxies", "dialer-proxy"), ("listeners", "proxy"), ("tunnels", "proxy")] {
            if case .array(let values) = additionalDocument.topLevelValue(key) {
                additionalDocument = additionalDocument.settingTopLevel(key, to: .array(values.map { value in
                    if key == "tunnels", case .string(let raw) = value {
                        var parts = raw.components(separatedBy: ",")
                        if parts.count == 4, parts[3].trimmingCharacters(in: .whitespaces) == old {
                            parts[3] = new
                            return .string(parts.joined(separator: ","))
                        }
                        return value
                    }
                    guard let target = value.topLevelValue(field) else { return value }
                    return value.settingTopLevel(field, to: reference(target))
                }))
            }
        }
        for key in ["proxy-providers", "rule-providers"] {
            if case .object(let providers) = additionalDocument.topLevelValue(key) {
                additionalDocument = additionalDocument.settingTopLevel(key, to: .object(providers.map { key, value in
                    var value = value
                    for field in ["proxy", "dialer-proxy"] {
                        if let target = value.topLevelValue(field) { value = value.settingTopLevel(field, to: reference(target)) }
                    }
                    if case .array(let nodes) = value.topLevelValue("payload") {
                        value = value.settingTopLevel("payload", to: .array(nodes.map { node in
                            guard let target = node.topLevelValue("dialer-proxy") else { return node }
                            return node.settingTopLevel("dialer-proxy", to: reference(target))
                        }))
                    }
                    if let override = value.topLevelValue("override"), let target = override.topLevelValue("dialer-proxy") {
                        value = value.settingTopLevel("override", to: override.settingTopLevel("dialer-proxy", to: reference(target)))
                    }
                    return (key, value)
                }))
            }
        }
        if let ntp = additionalDocument.topLevelValue("ntp"), let target = ntp.topLevelValue("dialer-proxy") {
            additionalDocument = additionalDocument.settingTopLevel("ntp", to: ntp.settingTopLevel("dialer-proxy", to: reference(target)))
        }
        func resolver(_ value: OrderedJSON) -> OrderedJSON {
            switch value {
            case .string(let raw):
                guard let hash = raw.firstIndex(of: "#") else { return value }
                let prefix = String(raw[...hash])
                let parts = raw[raw.index(after: hash)...].components(separatedBy: "&")
                let rewritten = parts.map { part -> String in
                    guard !part.contains("="), (part.removingPercentEncoding ?? part) == old else { return part }
                    return new.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed.subtracting(CharacterSet(charactersIn: "&=#"))) ?? new
                }
                return .string(prefix + rewritten.joined(separator: "&"))
            case .array(let values): return .array(values.map(resolver))
            case .object(let pairs): return .object(pairs.map { ($0.key, resolver($0.value)) })
            default: return value
            }
        }
        if var dns = additionalDocument.topLevelValue("dns") {
            for key in ["nameserver", "default-nameserver", "fallback", "proxy-server-nameserver", "direct-nameserver", "nameserver-policy", "proxy-server-nameserver-policy", "direct-nameserver-policy"] {
                if let value = dns.topLevelValue(key) { dns = dns.settingTopLevel(key, to: resolver(value)) }
            }
            additionalDocument = additionalDocument.settingTopLevel("dns", to: dns)
        }
    }
}

 
 
public enum ConfigurationRuleReplay {
    public struct Conflict: Error, Equatable, Sendable {
        public let path: [String]
    }

    public static func merge(baseline: OrderedJSON, local: OrderedJSON, incoming: OrderedJSON) throws -> OrderedJSON {
        let document = try mergeValue(baseline, local, incoming, path: [])!
        try ConfigurationRuleDraft.validateReplay(document, baseline: baseline)
        return document
    }

    private static func mergeValue(_ base: OrderedJSON?, _ local: OrderedJSON?, _ remote: OrderedJSON?, path: [String]) throws -> OrderedJSON? {
        if local == base { return remote }
        if remote == base || local == remote { return local }
        guard let base, let local, let remote else { throw Conflict(path: path) }
        if case .object(let b) = base, case .object(let l) = local, case .object(let r) = remote {
            return .object(try mergeEntries(b, l, r, path: path))
        }
        if case .array(let b) = base, case .array(let l) = local, case .array(let r) = remote {
            if path.last == "rules" || (path.count == 2 && path.first == "sub-rules") {
                func strings(_ values: [OrderedJSON]) throws -> [(key: String, value: OrderedJSON)] {
                    try values.map { value in
                        guard case .string(let key) = value else { throw Conflict(path: path) }
                        let kind = key.split(separator: ",", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces).uppercased()
                        return (kind == "MATCH" || kind == "FINAL" ? "\\0final" : key, value)
                    }
                }
                let be = try strings(b), le = try strings(l), re = try strings(r)
                let bs = Set(be.map(\.key)), ls = Set(le.map(\.key)), rs = Set(re.map(\.key))
                 
                 
                if !bs.subtracting(ls).intersection(bs.subtracting(rs)).isEmpty,
                   ls.subtracting(bs) != rs.subtracting(bs) { throw Conflict(path: path) }
                return .array(try mergeEntries(be, le, re, path: path).map(\.value))
            }
            if ["proxy-groups", "proxies", "listeners"].contains(path.last ?? "") {
                func named(_ values: [OrderedJSON]) throws -> [(key: String, value: OrderedJSON)] {
                    try values.map { value in
                        guard case .string(let key) = value.topLevelValue("name"), !key.isEmpty else { throw Conflict(path: path) }
                        return (key, value)
                    }
                }
                return .array(try mergeEntries(named(b), named(l), named(r), path: path).map(\.value))
            }
        }
        throw Conflict(path: path)
    }

    private static func mergeEntries(_ base: [(key: String, value: OrderedJSON)],
                                     _ local: [(key: String, value: OrderedJSON)],
                                     _ remote: [(key: String, value: OrderedJSON)], path: [String]) throws -> [(key: String, value: OrderedJSON)] {
        func map(_ entries: [(key: String, value: OrderedJSON)]) throws -> [String: OrderedJSON] {
            var result: [String: OrderedJSON] = [:]
            for entry in entries {
                guard result.updateValue(entry.value, forKey: entry.key) == nil else { throw Conflict(path: path) }
            }
            return result
        }
        let b = try map(base), l = try map(local), r = try map(remote)
        var values: [String: OrderedJSON] = [:]
        var keys: [String] = [], seen: Set<String> = []
        for entry in local + remote + base where seen.insert(entry.key).inserted { keys.append(entry.key) }
        for key in keys { values[key] = try mergeValue(b[key], l[key], r[key], path: path + [key]) }
        let surviving = Set(values.keys)
        let bk = base.map(\.key).filter(surviving.contains)
        let lk = local.map(\.key).filter(surviving.contains)
        let rk = remote.map(\.key).filter(surviving.contains)
        let existing = Set(bk)
        let lo = lk.filter(existing.contains), ro = rk.filter(existing.contains)
        if lo != bk && ro != bk && lo != ro { throw Conflict(path: path) }
        let order = lo != bk ? lo : ro
        var edges: [String: [String]] = [:], edgeSets: [String: Set<String>] = [:]
        var degrees = Dictionary(uniqueKeysWithValues: surviving.map { ($0, 0) })
        func link(_ from: String, _ to: String) {
            guard edgeSets[from, default: []].insert(to).inserted else { return }
            edges[from, default: []].append(to); degrees[to, default: 0] += 1
        }
        for (a, b) in zip(order, order.dropFirst()) { link(a, b) }
        for sequence in [lk, rk] {
            for (a, b) in zip(sequence, sequence.dropFirst()) where !existing.contains(a) || !existing.contains(b) { link(a, b) }
        }
         
         
        let rank = Dictionary(uniqueKeysWithValues: keys.enumerated().map { ($0.element, $0.offset) })
        var ready: [Int] = []
        func enqueue(_ value: Int) {
            ready.append(value)
            var child = ready.count - 1
            while child > 0 {
                let parent = (child - 1) / 2
                guard ready[child] < ready[parent] else { break }
                ready.swapAt(child, parent); child = parent
            }
        }
        func dequeue() -> Int {
            let value = ready[0], last = ready.removeLast()
            if !ready.isEmpty {
                ready[0] = last
                var parent = 0
                while parent * 2 + 1 < ready.count {
                    var child = parent * 2 + 1
                    if child + 1 < ready.count && ready[child + 1] < ready[child] { child += 1 }
                    guard ready[child] < ready[parent] else { break }
                    ready.swapAt(child, parent); parent = child
                }
            }
            return value
        }
        for (index, key) in keys.enumerated() where degrees[key] == 0 { enqueue(index) }
        var result: [(key: String, value: OrderedJSON)] = []
        while !ready.isEmpty {
            let key = keys[dequeue()]
            result.append((key, values[key]!))
            for next in edges[key] ?? [] {
                degrees[next]! -= 1
                if degrees[next] == 0 { enqueue(rank[next]!) }
            }
        }
        guard result.count == surviving.count else { throw Conflict(path: path) }
        return result
    }
}


public extension ConfigurationRuleDraft {
     
    mutating func replaceContents(_ document: OrderedJSON) throws {
        let record = ConfigurationSourceRecord(id: version.id, label: label, origin: .file(label), version: version.version)
        let parsed = try ConfigurationRuleDraft(scheme: .init(id: schemeID, label: label, kind: .custom, sourceID: version.id),
            payload: .init(record: record, original: Data(), documentJSON: document.serialized()))
        _ = try parsed.document()
        try parsed.validateGroupNamesAndCycles()
        let reconciled = parsed.preservingIdentity(from: self)
        groups = reconciled.groups; rows = reconciled.rows; additionalDocument = parsed.additionalDocument
        generatedRuleGroups = generatedRuleGroups.filter { key, name in
            containsRuleSet(key) && groups.contains(where: { $0.name == name })
        }
    }

    func containsRuleSet(_ key: String) -> Bool {
        rows.contains { $0.raw.hasPrefix("RULE-SET," + key + ",") }
    }

     
    public func ruleSetPolicy(_ key: String) -> String? {
        guard let row = rows.first(where: { $0.raw.hasPrefix("RULE-SET," + key + ",") }) else { return nil }
        return row.raw.split(separator: ",", maxSplits: 2, omittingEmptySubsequences: false).dropFirst(2).first.map(String.init)
    }

     
     
    public mutating func setRuleSetPolicy(_ key: String, policy: String) {
        guard let index = rows.firstIndex(where: { $0.raw.hasPrefix("RULE-SET," + key + ",") }) else { return }
        rows[index].raw = "RULE-SET," + key + "," + policy
        if let generated = generatedRuleGroups[key], generated != policy,
           let group = groups.first(where: { $0.name == generated }) {
            generatedRuleGroups.removeValue(forKey: key)
            try? removeGroups([group.id])
        }
    }

     
     
     
    public mutating func attachRuleSet(key: String, name: String, rules content: [String], policy: String) throws {
        if containsRuleSet(key) {
            var providers = additionalDocument.topLevelValue("rule-providers") ?? .object([])
            providers = providers.settingTopLevel(key, to: .object([
                ("type", .string("inline")), ("behavior", .string("classical")),
                ("payload", .array(content.map(OrderedJSON.string)))
            ]))
            additionalDocument = additionalDocument.settingTopLevel("rule-providers", to: providers)
            setRuleSetPolicy(key, policy: policy)
        } else {
            try addRuleSet(key: key, name: name, rules: content, defaultRoute: "proxy", policy: policy)
        }
    }

     
     
     
    mutating func addRuleSet(key: String, name: String, rules content: [String], defaultRoute: String, policy: String? = nil) throws {
        var candidate = self
        guard !containsRuleSet(key) else { return }
        var root = currentDocument()
        var providers = root.topLevelValue("rule-providers") ?? .object([])
        providers = providers.settingTopLevel(key, to: .object([
            ("type", .string("inline")), ("behavior", .string("classical")),
            ("payload", .array(content.map(OrderedJSON.string)))
        ]))
        root = root.settingTopLevel("rule-providers", to: providers)
        candidate.additionalDocument = root
        if let policy {
            candidate.rows.insert(.init(raw: "RULE-SET," + key + "," + policy), at: 0)
            self = candidate
            return
        }
        let policy = name
        if !candidate.groups.contains(where: { $0.name == policy }) {
            let target = defaultRoute == "proxy" ? candidate.groups.first?.name : nil
            let members = defaultRoute == "direct" ? ["DIRECT"] : defaultRoute == "reject" ? ["REJECT"] : target.map { [$0, "DIRECT"] } ?? ["DIRECT"]
            var group = OrderedJSON.object([("name", .string(policy)), ("type", .string("select")),
                ("proxies", .array(members.map(OrderedJSON.string)))])
            if defaultRoute == "proxy" && target == nil { group = group.settingTopLevel("include-all", to: .scalar("true")) }
            try candidate.setGroup(group, groupID: nil)
            candidate.generatedRuleGroups[key] = policy
        }
        candidate.rows.insert(.init(raw: "RULE-SET," + key + "," + policy), at: 0)
        self = candidate
    }

     
    mutating func updateLocalRuleSet(_ value: ConfigurationLocalRuleSet) throws {
        let key = "local-" + value.id
        guard containsRuleSet(key) else { return }
        var candidate = self
        if let name = generatedRuleGroups[key], let group = candidate.groups.first(where: { $0.name == name }), name != value.name {
            try candidate.setGroup(group.document.settingTopLevel("name", to: .string(value.name)), groupID: group.id)
        }
        var providers = candidate.additionalDocument.topLevelValue("rule-providers") ?? .object([])
        let provider = OrderedJSON.object([("type", .string("inline")), ("behavior", .string("classical")),
            ("payload", .array(value.rules.map(OrderedJSON.string)))])
        providers = providers.settingTopLevel(key, to: provider)
        candidate.additionalDocument = candidate.additionalDocument.settingTopLevel("rule-providers", to: providers)
        self = candidate
    }

    mutating func removeRuleSet(_ key: String) {
        rows.removeAll { $0.raw.hasPrefix("RULE-SET," + key + ",") }
        if let name = generatedRuleGroups.removeValue(forKey: key), let group = groups.first(where: { $0.name == name }) {
             
            try? removeGroups([group.id])
        }
        if case .object(let values) = additionalDocument.topLevelValue("rule-providers") {
            additionalDocument = additionalDocument.settingTopLevel("rule-providers", to: .object(values.filter { $0.key != key }))
        }
    }

    mutating func deleteRoutingGroup(_ id: UUID) throws {
        guard let group = groups.first(where: { $0.id == id }) else { return }
        var candidate = self
         
         
        candidate.rows.removeAll { row in
            let fields = row.raw.components(separatedBy: ",")
            guard !row.isFinal else { return false }
            return fields.count > 2 && fields[2] == group.name
        }
        try candidate.removeGroups([id])
        self = candidate
    }
}

 
 
 
 
 
 
public extension ConfigurationRuleDraft {
     
     
    private var pinnedFinalIndex: Int { rows.last?.isFinal == true ? rows.count - 1 : rows.count }

     
    mutating func moveRows(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let limit = pinnedFinalIndex
        guard !offsets.isEmpty, offsets.allSatisfy({ rows.indices.contains($0) && $0 < limit }) else { return }
        var movable = Array(rows[..<limit])
        let tail = Array(rows[limit...])
         
         
        let lifted = offsets.sorted().map { movable[$0] }
        for offset in offsets.sorted(by: >) { movable.remove(at: offset) }
        let target = min(destination, limit) - offsets.filter { $0 < min(destination, limit) }.count
        movable.insert(contentsOf: lifted, at: max(0, min(target, movable.count)))
        rows = movable + tail
    }

     
     
    mutating func moveRow(_ id: UUID, before target: UUID?) {
        let limit = pinnedFinalIndex
        guard let source = rows.firstIndex(where: { $0.id == id }), source < limit else { return }
        var movable = Array(rows[..<limit])
        let tail = Array(rows[limit...])
        let row = movable.remove(at: source)
        let index: Int
        if let target, let found = movable.firstIndex(where: { $0.id == target }) {
            index = found
        } else if target == nil || target == tail.first?.id {
            index = movable.endIndex
        } else {
            return
        }
        movable.insert(row, at: index)
        rows = movable + tail
    }

     
     
    mutating func moveRow(_ id: UUID, offset: Int) {
        let limit = pinnedFinalIndex
        guard let source = rows.firstIndex(where: { $0.id == id }), source < limit else { return }
        let destination = source + offset
        guard destination >= 0, destination < limit else { return }
        rows.swapAt(source, destination)
    }
}
