import Foundation
import HakoClientKit
import HakoClientUI

 
 
 
 
 
 
public struct HakoMacConfigurationLibraryActions {
     
    public var load: @Sendable () async throws -> ConfigurationLibrarySnapshot
     
    public var renameSource: @MainActor (String, String, UInt64) async throws -> ConfigurationLibrarySnapshot
     
    public var deleteSource: @MainActor (String, UInt64) async throws -> ConfigurationLibrarySnapshot
     
     
    public var updateSource: @MainActor (String) async throws -> Void
     
    public var deleteRuleScheme: @MainActor (String, UInt64) async throws -> ConfigurationLibrarySnapshot

    public init(
        load: @escaping @Sendable () async throws -> ConfigurationLibrarySnapshot,
        renameSource: @escaping @MainActor (String, String, UInt64) async throws -> ConfigurationLibrarySnapshot,
        deleteSource: @escaping @MainActor (String, UInt64) async throws -> ConfigurationLibrarySnapshot,
        updateSource: @escaping @MainActor (String) async throws -> Void,
        deleteRuleScheme: @escaping @MainActor (String, UInt64) async throws -> ConfigurationLibrarySnapshot
    ) {
        self.load = load
        self.renameSource = renameSource
        self.deleteSource = deleteSource
        self.updateSource = updateSource
        self.deleteRuleScheme = deleteRuleScheme
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
        case .subscriptions: "From Subscriptions"
        case .files: "From Files"
        case .customNodes: "Custom Nodes"
        case .proxyChains: "Proxy Chains"
        }
    }

    public var identifier: String {
        switch self {
        case .subscriptions: "subscriptions"
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
    @Published public private(set) var phase: Phase = .idle
     
    @Published public private(set) var isBusy = false
     
    @Published public private(set) var updatingSourceIDs: Set<String> = []
     
    @Published public private(set) var lastError: String?

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
        snapshot = next
        return true
    }

    public func clearError() { lastError = nil }

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

     
     
    @discardableResult
    public func updateSource(_ id: String) async -> Bool {
        guard !updatingSourceIDs.contains(id) else { return false }
        updatingSourceIDs.insert(id)
        lastError = nil
        defer { updatingSourceIDs.remove(id) }
        do {
            try await actions.updateSource(id)
            await reload()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

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

     
    public func source(of scheme: ConfigurationRuleScheme) -> ConfigurationSourceRecord? {
        snapshot.sources.first { $0.id == scheme.sourceID }
    }
}

 
public enum HakoMacSubscriptionUsageCopy {
     
    public static func traffic(_ usage: ConfigurationSubscriptionUsage) -> HakoDisplayText {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        let used = formatter.string(fromByteCount: usage.used)
        guard usage.total > 0 else { return .format("Used %@", [used]) }
        return .format("%@ of %@ used", [used, formatter.string(fromByteCount: usage.total)])
    }

     
    public static func expiry(_ usage: ConfigurationSubscriptionUsage, locale: Locale) -> HakoDisplayText? {
        guard usage.expire > 0 else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(usage.expire))
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return .format("Expires %@", [formatter.string(from: date)])
    }
}
