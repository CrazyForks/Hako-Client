import Foundation

public struct ConfigurationInput: Equatable, Sendable {
    public let id: String
    public let document: OrderedJSON
     
    public let resourcePaths: [String: String]
    public let hiddenProviderNames: Set<String>
    public let hiddenNodeNames: Set<String>
    public init(id: String, document: OrderedJSON, resourcePaths: [String: String] = [:], hiddenNodeNames: Set<String> = [], hiddenProviderNames: Set<String> = []) {
        self.id = id
        self.document = document
        self.resourcePaths = resourcePaths
        self.hiddenNodeNames = hiddenNodeNames
        self.hiddenProviderNames = hiddenProviderNames
    }
}

public struct ConfigurationComposition: Equatable, Sendable {
    public let document: OrderedJSON
    public let sourceIDs: [String]
}

public enum ConfigurationCompositionError: LocalizedError, Equatable {
    case duplicateSource(String)
    case invalidDocument(String)
    case duplicateName(source: String, name: String)
    case unresolvedDependency(source: String, name: String)

    public var errorDescription: String? {
        switch self {
        case .duplicateSource: return "A source was selected more than once."
        case .invalidDocument: return "A selected source is not a configuration object."
        case .duplicateName: return "Two entries in one source share a name. Rename one of them."
        case .unresolvedDependency(let source, let name):
            return "A selected source needs a proxy that no selected source supplies."
        }
    }
}

 
 
 
 
public enum ConfigurationComposer {
    public static func compose(
        sources: [ConfigurationInput],
        rules: ConfigurationInput
    ) throws -> ConfigurationComposition {
        var ids = Set<String>()
        for source in sources {
            guard !source.id.isEmpty, case .object = source.document else {
                throw ConfigurationCompositionError.invalidDocument(source.id)
            }
            guard ids.insert(source.id).inserted else {
                throw ConfigurationCompositionError.duplicateSource(source.id)
            }
        }
        guard case .object = rules.document else {
            throw ConfigurationCompositionError.invalidDocument(rules.id)
        }
        for input in sources + [rules] { try validateShape(input) }
         
         
        if sources.count == 1, sources[0] == rules {
            var document = rules.document
            for section in ["proxy-providers", "rule-providers"] {
                guard let providers = document.topLevelValue(section)?.compositionObject else { continue }
                document = document.settingTopLevel(section,to:.object(providers.map { pair in
                    guard pair.value.topLevelValue("type")?.compositionString == "file",
                          let path = pair.value.topLevelValue("path")?.compositionString,
                          let bound = rules.resourcePaths[path] else { return pair }
                    return (pair.key,pair.value.settingTopLevel("path",to:.string(bound)))
                }))
            }
            return ConfigurationComposition(document: document, sourceIDs: sources.map(\.id))
        }
        let groups = rules.document.topLevelValue("proxy-groups")?.compositionArray ?? []
        let groupNames = Set(groups.compactMap { $0.topLevelValue("name")?.compositionString })
        let nodeNames = try nameTable(sources, key: "proxies", preferred: rules.id, reserved: groupNames.union(builtins))
        let sourceGroupNames = Set(sources.flatMap {
            ($0.document.topLevelValue("proxy-groups")?.compositionArray ?? []).compactMap {
                $0.topLevelValue("name")?.compositionString
            }
        })
        let providerNames = try nameTable(sources, key: "proxy-providers", preferred: rules.id,
            reserved: groupNames.union(sourceGroupNames))
        var dependencyGroups = DependencyGroups(sources: sources, rules: rules, nodes: nodeNames,
            providers: providerNames, planGroups: groupNames)
        var nodes: [OrderedJSON] = []
        var localPaths: [String: String] = [:]
        var providers: [(key: String, value: OrderedJSON)] = []
        for source in sources {
            for node in source.document.topLevelValue("proxies")?.compositionArray ?? [] {
                guard let name = node.topLevelValue("name")?.compositionString,
                      let mapped = nodeNames[source.id]?[name] else {
                    throw ConfigurationCompositionError.invalidDocument(source.id)
                }
                var value = node.settingTopLevel("name", to: .string(mapped))
                if let dialer = node.topLevelValue("dialer-proxy")?.compositionString {
                    value = value.settingTopLevel("dialer-proxy", to: .string(
                        try dependencyGroups.resolve(dialer, source: source.id)
                    ))
                }
                nodes.append(value)
            }
            for pair in source.document.topLevelValue("proxy-providers")?.compositionObject ?? [] {
                guard let name = providerNames[source.id]?[pair.key] else { continue }
                var value = pair.value
                if let proxy = value.topLevelValue("proxy")?.compositionString {
                    value = value.settingTopLevel("proxy", to: .string(
                        try dependencyGroups.resolve(proxy, source: source.id)
                    ))
                }
                if let dialer = value.topLevelValue("override")?.topLevelValue("dialer-proxy")?.compositionString,
                   let override = value.topLevelValue("override") {
                    value = value.settingTopLevel("override", to: override.settingTopLevel("dialer-proxy", to:
                        .string(try dependencyGroups.resolve(dialer, source: source.id))))
                }
                 
                 
                 
                if value.topLevelValue("type")?.compositionString == "http" {
                    value = value.removingTopLevel("path")
                }
                if value.topLevelValue("type")?.compositionString == "file",
                   let original = value.topLevelValue("path")?.compositionString {
                    guard let path = source.resourcePaths[original] else {
                        throw ConfigurationCompositionError.unresolvedDependency(source: source.id, name: original)
                    }
                    if let owner = localPaths[path], owner != source.id {
                        throw ConfigurationCompositionError.unresolvedDependency(source: source.id, name: original)
                    }
                    localPaths[path] = source.id
                    value = value.settingTopLevel("path", to: .string(path))
                }
                providers.append((name, value))
            }
        }
        let originalNodes = Set((rules.document.topLevelValue("proxies")?.compositionArray ?? [])
            .compactMap { $0.topLevelValue("name")?.compositionString })
        let originalProviders = Set((rules.document.topLevelValue("proxy-providers")?.compositionObject ?? []).map(\.key))
        let hiddenNames = sources.flatMap { source in
            source.hiddenNodeNames.compactMap { nodeNames[source.id]?[$0] }
        }.sorted()
        let hiddenProviders = Set(sources.flatMap { source in
            source.hiddenProviderNames.compactMap { providerNames[source.id]?[$0] }
        })
        var outputGroups: [OrderedJSON] = []
        for group in groups {
            var value = group
            let members = group.topLevelValue("proxies")?.compositionArray ?? []
            let uses = group.topLevelValue("use")?.compositionArray ?? []
            let takesNodes = members.contains { originalNodes.contains($0.compositionString ?? "") }
            let takesProviders = !uses.isEmpty
            let includes = ["include-all", "include-all-proxies", "include-all-providers"]
                .contains { group.topLevelValue($0) == .scalar("true") }
            var rewritten: [OrderedJSON] = []
            for member in members {
                guard let name = member.compositionString else { rewritten.append(member); continue }
                if originalNodes.contains(name) {
                    if let mapped = nodeNames[rules.id]?[name],
                       let filter = group.topLevelValue("filter")?.compositionString, !filter.isEmpty {
                         
                         
                         
                        rewritten.append(.string(mapped))
                    }
                     
                     
                } else {
                    rewritten.append(member)  
                }
            }
            if group.topLevelValue("proxies") != nil {
                value = value.settingTopLevel("proxies", to: .array(rewritten))
            }
            if takesNodes || takesProviders || includes {
                 
                 
                value = value.settingTopLevel("include-all-proxies", to: .scalar("true"))
                if !providers.isEmpty {
                    value = value.settingTopLevel("use", to: .array(providers.map { .string($0.key) }))
                } else {
                    let unknown = uses.filter { !originalProviders.contains($0.compositionString ?? "") }
                    value = unknown.isEmpty ? value.removingTopLevel("use")
                        : value.settingTopLevel("use", to: .array(unknown))
                }
            }
            if !hiddenNames.isEmpty {
                let hidden = "^(" + hiddenNames.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|") + ")$"
                let existing = value.topLevelValue("exclude-filter")?.compositionString ?? ""
                value = value.settingTopLevel("exclude-filter", to: .string(existing.isEmpty ? hidden : "(" + existing + ")|" + hidden))
            }
            if !hiddenProviders.isEmpty && (takesNodes || takesProviders || includes) {
                value = value.removingTopLevel("include-all").removingTopLevel("include-all-providers")
                    .settingTopLevel("use", to: .array(providers.filter { !hiddenProviders.contains($0.key) }.map { .string($0.key) }))
            }
            outputGroups.append(value)
        }
        var result = rules.document
            .settingTopLevel("proxies", to: .array(nodes))
            .settingTopLevel("proxy-providers", to: .object(providers))
        if !dependencyGroups.output.isEmpty || rules.document.topLevelValue("proxy-groups") != nil {
            result = result.settingTopLevel("proxy-groups", to: .array(outputGroups + dependencyGroups.output))
        }
         
         
        func rewriteRules(_ value: OrderedJSON) throws -> OrderedJSON {
            guard let rows = value.compositionArray else { return value }
            return .array(try rows.map { rule in
                guard let text = rule.compositionString else { return rule }
                var fields = text.components(separatedBy: ",")
                let type = fields[0].trimmingCharacters(in: .whitespaces).uppercased()
                guard type != "SUB-RULE" else { return rule }
                 
                 
                let index: Int
                switch type {
                case "MATCH": index = 1
                case "NOT", "OR", "AND", "DOMAIN-REGEX", "PROCESS-NAME-REGEX", "PROCESS-PATH-REGEX":
                    index = fields.count - 1
                default: index = 2
                }
                guard fields.indices.contains(index) else { return rule }
                let target = fields[index].trimmingCharacters(in: .whitespaces)
                if originalNodes.contains(target) {
                    fields[index] = try dependency(target, source: rules.id, nodes: nodeNames, groups: groupNames)
                }
                return .string(fields.joined(separator: ","))
            })
        }
        if let rows = result.topLevelValue("rules") {
            result = result.settingTopLevel("rules", to: try rewriteRules(rows))
        }
        if let subrules = result.topLevelValue("sub-rules")?.compositionObject {
            result = result.settingTopLevel("sub-rules", to: .object(try subrules.map {
                ($0.key, try rewriteRules($0.value))
            }))
        }
        return ConfigurationComposition(document: result, sourceIDs: sources.map(\.id))
    }

    private static func validateShape(_ input: ConfigurationInput) throws {
        for key in ["proxies", "proxy-groups", "rules"] {
            if let value = input.document.topLevelValue(key), value.compositionArray == nil {
                throw ConfigurationCompositionError.invalidDocument(input.id + ": " + key)
            }
        }
        for key in ["proxy-providers", "rule-providers", "sub-rules"] {
            if let value = input.document.topLevelValue(key), value.compositionObject == nil {
                throw ConfigurationCompositionError.invalidDocument(input.id + ": " + key)
            }
        }
    }

     
     
    private struct DependencyGroups {
        let sources: [ConfigurationInput]
        let rules: ConfigurationInput
        let nodes: [String: [String: String]]
        let providers: [String: [String: String]]
        let planGroups: Set<String>
        var names: [String: [String: String]] = [:]
        var output: [OrderedJSON] = []
        var visited: Set<String> = []

        mutating func resolve(_ name: String, source id: String) throws -> String {
            if let node = nodes[id]?[name] { return node }
            if builtins.contains(name) { return name }
            if id == rules.id, planGroups.contains(name) { return name }
            guard let source = sources.first(where: { $0.id == id }),
                  let original = source.document.topLevelValue("proxy-groups")?.compositionArray?
                    .first(where: { $0.topLevelValue("name")?.compositionString == name }) else {
                throw ConfigurationCompositionError.unresolvedDependency(source: id, name: name)
            }
            if names.isEmpty {
                let allNodes = Set(nodes.values.flatMap { $0.values })
                names = try nameTable(sources.filter { $0.id != rules.id }, key: "proxy-groups",
                    preferred: rules.id, reserved: planGroups.union(allNodes).union(builtins))
            }
            guard let mapped = names[id]?[name] else {
                throw ConfigurationCompositionError.unresolvedDependency(source: id, name: name)
            }
            let key = id + "\u{0}" + name
            guard visited.insert(key).inserted else { return mapped }  
            var group = original.settingTopLevel("name", to: .string(mapped))
            var members = try (original.topLevelValue("proxies")?.compositionArray ?? []).map { item in
                guard let target = item.compositionString else { return item }
                return OrderedJSON.string(try resolve(target, source: id))
            }
            let includeNodes = ["include-all", "include-all-proxies"].contains {
                original.topLevelValue($0) == .scalar("true")
            }
            if includeNodes {
                 
                 
                 
                if let filter = original.topLevelValue("filter")?.compositionString, !filter.isEmpty {
                    throw ConfigurationCompositionError.unresolvedDependency(source: id, name: name + " (filtered dependency)")
                }
                members += (source.document.topLevelValue("proxies")?.compositionArray ?? []).compactMap {
                    $0.topLevelValue("name")?.compositionString.flatMap { nodes[id]?[$0] }.map(OrderedJSON.string)
                }
            }
            var uses = original.topLevelValue("use")?.compositionArray ?? []
            if ["include-all", "include-all-providers"].contains(where: { original.topLevelValue($0) == .scalar("true") }) {
                uses = (source.document.topLevelValue("proxy-providers")?.compositionObject ?? []).map { .string($0.key) }
            }
            uses = try uses.map { item in
                guard let key = item.compositionString, let provider = providers[id]?[key] else {
                    throw ConfigurationCompositionError.unresolvedDependency(source: id, name: item.serialized())
                }
                return .string(provider)
            }
            for key in ["include-all", "include-all-proxies", "include-all-providers"] { group = group.removingTopLevel(key) }
            group = group.settingTopLevel("proxies", to: .array(members))
            if !uses.isEmpty { group = group.settingTopLevel("use", to: .array(uses)) }
            output.append(group)
            return mapped
        }
    }

    private static let builtins: Set<String> = ["DIRECT", "REJECT", "REJECT-DROP", "PASS", "COMPATIBLE", "GLOBAL"]

    private static func dependency(
        _ name: String, source: String, nodes: [String: [String: String]], groups: Set<String>
    ) throws -> String {
        if let mapped = nodes[source]?[name] { return mapped }
        if groups.contains(name) || builtins.contains(name) { return name }
        throw ConfigurationCompositionError.unresolvedDependency(source: source, name: name)
    }

    private static func nameTable(
        _ sources: [ConfigurationInput], key: String, preferred: String, reserved: Set<String>
    ) throws -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        var owners: [String: [String]] = [:]
        for source in sources {
            let names: [String]
            if key != "proxy-providers" {
                let rows = source.document.topLevelValue(key)?.compositionArray ?? []
                names = rows.compactMap { $0.topLevelValue("name")?.compositionString }
                guard names.count == rows.count else { throw ConfigurationCompositionError.invalidDocument(source.id) }
            } else {
                names = (source.document.topLevelValue(key)?.compositionObject ?? []).map(\.key)
            }
            var seen = Set<String>()
            for name in names {
                guard !name.isEmpty, seen.insert(name).inserted else {
                    throw ConfigurationCompositionError.duplicateName(source: source.id, name: name)
                }
                owners[name, default: []].append(source.id)
            }
            result[source.id] = [:]
        }
        var used = reserved.union(owners.keys)
        for name in owners.keys.sorted() {
            let sourceIDs = owners[name]!.sorted()
            let primary = sourceIDs.contains(preferred) ? preferred : sourceIDs[0]
            for id in sourceIDs {
                if id == primary && !reserved.contains(name) {
                    result[id]![name] = name
                } else {
                    let base = "[\(id)] \(name)"
                    var candidate = base
                    var suffix = 2
                    while used.contains(candidate) { candidate = "\(base) (\(suffix))"; suffix += 1 }
                    used.insert(candidate)
                    result[id]![name] = candidate
                }
            }
        }
        return result
    }
}

private extension OrderedJSON {
    var compositionArray: [OrderedJSON]? { if case .array(let values) = self { return values }; return nil }
    var compositionObject: [(key: String, value: OrderedJSON)]? { if case .object(let values) = self { return values }; return nil }
    var compositionString: String? { if case .string(let value) = self { return value }; return nil }
}
