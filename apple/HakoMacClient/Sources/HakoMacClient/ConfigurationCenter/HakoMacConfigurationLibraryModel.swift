import Foundation
import HakoClientKit
import HakoClientUI

 
 
 
 
 
 
public struct HakoMacConfigurationLibraryActions {
     
    public var load: @Sendable () async throws -> ConfigurationLibrarySnapshot
     
    public var renameSource: @MainActor (String, String, UInt64) async throws -> ConfigurationLibrarySnapshot
     
    public var deleteSource: @MainActor (String, UInt64) async throws -> ConfigurationLibrarySnapshot
     
     
    public var updateSource: @MainActor (String) async throws -> Void
     
    public var deleteRuleScheme: @MainActor (String, UInt64) async throws -> ConfigurationLibrarySnapshot
     
     
    public var addSource: @MainActor (ConfigurationSourcePayload, UInt64) async throws -> ConfigurationLibrarySnapshot
     
     
    public var addRuleScheme: @MainActor (ConfigurationSourcePayload, UInt64) async throws -> ConfigurationLibrarySnapshot
     
     
    public var copyScheme: @MainActor (String, String, UInt64) async throws -> ConfigurationLibrarySnapshot
     
     
    public var loadCollections: @Sendable (ConfigurationLibrarySnapshot) async throws -> [ConfigurationCollectionEntry] = { _ in [] }
     
     
     
    public var updateSourceReplacingRules: @MainActor (String, String?) async throws -> Void = { _, _ in
        throw ConfigurationLibraryError.unreadable
    }
     
     
     
     
    public var updateAllSources: (@MainActor (_ progress: @escaping @MainActor (String) -> Void) async -> HakoMacBatchOutcome)?
     
     
    public var updateAllRuleSets: (@MainActor (_ progress: @escaping @MainActor (String) -> Void) async -> HakoMacBatchOutcome)?
     
     
     
    public var saveSourceDetails: @MainActor (String, String, ConfigurationSourceSettingsDraft?, UInt64) async throws -> ConfigurationLibrarySnapshot = { _, _, _, _ in
        throw ConfigurationLibraryError.unreadable
    }
     
     
     
    public var syncLegacyProfiles: (@MainActor (_ progress: @escaping @MainActor (String) -> Void) async -> HakoMacBatchOutcome)?
     
    public var saveSourceSettings: @MainActor (String, ConfigurationSourceSettingsDraft, UInt64) async throws -> ConfigurationLibrarySnapshot = { _, _, _ in
        throw ConfigurationLibraryError.unreadable
    }

    public init(
        load: @escaping @Sendable () async throws -> ConfigurationLibrarySnapshot,
        renameSource: @escaping @MainActor (String, String, UInt64) async throws -> ConfigurationLibrarySnapshot,
        deleteSource: @escaping @MainActor (String, UInt64) async throws -> ConfigurationLibrarySnapshot,
        updateSource: @escaping @MainActor (String) async throws -> Void,
        deleteRuleScheme: @escaping @MainActor (String, UInt64) async throws -> ConfigurationLibrarySnapshot,
        addSource: @escaping @MainActor (ConfigurationSourcePayload, UInt64) async throws -> ConfigurationLibrarySnapshot = { _, _ in
            throw ConfigurationLibraryError.unreadable
        },
        addRuleScheme: @escaping @MainActor (ConfigurationSourcePayload, UInt64) async throws -> ConfigurationLibrarySnapshot = { _, _ in
            throw ConfigurationLibraryError.unreadable
        },
        copyScheme: @escaping @MainActor (String, String, UInt64) async throws -> ConfigurationLibrarySnapshot = { _, _, _ in
            throw ConfigurationLibraryError.unreadable
        }
    ) {
        self.load = load
        self.renameSource = renameSource
        self.deleteSource = deleteSource
        self.updateSource = updateSource
        self.deleteRuleScheme = deleteRuleScheme
        self.addSource = addSource
        self.addRuleScheme = addRuleScheme
        self.copyScheme = copyScheme
    }

     
     
    public static var unavailable: HakoMacConfigurationLibraryActions {
        HakoMacConfigurationLibraryActions(
            load: { ConfigurationLibrarySnapshot() },
            renameSource: { _, _, _ in throw ConfigurationLibraryError.unreadable },
            deleteSource: { _, _ in throw ConfigurationLibraryError.unreadable },
            updateSource: { _ in throw ConfigurationLibraryError.unreadable },
            deleteRuleScheme: { _, _ in throw ConfigurationLibraryError.unreadable }
        )
    }
}

 
public enum HakoMacNodeLibraryGroup: CaseIterable, Sendable {
    case subscriptions, files, customNodes, proxyChains

     
    public var title: String {
        switch self {
        case .subscriptions: "From Profile URLs"
        case .files: "From Files"
        case .customNodes: "Custom Nodes"
        case .proxyChains: "Proxy Chains"
        }
    }

    public var identifier: String {
        switch self {
        case .subscriptions: "config-urls"
        case .files: "files"
        case .customNodes: "custom-nodes"
        case .proxyChains: "proxy-chains"
        }
    }

     
     
    public func contains(_ source: ConfigurationSourceRecord) -> Bool {
        if source.nodeChain != nil { return self == .proxyChains }
        switch source.origin {
        case .subscription: return self == .subscriptions
        case .file: return self == .files
        case .customNodes: return self == .customNodes
        case .bundled: return false
        }
    }
}

public struct HakoMacNodeLibraryShelf: Identifiable, Equatable {
    public let group: HakoMacNodeLibraryGroup
    public let sources: [ConfigurationSourceRecord]
    public var id: String { group.identifier }
}

public struct HakoMacRuleLibraryShelf: Identifiable, Equatable {
    public let section: HakoConfigurationRuleLibrarySection
    public let schemes: [ConfigurationRuleScheme]
    public var id: String { section.title }
}

 
 
 
 
 
 
@MainActor
public final class HakoMacConfigurationLibraryModel: ObservableObject {
    public enum Phase: Equatable, Sendable {
        case idle, loading, ready
        case failed(String)
    }

    @Published public private(set) var snapshot = ConfigurationLibrarySnapshot()
     
     
     
     
    @Published public private(set) var nodeShelves: [HakoMacNodeLibraryShelf] = []
    @Published public private(set) var ruleShelves: [HakoMacRuleLibraryShelf] = []
     
    @Published public private(set) var schemeUsage: [String: Int] = [:]
     
    @Published public private(set) var collections: [ConfigurationCollectionEntry] = []
    private var collectionsGeneration: UInt64?
    @Published public private(set) var phase: Phase = .idle
     
    @Published public private(set) var isBusy = false
     
    @Published public private(set) var updatingSourceIDs: Set<String> = []
     
    @Published public private(set) var lastError: String?
     
    @Published public private(set) var updateProgress: String?
     
    @Published public private(set) var updateStatus: String?
     
    @Published public private(set) var updateError: String?
    public var isUpdatingAll: Bool { updateProgress != nil }
     
     
    @Published public private(set) var updateFailures: [String: String] = [:]
     
     
     
    @Published public private(set) var ruleConflictSourceID: String?

    private let actions: HakoMacConfigurationLibraryActions

    public init(actions: HakoMacConfigurationLibraryActions) {
        self.actions = actions
    }

    public func reload() async {
        if phase != .ready { phase = .loading }
        do {
            let loaded = try await actions.load()
            _ = apply(loaded)
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

     
    @discardableResult
    public func apply(_ next: ConfigurationLibrarySnapshot) -> Bool {
        guard next.generation >= snapshot.generation else { return false }
        guard next != snapshot || phase != .ready else { return true }
        snapshot = next
        nodeShelves = Self.nodeShelves(next)
        ruleShelves = Self.ruleShelves(next)
        schemeUsage = next.recipes.reduce(into: [:]) { counts, recipe in counts[recipe.ruleSchemeID, default: 0] += 1 }
        refreshCollections(next)
        return true
    }

    private func refreshCollections(_ next: ConfigurationLibrarySnapshot) {
        guard collectionsGeneration != next.generation else { return }
        collectionsGeneration = next.generation
        let load = actions.loadCollections
        Task { [weak self] in
            let loaded = (try? await load(next)) ?? []
            await MainActor.run {
                guard let self, self.collectionsGeneration == next.generation else { return }
                self.collections = loaded
            }
        }
    }

     
    public func collections(for sourceID: String, kind: ConfigurationCollection.Kind = .nodes) -> [ConfigurationCollectionEntry] {
        collections.filter { $0.source.id == sourceID && $0.id.kind == kind }
    }

    @discardableResult
    public func saveSourceSettings(_ id: String, draft: ConfigurationSourceSettingsDraft) async -> Bool {
        await write { [actions] generation in try await actions.saveSourceSettings(id, draft, generation) }
    }

     
     
    @discardableResult
    public func saveSourceDetails(_ id: String, label: String, settings: ConfigurationSourceSettingsDraft?) async -> Bool {
        await write { [actions] generation in try await actions.saveSourceDetails(id, label, settings, generation) }
    }

    public func clearError() { lastError = nil }

     
     
     
    public func report(_ message: String) { lastError = message }

    @discardableResult
    public func renameSource(_ id: String, label: String) async -> Bool {
        await write { [actions] generation in try await actions.renameSource(id, label, generation) }
    }

    @discardableResult
    public func deleteSource(_ id: String) async -> Bool {
        await write { [actions] generation in try await actions.deleteSource(id, generation) }
    }

    @discardableResult
    public func deleteRuleScheme(_ id: String) async -> Bool {
        await write { [actions] generation in try await actions.deleteRuleScheme(id, generation) }
    }

     
     
    public func addSource(_ payload: ConfigurationSourcePayload) async throws {
        try await writeOrThrow { [actions] generation in try await actions.addSource(payload, generation) }
    }

    public func addRuleScheme(_ payload: ConfigurationSourcePayload) async throws {
        try await writeOrThrow { [actions] generation in try await actions.addRuleScheme(payload, generation) }
    }

     
     
    public func copyScheme(_ id: String, label: String) async throws -> String {
        let before = Set(snapshot.rules.map(\.id))
        try await writeOrThrow { [actions] generation in try await actions.copyScheme(id, label, generation) }
        guard let made = snapshot.rules.first(where: { !before.contains($0.id) }) else {
            throw ConfigurationLibraryError.unreadable
        }
        return made.id
    }

    private func writeOrThrow(_ operation: (UInt64) async throws -> ConfigurationLibrarySnapshot) async throws {
        guard !isBusy else { throw ConfigurationLibraryError.busy }
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        let next = try await operation(snapshot.generation)
        _ = apply(next)
    }

     
     
     
    public func updateAllSources() async {
        guard updateProgress == nil else { return }
        guard let batch = actions.updateAllSources else {
            for source in snapshot.sources {
                if case .subscription = source.origin { _ = await updateSource(source.id) }
            }
            return
        }
        await runBatch(batch, statusKey: "Resources updated")
    }

     
     
    public func updateAllRuleSets() async {
        guard updateProgress == nil, let batch = actions.updateAllRuleSets else { return }
        await runBatch(batch, statusKey: "Rule sets updated")
    }

     
     
     
    public func updateEverything() async {
        guard updateProgress == nil else { return }
        let legacy = actions.syncLegacyProfiles
        let sources = actions.updateAllSources
        let rules = actions.updateAllRuleSets
        guard legacy != nil || sources != nil || rules != nil else { return }
        await runBatch({ progress in
            var total = HakoMacBatchOutcome()
            for stage in [legacy, sources, rules].compactMap({ $0 }) {
                let outcome = await stage(progress)
                total.updated += outcome.updated
                total.failures += outcome.failures
            }
            return total
        }, statusKey: "Resources updated")
    }

     
     
     
     
    public var hasLinkedNodes: Bool {
        snapshot.availableSources.contains { if case .subscription = $0.origin { return $0.isRetainedSnapshot != true && $0.suppliesNodes }; return false }
            || collections.contains { $0.collection.id.kind == .nodes && $0.collection.type == "http" && $0.source.isRetainedSnapshot != true }
    }

     
     
    public var hasLinkedRuleSets: Bool {
        collections.contains { $0.collection.id.kind == .rules && $0.collection.type == "http" && $0.source.isRetainedSnapshot != true }
    }

    public func hasLinkedContent(legacyProfiles: Bool) -> Bool {
        legacyProfiles
            || snapshot.availableSources.contains { if case .subscription = $0.origin { return $0.isRetainedSnapshot != true }; return false }
            || collections.contains { $0.collection.type == "http" && $0.source.isRetainedSnapshot != true }
    }

    private func runBatch(
        _ batch: @MainActor (_ progress: @escaping @MainActor (String) -> Void) async -> HakoMacBatchOutcome, statusKey: String
    ) async {
        updateProgress = ""
        updateStatus = nil
        updateError = nil
        let outcome = await batch { [weak self] line in self?.updateProgress = line }
        await reload()
         
        collectionsGeneration = nil
        refreshCollections(snapshot)
        updateProgress = nil
        updateStatus = HakoCopy.string(statusKey, locale: .current) + ": " + String(outcome.updated)
        updateError = outcome.failures.isEmpty ? nil : outcome.failures.joined(separator: "\n")
    }

    public func clearUpdateStatus() { updateStatus = nil; updateError = nil }

     
     
    @discardableResult
    public func updateSource(_ id: String, replacingRules: Bool = false) async -> Bool {
        guard !updatingSourceIDs.contains(id) else { return false }
        updatingSourceIDs.insert(id)
        lastError = nil
        updateFailures[id] = nil
        ruleConflictSourceID = nil
        defer { updatingSourceIDs.remove(id) }
        do {
            if replacingRules {
                let version = snapshot.sources.first { $0.id == id }?.version
                try await actions.updateSourceReplacingRules(id, version)
            } else {
                try await actions.updateSource(id)
            }
            await reload()
            return true
        } catch {
            if error is ConfigurationRuleReplay.Conflict {
                ruleConflictSourceID = id
            } else {
                updateFailures[id] = HakoConfigurationUpdateCopy.message(error, locale: .current)
                lastError = error.localizedDescription
            }
            return false
        }
    }

    public func dismissRuleConflict() { ruleConflictSourceID = nil }

    private func write(_ operation: (UInt64) async throws -> ConfigurationLibrarySnapshot) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        do {
            let next = try await operation(snapshot.generation)
            _ = apply(next)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

     

     
    nonisolated public static func nodeShelves(_ snapshot: ConfigurationLibrarySnapshot) -> [HakoMacNodeLibraryShelf] {
        let sources = snapshot.availableSources.filter(\.suppliesNodes)
        return HakoMacNodeLibraryGroup.allCases.compactMap { group in
            let members = sources.filter { group.contains($0) }
            return members.isEmpty ? nil : HakoMacNodeLibraryShelf(group: group, sources: members)
        }
    }

     
     
    nonisolated public static func ruleShelves(_ snapshot: ConfigurationLibrarySnapshot) -> [HakoMacRuleLibraryShelf] {
        let schemes = snapshot.availableRules
            + ConfigurationBuiltins.schemes.filter { builtin in !snapshot.rules.contains { $0.id == builtin.id } }
        return HakoConfigurationRuleLibrarySection.allCases.compactMap { section in
            let members = schemes.filter { section.contains($0, library: snapshot) }
            return members.isEmpty ? nil : HakoMacRuleLibraryShelf(section: section, schemes: members)
        }
    }

     
    public func configurations(usingSource id: String) -> [String] {
        snapshot.recipes
            .filter { recipe in recipe.dependencies.contains { $0.id == id } }
            .map(\.label)
    }

     
    public func configurations(usingScheme id: String) -> [String] {
        snapshot.recipes.filter { $0.ruleSchemeID == id }.map(\.label)
    }

     
     
    public func usageCount(ofScheme id: String) -> Int { schemeUsage[id] ?? 0 }

     
    public func source(of scheme: ConfigurationRuleScheme) -> ConfigurationSourceRecord? {
        snapshot.sources.first { $0.id == scheme.sourceID }
    }
}

 
public enum HakoMacSubscriptionUsageCopy {
     
     
    @MainActor private static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter
    }()
    private static let dateFormatters = HakoMacDateFormatterCache(dateStyle: .medium, timeStyle: .none)

     
    @MainActor public static func traffic(_ usage: ConfigurationSubscriptionUsage) -> HakoDisplayText {
        let formatter = bytes
        let used = formatter.string(fromByteCount: usage.used)
        guard usage.total > 0 else { return .format("Used %@", [used]) }
        return .format("%@ of %@ used", [used, formatter.string(fromByteCount: usage.total)])
    }

     
    public static func expiry(_ usage: ConfigurationSubscriptionUsage, locale: Locale) -> HakoDisplayText? {
        guard usage.expire > 0 else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(usage.expire))
        return .format("Expires %@", [dateFormatters.formatter(for: locale).string(from: date)])
    }
}

 
 
public final class HakoMacDateFormatterCache: @unchecked Sendable {
    private let dateStyle: DateFormatter.Style
    private let timeStyle: DateFormatter.Style
    private var formatters: [String: DateFormatter] = [:]
    private let lock = NSLock()

    public init(dateStyle: DateFormatter.Style, timeStyle: DateFormatter.Style) {
        self.dateStyle = dateStyle
        self.timeStyle = timeStyle
    }

    public func formatter(for locale: Locale) -> DateFormatter {
        lock.lock(); defer { lock.unlock() }
        if let cached = formatters[locale.identifier] { return cached }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        formatters[locale.identifier] = formatter
        return formatter
    }
}

 
 
public struct HakoMacBatchOutcome: Sendable {
    public var updated: Int
    public var failures: [String]
    public init(updated: Int = 0, failures: [String] = []) { self.updated = updated; self.failures = failures }
}

extension ConfigurationRuleScheme {
     
     
    var canBeDeleted: Bool {
        !ConfigurationBuiltins.isNative(id) && isRetainedSnapshot != true
            && (kind == .imported || kind == .custom || kind == .supplied)
    }
}
