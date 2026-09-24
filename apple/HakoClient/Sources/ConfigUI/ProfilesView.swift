import Combine
import HakoClientKit
#if os(macOS)
 
 
import Hako
#endif
import HakoClientUI

 
 
 
 
 
 
 
 
struct HakoCoreRefusal: Error {}
import SwiftUI
import UniformTypeIdentifiers

 
 
 
private actor LocalProfilePreviewCache {
    static let shared = LocalProfilePreviewCache()

    private var values: [String: String] = [:]

    func text(for profile: Profile, container: URL?) -> String? {
        guard let source = activeRevisionSource(for: profile, container: container)
            ?? sidecarSource(for: profile, container: container)
        else { return nil }
        return text(for: source)
    }

     
     
     
    func exportText(for profile: Profile, container: URL?) -> String? {
        guard let source = sidecarSource(for: profile, container: container)
            ?? activeRevisionSource(for: profile, container: container)
        else { return nil }
        return text(for: source)
    }

     
     
     
     
     
    private func text(
        for source: (cacheKey: String, cacheNamespace: String, yaml: String)
    ) -> String? {
        if let cached = values[source.cacheKey] { return cached }
        let staleKeys = values.keys.filter {
            $0 != source.cacheKey && $0.hasPrefix("\(source.cacheNamespace)|")
        }
        staleKeys.forEach { values.removeValue(forKey: $0) }
        values[source.cacheKey] = source.yaml
        return source.yaml
    }

    private func activeRevisionSource(
        for profile: Profile,
        container: URL?
    ) -> (cacheKey: String, cacheNamespace: String, yaml: String)? {
        guard let container else { return nil }

        if let revision = profile.activeRevision,
           let stored = try? ConfigResourceStore(containerURL: container)
               .loadConfiguration(profileID: profile.id, revision: revision),
           let yaml = stored.text {
            let namespace = "revision|\(profile.id)"
            return ("\(namespace)|\(revision)", namespace, yaml)
        }

        return nil
    }

    private func sidecarSource(
        for profile: Profile,
        container: URL?
    ) -> (cacheKey: String, cacheNamespace: String, yaml: String)? {
        guard let container else { return nil }
        let sidecar = container
            .appendingPathComponent("working/store/\(profile.id)/source.yaml")
        guard let yaml = try? String(contentsOf: sidecar, encoding: .utf8) else { return nil }
        let attributes = try? FileManager.default.attributesOfItem(atPath: sidecar.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? Int64(yaml.utf8.count)
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let namespace = "source|\(profile.id)"
        return ("\(namespace)|\(sidecar.path)|\(size)|\(modified)", namespace, yaml)
    }
}

 
 
@MainActor
final class ProfilesViewModel: ObservableObject {
     
     
     
    var resourceStoreForHomeTally: ConfigResourceStore? {
        container.flatMap { try? ConfigResourceStore(containerURL: $0) }
    }

    @Published private(set) var profiles: [Profile] = [] {
        didSet { editableSourceCache.removeAll() }
    }
     
     
     
     
    private var editableSourceCache: [String: Bool] = [:]
    private(set) var editableSourceStatsForTesting = 0
    @Published private(set) var savedConfigurationGeneration: UInt64 = 0
    @Published private(set) var activeProfileID: String?
    @Published private(set) var busyProfileID: String?
     
     
     
     
     
     
    @Published private(set) var isActivating = false
     
     
     
    @Published private(set) var activationAppliesToTunnel: Bool?
     
     
     
    @Published private(set) var statusMessage: HakoDisplayText = .copy("")
    @Published private(set) var notices: [String] = []
    @Published private(set) var planErrors: [String] = []
    @Published private(set) var lastFailure: ConfigurationFailure?
    @Published private(set) var batchReport: BatchUpdateReport?
    @Published private(set) var isBatchSyncing = false

     
     
     
     
    private var baseYAMLCache: [String: (key: String, value: String?)] = [:]
    private var projectedYAMLCache: [String: (key: String, value: String?)] = [:]
     
    private var presentedProxiesYAMLCache: [String: (key: String, value: String?)] = [:]
     
     
     
    private var effectiveYAMLCache: [String: (key: String, value: String?)] = [:]
     
     
     
     
     
     
    private var sourceYAMLCache: [String: String?] = [:]

    private let vpn: VPNController
    private let credentials: CredentialStore
    private let container: URL?
    private let runtimeDefaults: UserDefaults
    private let sourceWriter: (String, Profile, URL) throws -> Void
    private let makeProfileID: () -> String
    private var activationTask: Task<Void, Never>?
    private var pendingActivation: ActivationRequest?
    private var batchTask: Task<Void, Never>?
    private var batchRunID: UUID?
    private let downloader: HTTPFetching
    private(set) var storeReplacementObserver: NSObjectProtocol?
    private var selectionObserver: NSObjectProtocol?
     
     
     
    private static let batchItemLimit: TimeInterval = 45
    private var failedOperation: FailedOperation?
    private var automaticSelectionAttempts: Set<String> = []

    var isActivationInFlight: Bool { activationAppliesToTunnel != nil }

    private struct ActivationRequest {
        let profile: Profile
        let applyToTunnel: Bool
        let preferCachedSource: Bool
    }

    private enum FailedOperation {
        case sync(String)
        case activation(String)
    }

    init(
        vpn: VPNController,
        container: URL? = HakoAppIdentifiers.appGroupContainer,
        credentials: CredentialStore = CredentialStore(),
        sourceWriter: ((String, Profile, URL) throws -> Void)? = nil,
         
         
         
        downloader: HTTPFetching = ResourceDownloader(),
        makeProfileID: @escaping () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.vpn = vpn
        self.container = container
        self.runtimeDefaults = vpn.clientPreferences
        self.credentials = credentials
        self.downloader = downloader
        self.sourceWriter = sourceWriter ?? Self.writeSourceYAML
        self.makeProfileID = makeProfileID
         
         
         
         
        widgetFactsSubscription = Publishers.CombineLatest($activeProfileID, $profiles)
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] activeID, profiles in
                guard let self else { return }
                let active = profiles.first { $0.id == activeID }
                HakoWidgetFactsPublisher.publish(activeLabel: active?.label) { [weak self] in
                    guard let self, let active else { return nil }
                    return self.sourceYAML(for: active)
                }
            }
    }

    private var widgetFactsSubscription: AnyCancellable?

    deinit {
         
         
         
         
        if let storeReplacementObserver {
            NotificationCenter.default.removeObserver(storeReplacementObserver)
        }
        if let selectionObserver {
            NotificationCenter.default.removeObserver(selectionObserver)
        }
    }

    private var workingDir: URL? { container?.appendingPathComponent("working") }
    private var profileStore: ProfileStore? {
        workingDir.map { ProfileStore(fileURL: $0.appendingPathComponent("store/profiles.json")) }
    }

     
     
     
     
    private func observeStoreReplacement() {
        guard storeReplacementObserver == nil else { return }
        storeReplacementObserver = NotificationCenter.default.addObserver(
            forName: .hakoProfileStoreReplaced,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hasAttemptedConfigurationRecovery = false
            self?.load()
        }
         
         
         
         
        selectionObserver = NotificationCenter.default.addObserver(
            forName: .hakoProfileSelectionDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.load()
        }
    }

     
    func applyProfileNow(_ profileID: String) {
        guard let profileStore,
              let latest = profileStore.load().first(where: { $0.id == profileID })
        else { return }
        let action = ProfileSettingsRestagePolicy.action(
            profileID: profileID,
            activeProfileID: activeProfileID,
            vpnStatus: vpn.status
        )
        guard action != .persistOnly else { return }
        startActivation(
            latest,
            applyToTunnel: action == .restageAndApply,
            preferCachedSource: true,
            because: HakoPerf.Reason.readerTappedApply
        )
    }

    func load() {
         
         
        if let library = configurationLibraryStore, let workingDir,
           ConfigurationCenterPublicationBridge.hasReplacementRecovery(workingDir: workingDir) {
            do { try ConfigurationCenterPublicationBridge.recoverReplacements(library: library, workingDir: workingDir) }
            catch {
                recordFailure(error, context: .localImport, operation: nil, preservesLastKnownGood: true)
                return
            }
        }
        if !hasAttemptedConfigurationRecovery {
            hasAttemptedConfigurationRecovery = true
            Task { [weak self] in
                do {
                    try await self?.recoverConfigurationPublications()
                    try await self?.registerLegacyConfigurationSources()
                }
                catch { self?.recordFailure(error,context:.localImport,operation:nil,preservesLastKnownGood:true) }
            }
        }
         
         
         
         
        forgetCachedSource()
        let loadBegan = DispatchTime.now().uptimeNanoseconds
        defer {
            HakoPerf.span(
                "profiles.load",
                milliseconds: Double(
                    DispatchTime.now().uptimeNanoseconds - loadBegan
                ) / 1_000_000,
                detail: "profiles=\(profiles.count)"
            )
        }
         
         
         
         
         
        derivedModeMemo = nil
        observeStoreReplacement()
        guard let profileStore else { return }
         
         
         
         
         
        if let workingDir {
            PlaintextSourceMigration.run(
                profileStore: profileStore,
                workingDir: workingDir,
                credentials: credentials
            )
        }
        if let container, !false {
            do {
                try LocalDefaultProfileProvisioner.provisionIfNeeded(
                    store: profileStore,
                    workingDirectory: container.appendingPathComponent("working")
                )
                try BundledProfileProvisioner.provisionExistingProfileIfNeeded(
                    container: container
                )
                 
                 
                 
                 
                try CorpusProfileSeeder.seedIfRequested(
                    store: profileStore,
                    workingDirectory: container.appendingPathComponent("working")
                )
                 
                 
                 
                if let documents = try? FileManager.default.url(
                    for: .documentDirectory, in: .userDomainMask,
                    appropriateFor: nil, create: false
                ) {
                    RuleProviderCompileProbe.runIfRequested(documents: documents)
                }
            } catch {
                recordFailure(error, context: .localImport, operation: nil,
                              preservesLastKnownGood: false)
            }
        }
         
         
         
        let loaded = profileStore.load().sorted {
            ($0.order, $0.id) < ($1.order, $1.id)
        }
        if let container {
             
             
             
            activeProfileID = (
                try? ConfigResourceStore(
                    containerURL: container
                ).activeIdentity()
            )?.profileID
        }
        let preferred = loaded.first {
            $0.id == activeProfileID
        } ?? loaded.first
        _ = FlClashRuntimeConfig.migrateIfNeeded(
            preferredProfile: preferred,
            legacyGlobalOverride: GlobalConfig.load(
                from: runtimeDefaults
            ),
            defaults: runtimeDefaults
        )
         
         
        _ = FlClashRuntimeConfig.promoteNamespacesIfNeeded(
            profiles: loaded,
            activeProfileID: activeProfileID,
            defaults: runtimeDefaults
        )
        let sanitized = loaded.map(
            FlClashRuntimeConfig.sanitizedProfile
        )
        if sanitized != loaded {
            do {
                try profileStore.save(sanitized)
            } catch {
                recordFailure(
                    error,
                    context: .activation,
                    operation: nil,
                    preservesLastKnownGood: true
                )
            }
        }
         
         
        if profiles != sanitized { profiles = sanitized }
    }

     

    var configurationLibraryStore: ConfigurationLibraryStore? {
        guard let workingDir else { return nil }
        let directory = workingDir.appendingPathComponent("configuration-library")
#if canImport(UIKit)
        return ConfigurationLibraryStore(directory:directory,beginAccess:ConfigStoreSuspensionShield.beginLibraryAccess)
#else
        return ConfigurationLibraryStore(directory:directory)
#endif
    }

    private var legacyRegistration: (id: UUID, task: Task<Void, Error>)?

     
     
     
     
     
    func registerLegacyConfigurationSources() async throws {
        if let registration = legacyRegistration {
            defer { if legacyRegistration?.id == registration.id { legacyRegistration = nil } }
            return try await registration.task.value
        }
        let registrationID = UUID()
        let task = Task { @MainActor in
            guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
            guard let store = configurationLibraryStore, let workingDir else { throw ConfigurationLibraryError.unreadable }
            changingConfigurationLibrary = true
            defer { changingConfigurationLibrary = false }
            let installed = profiles
            var failures: [String] = []
            func register(_ prepare: @escaping @Sendable (ConfigurationLibrarySnapshot) throws
                -> (snapshot: ConfigurationLibrarySnapshot, payloads: [ConfigurationSourcePayload])?) async throws {
                try await Task.detached(priority: .utility) {
                    let current = try store.snapshot()
                    if let registration = try prepare(current) {
                        _ = try store.commit(registration.snapshot, payloads: registration.payloads,
                            expectedGeneration: current.generation)
                    }
                }.value
            }
            for profile in installed {
                try Task.checkCancellation()
                do {
                    try await register { current in
                        try ConfigurationLegacyRegistration.prepare(profile: profile, snapshot: current,
                            load: { try ConfigurationLegacyRegistration.payload(profile: profile, workingDir: workingDir) })
                    }
                } catch { failures.append(profile.label + ": " + error.localizedDescription) }
                do {
                    try await register { current in
                        try ConfigurationLegacyRegistration.prepareCustomNodes(profile: profile, snapshot: current,
                            load: { try ConfigurationLegacyRegistration.customNodePayload(profile: profile, workingDir: workingDir) })
                    }
                } catch { failures.append(profile.label + ": " + error.localizedDescription) }
            }
             
             
             
            do {
                try await register { current in ConfigurationBuiltins.retiringCommunitySchemes(in: current) }
            } catch { failures.append(error.localizedDescription) }
            if !failures.isEmpty { throw PipelineError.sourceUnavailable(failures.joined(separator: "\n")) }
        }
        legacyRegistration = (registrationID, task)
        defer { if legacyRegistration?.id == registrationID { legacyRegistration = nil } }
        try await task.value
    }

     
    func configurationLegacyNodeSources(in snapshot: ConfigurationLibrarySnapshot) async throws -> [String: ConfigurationSourcePayload] {
        var available: [String: ConfigurationSourcePayload] = [:]
        for profile in profiles where profile.id != LocalDefaultProfileProvisioner.profileID
            && !snapshot.sources.contains(where: { $0.id == "legacy-" + profile.id })
            && !snapshot.recipes.contains(where: { $0.id == profile.id }) {
            if let payload = try? await configurationSourceFromLegacy(profile.id), payload.record.suppliesNodes {
                available[profile.id] = payload
            }
            try Task.checkCancellation()
        }
        return available
    }

    func configurationSourceFromLegacy(_ id: String) async throws -> ConfigurationSourcePayload {
        guard let profile = profiles.first(where: { $0.id == id }), let workingDir else {
            throw PipelineError.sourceUnavailable("The original configuration is unavailable.")
        }
        return try await Task.detached(priority: .userInitiated) {
            try ConfigurationLegacyRegistration.payload(profile: profile, workingDir: workingDir)
        }.value
    }

    func fetchConfigurationSource(url: String, label: String) async throws -> ConfigurationSourcePayload {
        try await ConfigurationCenterSourceBridge.fetch(url: url, label: label, credentials: credentials,
                                                        downloader: downloader)
    }

    private var hasAttemptedConfigurationRecovery = false
    private var configurationRecovery: Task<Void, Error>?

    func recoverConfigurationPublications() async throws {
        if let configurationRecovery { return try await configurationRecovery.value }
        let task = Task { @MainActor in try await self.performConfigurationRecovery() }
        configurationRecovery = task
        defer { configurationRecovery = nil }
        try await task.value
    }

    private func performConfigurationRecovery() async throws {
        guard let library = configurationLibraryStore, let workingDir, let profileStore else { return }
        try ConfigurationCenterPublicationBridge.recoverReplacements(library: library, workingDir: workingDir)
        let pending = try await Task.detached { try library.snapshot().pendingPublications ?? [] }.value
        for reference in pending {
            let profile = try await Task.detached(priority:.userInitiated) {
                let publication = try library.publication(reference)
                return try ConfigurationCenterPublicationBridge.stage(publication,library:library,workingDir:workingDir)
            }.value
             
            if !profileStore.load().contains(where: { $0.id == profile.id }) { try profileStore.upsert(profile) }
            try await Task.detached { try library.acknowledgePublication(reference) }.value
        }
        try await Task.detached {
            try ConfigurationCenterPublicationBridge.reconcileDeletedProfiles(library: library, profileStore: profileStore)
        }.value
        if !pending.isEmpty { load() }
    }

    func createConfiguration(_ draft: ConfigurationCreationDraft, generation: UInt64,
                             id: String) async throws -> (id: String, connected: Bool?) {
         
         
         
        guard id.count == 36, UUID(uuidString: id) != nil, id == id.lowercased() else {
            throw ConfigResourceStoreError.invalidProfileID
        }
        guard let library = configurationLibraryStore, let workingDir, let container, let profileStore else {
            throw PipelineError.sourceUnavailable("The configuration store is unavailable.")
        }
        let current = try await Task.detached { try library.snapshot() }.value
        if current.recipes.contains(where: { $0.id == id }) {
             
             
            try await recoverConfigurationPublications()
            guard profileStore.load().contains(where: { $0.id == id }) else {
                throw PipelineError.sourceUnavailable("The configuration was saved but could not be opened. Try again.")
            }
             
            return (id, nil)
        }
        let prepared = try await Task.detached(priority:.userInitiated) {
            try library.prepare(draft,profileID:id,expectedGeneration:generation,
                resolveInput:ConfigurationCenterSourceBridge.boundInput)
        }.value
        let label = ProfileLabelPolicy.deduplicate(prepared.recipe.label,existing:profileStore.load().map(\.label))
         
         
         
         
         
         
        let profileSource = Self.profileSource(for: prepared)
        let profile = Profile(id:id,label:label,labelIsUserAssigned:true,source:profileSource,autoUpdate:false,
            updateIntervalHours:12,subscriptionInfo:nil,selectedMap:[:],override:OverrideSpec(),
            activeRevision:nil,order:(profiles.map(\.order).min() ?? 0) - 1,lastUpdatedAt:nil)
        let check = coreAcceptsDocument
        let yaml = try await Task.detached(priority:.userInitiated) {
            let yaml = try ConfigTransforms.jsonToYAML(prepared.composition.document.serialized())
            try ConfigTransforms.validateSource(yaml)
            let runtime = try ProfileRuntimeConfigBuilder.runtimePreview(raw:yaml,profile:profile)
            let files = try Set(prepared.recipe.dependencies).flatMap { reference in
                let payload = try prepared.payloads.first(where: { $0.record.id == reference.id && $0.record.version == reference.version })
                    ?? library.payload(reference)
                return ConfigurationCenterSourceBridge.boundFiles(payload)
            }
            try ConfigurationCenterSourceBridge.withValidationResources(yaml:runtime,files:files,directory:workingDir) { resolved in
                do { try check(resolved,container) }
                catch {
                    guard Self.refusalBelongsToActivation(error.localizedDescription) else { throw error }
                }
            }
            return yaml
        }.value
        try Task.checkCancellation()
        var candidate = prepared.candidate
        if let index = candidate.recipes.firstIndex(where: { $0.id == id }) { candidate.recipes[index].label = label }
        let publication = ConfigurationPublicationPayload(reference:.init(profileID:id),
            profileMetadata:try JSONEncoder().encode(profile),yaml:yaml)
        _ = try await Task.detached(priority:.userInitiated) {
            try library.commitPublication(candidate,payloads:prepared.payloads,publication:publication,expectedGeneration:generation)
        }.value
         
         
        let staged = try await Task.detached(priority:.userInitiated) {
            try ConfigurationCenterPublicationBridge.stage(publication,library:library,workingDir:workingDir)
        }.value
        if !profileStore.load().contains(where: { $0.id == id }) { try profileStore.upsert(staged) }
        try await Task.detached { try library.acknowledgePublication(publication.reference) }.value
        load()
         
        return (id,nil)
    }

    private var changingConfigurationLibrary = false

    func editConfiguration(_ draft: ConfigurationCreationDraft, id: String, generation: UInt64) async throws {
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        guard let original = profiles.first(where: { $0.id == id }) else { throw ConfigurationLibraryError.missingDependency(id) }
        let prepared = try await Task.detached(priority: .userInitiated) {
            if try library.snapshot().recipes.contains(where: { $0.id == id }) {
                return try library.prepareEditing(draft, profileID: id, expectedGeneration: generation,
                    resolveInput: ConfigurationCenterSourceBridge.boundInput)
            }
            return try library.prepare(draft, profileID: id, expectedGeneration: generation,
                resolveInput: ConfigurationCenterSourceBridge.boundInput)
        }.value
        var candidate = prepared.candidate
        if draft.newSources.contains(where: { $0.record.id == "legacy-" + id }),
           let index = candidate.recipes.firstIndex(where: { $0.id == id }) {
            candidate.recipes[index].followsUpdates = original.autoUpdate
        }
        try await saveConfigurationPlan(candidate: candidate, payloads: prepared.payloads,
            compositions: [id: prepared.composition], generation: generation, rename: id)
    }

    func editConfigurationAdvancedSettings(_ id: String, json: String, generation: UInt64) async throws {
        guard !changingConfigurationLibrary, let library = configurationLibraryStore else { throw ConfigurationLibraryError.busy }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        let prepared = try await Task.detached(priority: .userInitiated) {
            try library.prepareAdvancedSettingsEditing(id, settingsJSON: json, expectedGeneration: generation, includingDNS: true,
                resolveInput: ConfigurationCenterSourceBridge.boundInput)
        }.value
        try await saveConfigurationPlan(candidate: prepared.candidate, payloads: prepared.payloads,
            compositions: prepared.compositions, generation: generation)
    }

    func setConfigurationSourceUpdates(_ id: String, enabled: Bool) async throws {
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        _ = try await Task.detached(priority: .userInitiated) {
            var candidate = try library.snapshot()
            guard candidate.pendingPublications?.isEmpty ?? true else { throw ConfigurationLibraryError.busy }
            guard let index = candidate.recipes.firstIndex(where: { $0.id == id }) else {
                throw ConfigurationLibraryError.missingDependency(id)
            }
            candidate.recipes[index].followsUpdates = enabled
            return try library.commit(candidate, payloads: [], expectedGeneration: candidate.generation)
        }.value
        load()
    }

     
     
     
     
    static func profileSource(for prepared: PreparedConfigurationCreation) -> Profile.Source {
        guard prepared.recipe.sources.count == 1,
              let reference = prepared.recipe.sources.first,
              let record = prepared.candidate.sources.first(where: { $0.id == reference.id }),
              case let .subscription(link) = record.origin,
              !link.isEmpty else { return .clipboard }
        return .url(link)
    }

    func setUsesOriginalConfiguration(_ id: String, enabled: Bool) async throws {
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
         
         
         
         
         
         
        let existing = try await Task.detached { try library.snapshot() }.value
        if !existing.recipes.contains(where: { $0.id == id }) {
            guard !enabled else { return }
            try await composeLegacyConfiguration(id)
            return
        }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        let generation = existing.generation
        let prepared = try await Task.detached(priority: .userInitiated) {
            let value = try library.prepareOriginalUse(id, uses: enabled, expectedGeneration: generation,
                resolveInput: ConfigurationCenterSourceBridge.boundInput)
            for payload in value.payloads { try ConfigTransforms.validateSource(payload.documentJSON) }
            return value
        }.value
        try await saveConfigurationPlan(candidate: prepared.candidate, payloads: prepared.payloads,
            compositions: [id: prepared.composition], generation: generation)
    }

     
     
     
     
     
     
    private func composeLegacyConfiguration(_ id: String) async throws {
        guard let profile = profiles.first(where: { $0.id == id }),
              let library = configurationLibraryStore else {
            throw ConfigurationLibraryError.missingDependency(id)
        }
         
         
         
         
         
         
        try await registerLegacyConfigurationSources()
        try await recoverConfigurationPublications()
        let snapshot = try await Task.detached { try library.snapshot() }.value
        let source = try await configurationSourceFromLegacy(id)
        let ownRules = "rules-" + source.record.id
         
         
         
        let registered = snapshot.rules.contains { $0.id == ownRules }
        let hasRules = registered || (source.record.hasRules && source.record.registersSuppliedRules != false)
        var draft = ConfigurationCreationDraft()
        draft.add(source, rule: hasRules && !registered
            ? ConfigurationRuleScheme(id: ownRules, label: source.record.label, kind: .supplied, sourceID: source.record.id)
            : nil)
        draft.selectedRuleID = hasRules ? ownRules : ConfigurationBuiltins.basicRuleID
        draft.label = profile.label
        draft.dnsMode = .source
        draft.connectAfterCreation = false
        try await editConfiguration(draft, id: id, generation: snapshot.generation)
    }

    func saveConfigurationRuleCustomization(_ draft: ConfigurationRuleDraft, generation: UInt64) async throws -> ConfigurationLibrarySnapshot {
        guard !changingConfigurationLibrary, let store = configurationLibraryStore else { throw ConfigurationLibraryError.busy }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        let prepared = try await Task.detached {
            let value = try store.prepareRuleCustomization(draft, expectedGeneration: generation,
                resolveInput: ConfigurationCenterSourceBridge.boundInput)
            for payload in value.payloads { try ConfigTransforms.validateSource(payload.documentJSON) }
            return value
        }.value
        try await saveConfigurationPlan(candidate: prepared.candidate, payloads: prepared.payloads,
            compositions: prepared.compositions, generation: generation)
        return try await Task.detached { try store.snapshot() }.value
    }

    func saveConfigurationLocalRuleSet(_ value: ConfigurationLocalRuleSet?, deleting id: String? = nil) async throws -> ConfigurationLibrarySnapshot {
        guard !changingConfigurationLibrary, let store = configurationLibraryStore else { throw ConfigurationLibraryError.busy }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        let prepared = try await Task.detached {
            let prepared = try store.prepareLocalRuleSet(value, deleting: id, resolveInput: ConfigurationCenterSourceBridge.boundInput)
            for payload in prepared.payloads { try ConfigTransforms.validateSource(payload.documentJSON) }
            return prepared
        }.value
        try await saveConfigurationPlan(candidate: prepared.candidate, payloads: prepared.payloads,
            compositions: prepared.compositions, generation: prepared.candidate.generation)
        return try await Task.detached { try store.snapshot() }.value
    }

    func createConfigurationRuleScheme(_ draft: ConfigurationNewRuleDraft, generation: UInt64) async throws -> ConfigurationLibrarySnapshot {
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        return try await Task.detached(priority: .userInitiated) {
            try library.createRuleScheme(label: draft.label, templateID: draft.templateID, expectedGeneration: generation)
        }.value
    }

    func saveConfigurationRuleDraft(_ draft: ConfigurationRuleDraft, generation: UInt64) async throws -> ConfigurationLibrarySnapshot {
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        let prepared = try await Task.detached(priority: .userInitiated) {
            let plan = try library.prepareRuleEditing(draft, expectedGeneration: generation,
                resolveInput: ConfigurationCenterSourceBridge.boundInput)
            for payload in plan.payloads { try ConfigTransforms.validateSource(payload.documentJSON) }
            return plan
        }.value
        try await saveConfigurationPlan(candidate: prepared.candidate, payloads: prepared.payloads,
            compositions: prepared.compositions, generation: generation)
        return try await Task.detached { try library.snapshot() }.value
    }

    func addConfigurationRuleScheme(_ source: ConfigurationSourcePayload, generation: UInt64) async throws -> ConfigurationLibrarySnapshot {
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        return try await Task.detached(priority: .userInitiated) {
            try library.addRuleScheme(source, expectedGeneration: generation)
        }.value
    }

    func copyConfigurationRuleScheme(_ id: String, label: String, generation: UInt64) async throws -> ConfigurationLibrarySnapshot {
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        return try await Task.detached(priority: .userInitiated) {
            try library.copyRuleScheme(id, label: label, expectedGeneration: generation)
        }.value
    }

    func deleteConfigurationRuleScheme(_ id: String, generation: UInt64) async throws -> ConfigurationLibrarySnapshot {
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        let prepared = try await Task.detached(priority: .userInitiated) {
            try library.prepareRuleRemoval(id, expectedGeneration: generation,
                resolveInput: ConfigurationCenterSourceBridge.boundInput)
        }.value
        try await saveConfigurationPlan(candidate: prepared.candidate, payloads: prepared.payloads,
            compositions: prepared.compositions, generation: generation)
        return try await Task.detached { try library.snapshot() }.value
    }

    func addConfigurationSource(_ source: ConfigurationSourcePayload, generation: UInt64) async throws -> ConfigurationLibrarySnapshot {
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        return try await Task.detached(priority: .userInitiated) {
            try library.addSource(source, expectedGeneration: generation)
        }.value
    }

    func renameConfigurationSource(_ id: String, label: String, generation: UInt64) async throws -> ConfigurationLibrarySnapshot {
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        return try await Task.detached(priority: .userInitiated) {
            try library.renameSource(id, label: label, expectedGeneration: generation)
        }.value
    }

    func saveConfigurationSourceSettings(_ id: String, draft: ConfigurationSourceSettingsDraft,
                                         label: String? = nil, generation: UInt64) async throws -> ConfigurationLibrarySnapshot {
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        let result = try await Task.detached {
            try library.updateSourceSettings(id, draft: draft, label: label, expectedGeneration: generation)
        }.value
        BackgroundRefresh.schedule(earliest: BackgroundRefresh.nextEligibility())
        return result
    }

    func deleteConfigurationSource(_ id: String, generation: UInt64) async throws -> ConfigurationLibrarySnapshot {
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        let prepared = try await Task.detached(priority: .userInitiated) {
            try library.prepareSourceRemoval(id, expectedGeneration: generation,
                resolveInput: ConfigurationCenterSourceBridge.boundInput)
        }.value
        try await saveConfigurationPlan(candidate: prepared.candidate, payloads: prepared.payloads,
            compositions: prepared.compositions, generation: generation)
        return try await Task.detached { try library.snapshot() }.value
    }

    func saveConfigurationChain(_ version: ConfigurationSourceVersion, replacement: ConfigurationSourcePayload) async throws -> ConfigurationLibrarySnapshot {
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        let snapshot = try await Task.detached { try library.snapshot() }.value
        let plan = try await Task.detached(priority: .userInitiated) {
            guard let record = snapshot.sources.first(where: { $0.id == version.id }), record.nodeChain != nil,
                  ConfigurationSourceVersion(record) == version, replacement.record.id == version.id else {
                throw ConfigurationLibraryError.staleGeneration
            }
            try ConfigTransforms.validateSource(ConfigTransforms.jsonToYAML(replacement.documentJSON))
            return try library.prepareSourceUpdate(replacement, expectedGeneration: snapshot.generation,
                updatingPinnedConsumers: true, resolveInput: ConfigurationCenterSourceBridge.boundInput)
        }.value
        try await saveConfigurationPlan(candidate: plan.candidate, payloads: plan.payloads,
            compositions: plan.compositions, generation: snapshot.generation)
        return try await Task.detached { try library.snapshot() }.value
    }

     
    func saveConfigurationNodeSource(_ version: ConfigurationSourceVersion, yaml: String) async throws -> ConfigurationLibrarySnapshot {
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        let snapshot = try await Task.detached { try library.snapshot() }.value
        let plan = try await Task.detached(priority: .userInitiated) {
            guard var record = snapshot.sources.first(where: { $0.id == version.id }),
                  record.suppliesNodes, record.nodeChain == nil, ConfigurationSourceVersion(record) == version else {
                throw ConfigurationLibraryError.staleGeneration
            }
            let edited = try OrderedJSON.parse(ConfigTransforms.yamlToJSON(yaml))
            let keys: Set<String> = ["proxies", "proxy-providers"]
            guard case .object(let entries) = edited,
                  entries.allSatisfy({ keys.contains($0.key) }) else {
                throw NSError(domain: "ConfigurationNodeEditor", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: HakoCopy.string("Only nodes and proxy providers belong here. Edit rules in Rule Library.", locale: .current)])
            }
            try ConfigTransforms.validateSource(yaml)
            let previous = try library.payload(version)
            var document = try OrderedJSON.parse(previous.documentJSON)
            for key in keys {
                if let value = edited.topLevelValue(key) { document = document.settingTopLevel(key, to: value) }
                else { document = document.removingTopLevel(key) }
            }
            if case .array(let nodes) = edited.topLevelValue("proxies") { record.nodeCount = nodes.count }
            else { record.nodeCount = 0 }
            if case .object(let providers) = edited.topLevelValue("proxy-providers") { record.providerCount = providers.count }
            else { record.providerCount = 0 }
            record.version = UUID().uuidString; record.updatedAt = Date()
            let replacement = ConfigurationSourcePayload(record: record, original: previous.original,
                documentJSON: document.serialized(), resourceFiles: previous.resourceFiles,
                ruleBaselineJSON: previous.ruleBaselineJSON)
            return try library.prepareSourceUpdate(replacement, expectedGeneration: snapshot.generation,
                updatingPinnedConsumers: true, resolveInput: ConfigurationCenterSourceBridge.boundInput)
        }.value
        try await saveConfigurationPlan(candidate: plan.candidate, payloads: plan.payloads,
            compositions: plan.compositions, generation: snapshot.generation)
        return try await Task.detached { try library.snapshot() }.value
    }

    func saveConfigurationCollection(_ entry: ConfigurationCollectionEntry, definitionJSON: String?) async throws -> ConfigurationLibrarySnapshot {
        guard !changingConfigurationLibrary, let library = configurationLibraryStore else { throw ConfigurationLibraryError.busy }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        let snapshot = try await Task.detached { try library.snapshot() }.value
        let plan = try await Task.detached {
            guard var record = snapshot.sources.first(where: { $0.id == entry.source.id }),
                  record.version == entry.source.version else { throw ConfigurationLibraryError.staleGeneration }
            let previous = try library.payload(.init(record))
            var document = try OrderedJSON.parse(previous.documentJSON)
            let field = entry.id.kind.rawValue
            var definitions = document.topLevelValue(field) ?? .object([])
            if let definitionJSON {
                let value = try OrderedJSON.parse(definitionJSON)
                guard case .object = value else { throw ConfigurationLibraryError.unreadable }
                definitions = definitions.settingTopLevel(entry.collection.name, to: value)
            } else { definitions = definitions.removingTopLevel(entry.collection.name) }
            document = document.settingTopLevel(field, to: definitions)
            try ConfigTransforms.validateSource(document.serialized())
            if case .object(let values) = document.topLevelValue("proxy-providers") { record.providerCount = values.count }
            if case .object(let values) = document.topLevelValue("rule-providers") { record.ruleProviderCount = values.count }
            record.version = UUID().uuidString; record.updatedAt = Date()
            let replacement = ConfigurationSourcePayload(record: record, original: previous.original,
                documentJSON: document.serialized(), resourceFiles: previous.resourceFiles, ruleBaselineJSON: previous.ruleBaselineJSON)
            return try library.prepareSourceUpdate(replacement, expectedGeneration: snapshot.generation,
                updatingPinnedConsumers: true, resolveInput: ConfigurationCenterSourceBridge.boundInput)
        }.value
        try await saveConfigurationPlan(candidate: plan.candidate, payloads: plan.payloads,
            compositions: plan.compositions, generation: snapshot.generation)
        return try await Task.detached { try library.snapshot() }.value
    }

    func saveConfigurationCustomNode(_ version: ConfigurationSourceVersion, nodeJSON: String, index: Int? = 0) async throws -> ConfigurationLibrarySnapshot {
        try await changeConfigurationCustomNode(version, nodeJSON: nodeJSON, index: index)
    }

    func deleteConfigurationCustomNode(_ version: ConfigurationSourceVersion, index: Int) async throws -> ConfigurationLibrarySnapshot {
        try await changeConfigurationCustomNode(version, nodeJSON: nil, index: index)
    }

     
     
     
    private func changeConfigurationCustomNode(_ version: ConfigurationSourceVersion, nodeJSON: String?, index: Int?) async throws -> ConfigurationLibrarySnapshot {
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        let snapshot = try await Task.detached { try library.snapshot() }.value
        let plan = try await Task.detached(priority: .userInitiated) {
            guard var record = snapshot.sources.first(where: { $0.id == version.id }),
                  case .customNodes = record.origin, record.nodeChain == nil, ConfigurationSourceVersion(record) == version else {
                throw ConfigurationLibraryError.staleGeneration
            }
            let previous = try library.payload(version)
            let original = try OrderedJSON.parse(previous.documentJSON)
            guard case .array(var nodes) = original.topLevelValue("proxies") else {
                throw ConfigurationLibraryError.invalidIdentifier
            }
            if let index {
                guard nodes.indices.contains(index) else { throw ConfigurationLibraryError.staleGeneration }
                if let nodeJSON { nodes[index] = try OrderedJSON.parse(nodeJSON) }
                else { nodes.remove(at: index) }
            } else if let nodeJSON { nodes.append(try OrderedJSON.parse(nodeJSON)) }
            let document = original.settingTopLevel("proxies", to: .array(nodes))
            record.nodeCount = nodes.count
            let yaml = try ConfigTransforms.jsonToYAML(document.serialized())
            try ConfigTransforms.validateSource(yaml)
            record.version = UUID().uuidString; record.updatedAt = Date()
            let replacement = ConfigurationSourcePayload(record: record, original: Data(yaml.utf8),
                documentJSON: document.serialized(), resourceFiles: previous.resourceFiles)
            return try library.prepareSourceUpdate(replacement, expectedGeneration: snapshot.generation,
                updatingPinnedConsumers: true, resolveInput: ConfigurationCenterSourceBridge.boundInput)
        }.value
        try await saveConfigurationPlan(candidate: plan.candidate, payloads: plan.payloads,
            compositions: plan.compositions, generation: snapshot.generation)
        return try await Task.detached { try library.snapshot() }.value
    }

    func refreshConfigurationSource(_ id: String, replaceEditedRules: Bool = false,
                                    expectedVersion: String? = nil) async throws {
        guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
        guard let library = configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        changingConfigurationLibrary = true
        defer { changingConfigurationLibrary = false }
        let current = try await Task.detached { try library.snapshot() }.value
        guard let source = current.availableSources.first(where: { $0.id == id }),
              case .subscription(let url) = source.origin else {
            throw ConfigurationLibraryError.missingDependency(id)
        }
        if let expectedVersion, source.version != expectedVersion { throw ConfigurationLibraryError.staleGeneration }
        let fetched = try await ConfigurationCenterSourceBridge.fetch(url: url, label: source.label,
            credentials: credentials, downloader: downloader)
        var record = ConfigurationSourceRecord(id: id, label: source.label, origin: source.origin,
            version: fetched.record.version, nodeCount: fetched.record.nodeCount,
            providerCount: fetched.record.providerCount, groupCount: fetched.record.groupCount,
            ruleCount: fetched.record.ruleCount, suppliesNodes: source.suppliesNodes,
            updatedAt: fetched.record.updatedAt, updateIntervalHours: source.updateIntervalHours,
            userAgent: source.userAgent, dnsOverHTTPS: source.dnsOverHTTPS,
            registersSuppliedRules: source.registersSuppliedRules)
        record.subscriptionUsage = fetched.record.subscriptionUsage
        let refreshedRecord = record
        let prepared = try await Task.detached(priority: .userInitiated) {
            let previous = try library.payload(.init(source))
            let replacement = ConfigurationSourcePayload(record: refreshedRecord, original: fetched.original,
                documentJSON: fetched.documentJSON, resourceFiles: previous.resourceFiles)
            return try library.prepareSourceUpdate(replacement, expectedGeneration: current.generation,
                replaceEditedRules: replaceEditedRules, resolveInput: ConfigurationCenterSourceBridge.boundInput)
        }.value
        try await saveConfigurationPlan(candidate: prepared.candidate, payloads: prepared.payloads,
            compositions: prepared.compositions, generation: current.generation)
    }

    private func saveConfigurationPlan(candidate initial: ConfigurationLibrarySnapshot,
                                       payloads: [ConfigurationSourcePayload],
                                       compositions: [String: ConfigurationComposition],
                                       generation: UInt64, rename: String? = nil) async throws {
        guard let library = configurationLibraryStore, let workingDir, let container, let profileStore else {
            throw ConfigurationLibraryError.unreadable
        }
         
         
        if compositions.isEmpty {
            try Task.checkCancellation()
            _ = try await Task.detached {
                try library.commit(initial, payloads: payloads, expectedGeneration: generation)
            }.value
            return
        }
        let originals = profileStore.load()
        var candidate = initial
         
         
        for index in candidate.recipes.indices where candidate.recipes[index].id != rename {
            if let profile = originals.first(where: { $0.id == candidate.recipes[index].id }) {
                candidate.recipes[index].label = profile.label
            }
        }
        let planned = candidate
        let coreGate = coreAcceptsDocument
        let replacements = try await Task.detached(priority: .userInitiated) {
            try ConfigurationCenterSourceBridge.prepareReplacements(compositions: compositions, planned: planned,
                payloads: payloads, library: library, originals: originals, workingDir: workingDir,
                container: container, rename: rename, coreGate: coreGate)
        }.value
        try Task.checkCancellation()
        try await ConfigurationCenterPublicationBridge.replaceOffMain(replacements, candidate: candidate,
            payloads: payloads, library: library, workingDir: workingDir, expectedGeneration: generation)
        load()
        savedConfigurationGeneration &+= 1

    }

     

    func add(
        label: String,
        source: Profile.Source,
        rawYAML: String?,
        resourceFiles: [ExternalResourceImportFile] = []
    ) {
        guard let profileStore, let workingDir else { return }
         
         
         
         
         
        let uniqueLabel = ProfileLabelPolicy.deduplicate(
            ProfileLabelPolicy.name(given: label, for: source),
            existing: profiles.map(\.label)
        )
        var profile = Profile(
            id: makeProfileID(), label: uniqueLabel,
             
             
             
            labelIsUserAssigned: !label
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            source: source,
            autoUpdate: { if case .url = source { return true } else { return false } }(),
            updateIntervalHours: 12, subscriptionInfo: nil, selectedMap: [:],
            override: OverrideSpec(), activeRevision: nil,
            order: (profiles.map(\.order).max() ?? -1) + 1,
            lastUpdatedAt: nil)
        do {
            if let rawYAML {
                try ConfigTransforms.validateSource(rawYAML)
                 
                 
                 
                 
                 
                 
                 
                 
                let prepared = try ProfileExternalResourceImporter.prepare(
                    yaml: rawYAML,
                    profileID: profile.id,
                    source: externalResourceSource(source),
                    files: resourceFiles,
                    requiringAllFiles: { if case .file = source { return false } else { return true } }()
                )
                try ProfileExternalResourceStore.replace(
                    prepared.publicResources,
                    profileID: profile.id,
                    coreHomeDir: workingDir
                )
                profile.externalResources = prepared.references.isEmpty
                    ? nil : prepared.references
                try profileStore.upsert(profile)
                 
                try cacheSourceYAML(prepared.yaml, for: profile)
            } else {
                try profileStore.upsert(profile)
                if case .url = source {
                     
                     
                     
                     
                     
                     
                     
                    load()
                    if let stored = profiles.first(where: { $0.id == profile.id }) {
                        sync(stored)
                    }
                    return
                }
            }
        } catch {
            let failure = ConfigurationFailureClassifier.classify(
                error,
                context: .localImport,
                preservesLastKnownGood: false
            )
            planErrors = failure.map { [$0.localizedDescription] } ?? []
            statusMessage = failure.map { .copy($0.title) } ?? "Profile was not added"
             
             
             
             
            recordFailure(error, context: .localImport, operation: nil, preservesLastKnownGood: false)
            try? profileStore.remove(id: profile.id)
            try? FileManager.default.removeItem(
                at: workingDir.appendingPathComponent("store/\(profile.id)")
            )
            return
        }
        load()
    }

    @discardableResult
    func addDirectProfile() -> Profile? {
        let label = uniqueCopyLabel(base: "Local Profile", suffix: "")
        add(
            label: label,
            source: .clipboard,
            rawYAML: DirectProfileTemplate.yaml
        )
        return profiles.first { $0.label == label }
    }

     
     
     
    func selectSoleProfileIfNeeded() {
        guard let id = ProfileCenterPolicy.automaticSelectionID(
            profiles: profiles,
            activeProfileID: activeProfileID
        ), automaticSelectionAttempts.insert(id).inserted,
              let profile = profiles.first(where: { $0.id == id }) else { return }
        select(profile)
    }

     
     
    func select(_ profile: Profile) {
        guard profile.id != activeProfileID else { return }
         
         
         
         
         
         
         
        startActivation(
            profile,
            applyToTunnel: ProfileSelectionRuntimePolicy.shouldApplyToTunnel(
                vpnStatus: vpn.status
            ),
            preferCachedSource: true
,
            because: HakoPerf.Reason.profileSelected
        )
    }

     
     
     
     
    func selectAndWait(
        _ profile: Profile, force: Bool = false
    ) async -> Bool {
         
         
         
         
         
        guard force || profile.id != activeProfileID else { return true }
        startActivation(
            profile,
            applyToTunnel: ProfileSelectionRuntimePolicy.shouldApplyToTunnel(
                vpnStatus: vpn.status
            ),
            preferCachedSource: true
        )
        await waitForPendingActivation()
        return activeProfileID == profile.id && lastFailure == nil
    }

    private var activationCancellationGeneration: UInt64 = 0

     
     
     
     
    @discardableResult
    func connectFromHome(
        _ profile: Profile, forceReactivation: Bool = true
    ) async -> Bool {
        let cancellationGeneration = activationCancellationGeneration
         
         
        guard await selectAndWait(profile, force: forceReactivation),
              activeProfileID == profile.id,
              busyProfileID == nil, pendingActivation == nil, !isActivating,
              !Task.isCancelled,
              activationCancellationGeneration == cancellationGeneration
        else { return false }
        return await vpn.start()
    }

     
     
     
    func stripSourceCredentials(_ profile: Profile) throws {
        guard let profileStore else {
            throw PipelineError.sourceUnavailable("the shared profile store is unavailable")
        }
        guard let latest = profileStore.load().first(where: { $0.id == profile.id }),
              let stripped = ProfileMetadataUpdate.strippingSourceCredentials(
                from: latest
              ) else {
            return
        }
        try profileStore.upsert(stripped)
        statusMessage = "Stored URL credentials removed"
        load()
    }

     
     
    func saveMemoryTrim(_ profile: Profile) {
        guard let profileStore else { return }
        try? profileStore.upsert(profile)
        load()
    }

    func saveDNSBootstrapInsurance(_ profile: Profile) {
        guard let profileStore else { return }
        try? profileStore.upsert(profile)
        load()
    }

    func updateMetadata(
        _ profile: Profile,
        label: String,
        subscriptionURL: String?,
        autoUpdate: Bool,
        updateIntervalHours: Int
    ) throws {
        guard let profileStore else {
            throw PipelineError.sourceUnavailable("the shared profile store is unavailable")
        }
        do {
            let updated = try ProfileMetadataUpdate.apply(
                to: profile,
                label: label,
                subscriptionURL: subscriptionURL,
                autoUpdate: autoUpdate,
                updateIntervalHours: updateIntervalHours,
                existingLabels: Set(
                    profiles.filter { $0.id != profile.id }.map(\.label)
                )
            )
            try profileStore.upsert(updated)
            statusMessage = .format("%@ saved", [updated.label])
            clearFailure()
            load()
            savedConfigurationGeneration &+= 1

        } catch {
            recordFailure(
                error,
                context: .localImport,
                operation: nil,
                preservesLastKnownGood: true
            )
            throw error
        }
    }

     
     
     
     
     
     
     
     
     
     
    @discardableResult
    func duplicate(_ profile: Profile) async -> Profile? {
        guard let profileStore, let workingDir else { return nil }
        let id = makeProfileID()
        let label = uniqueCopyLabel(base: profile.label, suffix: " Copy")
        let sourceWriter = sourceWriter
        do {
            let prepared = try await Task.detached(priority: .userInitiated) {
                guard let hydrated = Self.sidecarYAML(for: profile, workingDir: workingDir) else {
                    throw PipelineError.sourceUnavailable(
                        "the saved source for this profile is unavailable"
                    )
                }
                let resources = try Self.duplicateResourceFiles(
                    sourceYAML: hydrated,
                    profile: profile,
                    dataByKey: Self.externalResourceData(for: profile, workingDir: workingDir)
                )
                let prepared = try ProfileExternalResourceImporter.prepare(
                    yaml: hydrated,
                    profileID: id,
                    source: .localFile,
                    files: resources
                )
                try ProfileExternalResourceStore.replace(
                    prepared.publicResources,
                    profileID: id,
                    coreHomeDir: workingDir
                )
                return prepared
            }.value

            var copy = Profile(
                id: id,
                label: label,
                source: .file(safeProfileFileName(label)),
                autoUpdate: false,
                updateIntervalHours: profile.updateIntervalHours,
                subscriptionInfo: nil,
                selectedMap: profile.selectedMap,
                currentGroupName: profile.currentGroupName,
                unfoldedGroups: profile.unfoldedGroups,
                override: profile.override,
                activeRevision: nil,
                order: profile.order + 1,
                lastUpdatedAt: nil,
                subscriptionETag: nil,
                subscriptionLastModified: nil,
                usesLocalSourceOverride: true,
                selectedScriptID: profile.selectedScriptID,
                overwriteMode: profile.overwriteMode,
                customOverwrite: profile.customOverwrite,
                proxyChain: profile.proxyChain,
                legacyRelayMigrations: profile.legacyRelayMigrations,
                proxyCredentials: nil,
                sourceCredentials: nil,
                sourceCredentialsRedacted: nil,
                externalResources: prepared.references.isEmpty ? nil : prepared.references,
                migratedGlobalOverride: profile.migratedGlobalOverride,
                outboundMode: profile.outboundMode
            )
             
             
             
             
             
             
             
            copy.postMergeScriptID = profile.postMergeScriptID
            copy.proxyNodeOverrides = profile.proxyNodeOverrides
             
             
            copy.providerDefinitions = profile.providerDefinitions
             
             
            copy.subscriptionInfo = nil
             
             
             
             
             
             
             
            var stored = profileStore.load()
            for index in stored.indices where stored[index].id != copy.id && stored[index].order >= copy.order {
                stored[index].order += 1
            }
            stored.removeAll { $0.id == copy.id }
            stored.append(copy)
            let sidecarCopy = copy
            try await Task.detached(priority: .userInitiated) {
                try sourceWriter(prepared.yaml, sidecarCopy, workingDir)
            }.value
            try profileStore.save(stored)
            statusMessage = .format("%@ created", [copy.label])
            clearFailure()
            load()
            return profiles.first(where: { $0.id == copy.id }) ?? copy
        } catch {
            try? profileStore.remove(id: id)
            try? FileManager.default.removeItem(
                at: workingDir.appendingPathComponent("store/\(id)")
            )
            recordFailure(
                error,
                context: .localImport,
                operation: nil,
                preservesLastKnownGood: true
            )
            load()
            return nil
        }
    }

    func installSubscription(_ rawURL: String) {
        if let existing = profiles.first(where: {
            if case let .url(url) = $0.source { return url == rawURL }
            return false
        }) {
            statusMessage = .format("Profile URL already exists; syncing %@…", [existing.label])
            sync(existing)
            return
        }
         
         
         
         
         
        add(label: "", source: .url(rawURL), rawYAML: nil)
    }

    func delete(at offsets: IndexSet) {
        for index in offsets {
            delete(profiles[index])
        }
    }

    func delete(_ profile: Profile) {
        guard let profileStore else { return }
        guard ProfileCenterPolicy.canDelete(
            profileID: profile.id,
            activeProfileID: activeProfileID
        ) else {
            statusMessage = profile.id == LocalDefaultProfileProvisioner.profileID
                ? "Direct is Clash's system fallback and cannot be deleted"
                : "Switch to another profile before deleting"
            return
        }
        let clearsOwnedFailure = failureProfile?.id == profile.id
        do {
             
             
             
             
             
             
             
            if let library = configurationLibraryStore {
                try ConfigurationCenterPublicationBridge.removeProfile(profile, library: library, profileStore: profileStore)
            } else { try profileStore.remove(id: profile.id) }
            if let workingDir {
                try? FileManager.default.removeItem(
                    at: workingDir.appendingPathComponent("store/\(profile.id)")
                )
            }
            try ProxyCredentialVault.remove(
                profile.proxyCredentials ?? [],
                store: credentials
            )
             
             
            try ProxyCredentialVault.remove(
                profile.sourceCredentials ?? [],
                store: credentials
            )
            try ProviderDefinitionCredentialVault.remove(
                profile.providerDefinitionCredentials ?? [],
                store: credentials
            )
            if clearsOwnedFailure {
                clearFailure()
            }
            statusMessage = .format("%@ deleted", [profile.label])
        } catch {
            statusMessage = .format("%@ could not be deleted", [profile.label])
            planErrors = [error.localizedDescription]
        }
        load()
    }

     

    func update(_ profile: Profile) {
        guard let profileStore else { return }
        try? profileStore.upsert(profile)
        load()
    }

     
     
     
     
     
     
     
     
     
    func renameProxyNode(profileID: String, from old: String, to new: String) throws {
        guard let profileStore,
              var latest = profileStore.load().first(where: { $0.id == profileID })
        else {
            throw PipelineError.sourceUnavailable("the profile is no longer available")
        }
        var unusedPayload: [[String: Any]] = []
        ProxyNodeRename.apply(
            from: old, to: new, profile: &latest, customPayload: &unusedPayload
        )
        try profileStore.upsert(latest)
        load()
    }

     
     
    func updateRules(_ draft: ProfileRulesDraft) throws {
        guard let profileStore,
              let latest = profileStore.load().first(where: { $0.id == draft.profileID }) else {
            throw PipelineError.sourceUnavailable("the profile is no longer available")
        }
        try updateConfiguration(draft.applying(to: latest))
    }

     
     
     
    func updateDNS(_ draft: ProfileDNSDraft) throws {
        guard let profileStore,
              let latest = profileStore.load().first(where: { $0.id == draft.profileID }) else {
            throw PipelineError.sourceUnavailable("the profile is no longer available")
        }
        try updateGlobalConfiguration(
            draft.applying(to: latest),
            replacing: ["dns"],
            configureSpec: { spec in
                spec.dnsOverridesProfiles = draft.dnsOverridesProfiles
            }
        )
    }

     
    func updateHosts(_ draft: ProfileHostsDraft) throws {
        guard let profileStore,
              let latest = profileStore.load().first(where: { $0.id == draft.profileID }) else {
            throw PipelineError.sourceUnavailable("the profile is no longer available")
        }
        try updateGlobalConfiguration(
            draft.applying(to: latest),
            replacing: ["hosts"]
        )
    }

     
     
    func updateNetwork(_ draft: ProfileNetworkDraft) throws {
        guard let profileStore,
              let latest = profileStore.load().first(where: { $0.id == draft.profileID }) else {
            throw PipelineError.sourceUnavailable("the profile is no longer available")
        }
        let updated = FlClashRuntimeConfig.sanitizedProfile(
            try draft.applying(to: latest)
        )
        try updateConfiguration(updated)
    }

     
    func updateGlobalNetwork(_ draft: ProfileNetworkDraft) throws {
        guard let profileStore,
              let latest = profileStore.load().first(where: { $0.id == draft.profileID }) else {
            throw PipelineError.sourceUnavailable("the profile is no longer available")
        }
        try updateGlobalConfiguration(
            draft.applyingGlobalRuntime(
                to: settingsProfile(for: latest)
            ),
            replacing: OverridePatch.networkRuntimeKeys
        )
    }

     
     
    func updateGlobalRuntimeTrust(
        _ draft: ProfileRuntimeTrustDraft
    ) throws {
        guard let profileStore,
              let latest = profileStore.load().first(
                  where: { $0.id == draft.profileID }
              ) else {
            throw PipelineError.sourceUnavailable(
                "the profile is no longer available"
            )
        }
        let projected = try draft.applyingGlobalRuntime(
            to: settingsProfile(for: latest)
        )
        var candidate = latest
        candidate.override.patchJSON = projected.override.patchJSON
        try updateGlobalConfiguration(
            candidate,
            replacing: OverridePatch.runtimeTrustKeys
        )
    }

     
     
     
     
     
     
     
    func updateGlobalLANShare(
        allowLAN: Bool?, mixedPort: Int32?, profileID: String
    ) throws {
        guard let profileStore,
              let latest = profileStore.load().first(where: { $0.id == profileID })
        else {
            throw PipelineError.sourceUnavailable(
                "the profile is no longer available"
            )
        }
        var patch = OverridePatch(patchJSON: settingsProfile(for: latest).override.patchJSON)
        patch.setValue(allowLAN, at: ["allow-lan"])
        if let mixedPort {
            patch.setValue(Int(mixedPort), at: ["mixed-port"])
        }
        var candidate = latest
        candidate.override.patchJSON = patch.patchJSON
        try updateGlobalConfiguration(candidate, replacing: ["allow-lan", "mixed-port"])
    }

     
     
     
     
     
     
    func kernelLANShareBinding() -> KernelLANShareBinding {
        let runtimeDefaults = runtimeDefaults
        return KernelLANShareBinding(
            profileSourceYAML: { [weak self] in
                guard let self,
                      let active = self.profiles.first(where: { $0.id == self.activeProfileID })
                else { return nil }
                return self.sourceYAML(for: active)
            },
            override: {
                let patch = OverridePatch(patchJSON: FlClashRuntimeConfig.load(from: runtimeDefaults).patchJSON)
                return KernelLANShareOverride(patch: patch)
            },
            writeOverride: { [weak self] override in
                guard let self, let id = self.activeProfileID else {
                    throw PipelineError.sourceUnavailable("the profile is no longer available")
                }
                try self.updateGlobalLANShare(
                    allowLAN: override.allowLAN, mixedPort: override.mixedPort, profileID: id
                )
            },
            setPermitted: {
                LocalNetworkPermission.setPermitted(
                    $0, in: UserDefaults(suiteName: HakoAppIdentifiers.appGroup)
                )
            },
            profileID: { [weak self] in self?.activeProfileID }
        )
    }

     
     
     
     
     
    func adoptHeldBackUpdate(_ profile: Profile, keyPath: String) throws {
        guard let profileStore,
              let latest = profileStore.load().first(where: { $0.id == profile.id }),
              let item = latest.suppressedUpdates?.first(where: { $0.keyPath == keyPath })
        else { return }
        var patch = OverridePatch(patchJSON: settingsProfile(for: latest).override.patchJSON)
        switch item.change {
        case .removed:
            patch.setValue(nil, at: item.components)
        case .added, .changed:
            guard let text = item.newValue,
                  let value = try? JSONSerialization.jsonObject(
                      with: Data(text.utf8), options: [.fragmentsAllowed]
                  )
            else { return }
            patch.setValue(value, at: item.components)
        }
        var candidate = latest
        candidate.override.patchJSON = patch.patchJSON
        candidate.suppressedUpdates = latest.suppressedUpdates?.filter { $0.keyPath != keyPath }
        if candidate.suppressedUpdates?.isEmpty == true { candidate.suppressedUpdates = nil }
        try updateGlobalConfiguration(candidate, replacing: [item.topLevelKey])
    }

     
    func dismissHeldBackUpdates(_ profile: Profile) throws {
        guard let profileStore,
              var latest = profileStore.load().first(where: { $0.id == profile.id })
        else { return }
        latest.suppressedUpdates = nil
        try profileStore.upsert(latest)
        load()
    }

     
     
    func updateGlobalCoreBehavior(
        network: ProfileNetworkDraft,
        runtime: ProfileRuntimeTrustDraft
    ) throws {
        guard network.profileID == runtime.profileID,
              let profileStore,
              let latest = profileStore.load().first(
                  where: { $0.id == network.profileID }
              ) else {
            throw PipelineError.sourceUnavailable(
                "the profile is no longer available"
            )
        }
        let projected = settingsProfile(for: latest)
        let networkApplied = try network.applyingGlobalRuntime(
            to: projected
        )
        let runtimeApplied = try runtime.applyingGlobalRuntime(
            to: networkApplied
        )
        var candidate = latest
        candidate.override.patchJSON =
            runtimeApplied.override.patchJSON
        try updateGlobalConfiguration(
            candidate,
            replacing:
                OverridePatch.networkRuntimeKeys
                .union(OverridePatch.runtimeTrustKeys)
        )
    }

     
    func updateRoutePreset(_ draft: ProfileRoutePresetDraft) throws {
        guard let profileStore,
              let latest = profileStore.load().first(where: { $0.id == draft.profileID }) else {
            throw PipelineError.sourceUnavailable("the profile is no longer available")
        }
        try updateGlobalConfiguration(
            draft.applying(to: latest),
            replacing: ["tun"]
        )
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func updateOutboundMode(
        profileID: String,
        mode: Profile.OutboundMode,
        kernelCarriesTheChange: Bool = true
    ) throws {
        guard let profileStore,
              let latest = profileStore.load().first(where: { $0.id == profileID }) else {
            throw PipelineError.sourceUnavailable("the profile is no longer available")
        }
        var projected = settingsProfile(for: latest)
        var patch = OverridePatch(
            patchJSON: projected.override.patchJSON
        )
        patch.mode = mode.rawValue
        projected.override.patchJSON = patch.patchJSON
        try updateGlobalConfiguration(
            projected,
            replacing: ["mode"],
            runtimeAlreadyCarriesChange: kernelCarriesTheChange
        )
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func restageForClientRuntimeSetting() {
        guard let id = activeProfileID,
              let profile = profiles.first(where: { $0.id == id })
        else { return }
        switch ProfileSettingsRestagePolicy.action(
            profileID: id,
            activeProfileID: activeProfileID,
            vpnStatus: vpn.status
        ) {
        case .persistOnly:
            break
        case .restageOnly:
            startActivation(profile, applyToTunnel: false, preferCachedSource: true, because: HakoPerf.Reason.clientRuntimeSetting)
        case .restageAndApply:
            startActivation(profile, applyToTunnel: true, preferCachedSource: true)
        }
    }

     
     
     
     
     
     
     
     
     
     
    func updateProxySelection(
        profileID: String,
        group: String,
        member: String,
        catalog: ProxiesOverviewModel? = nil
    ) throws {
        guard let profileStore,
              let latest = profileStore.load().first(where: { $0.id == profileID }) else {
            throw PipelineError.sourceUnavailable("the profile is no longer available")
        }
         
         
         
         
        let catalog = try catalog ?? {
            let projected = cachedUIProjectedYAML(for: latest)
                ?? CustomNodesGroupMaterializer.projectForUI(sourceYAML: sourceYAML(for: latest), profile: latest)
                ?? sourceYAML(for: latest)
            return ProxiesOverviewModel.make(
                sourceYAML: projected,
                selectedMap: latest.selectedMap
            )
        }()
        let isGlobal = group == GlobalProxySelectionPolicy.groupName
        if isGlobal {
             
             
             
            let known = catalog.proxies.contains { $0.name == member }
                || catalog.groups.contains { $0.name == member }
            guard known else {
                throw PipelineError.sourceUnavailable("the selected proxy is no longer available")
            }
        } else {
            guard let targetGroup = catalog.groups.first(where: { $0.name == group }),
                  ProxyGroupControlKind(rawType: targetGroup.type).acceptsMemberChoice,
                  targetGroup.members.contains(where: { $0.name == member }) else {
                throw PipelineError.sourceUnavailable("the selected proxy is no longer available")
            }
        }
        var updated = latest
        updated.selectedMap[group] = member
        updated.currentGroupName = group
        try profileStore.upsert(updated)
         
         
         
         
         
        if let index = profiles.firstIndex(where: { $0.id == updated.id }) {
            profiles[index] = updated
        } else {
            load()
        }
    }

     
     
     
     
     
     
    private var derivedModeMemo:
        (profileID: String, patchJSON: String, mode: Profile.OutboundMode)?

     
     
     
    func outboundMode(for profile: Profile) -> Profile.OutboundMode {
        let runtime = FlClashRuntimeConfig.load(
            from: runtimeDefaults
        )
        if let raw = OverridePatch(
            patchJSON: runtime.patchJSON
        ).mode,
           let mode = Profile.OutboundMode(
               rawValue: raw.lowercased()
           ) {
            return mode
        }
        if let memo = derivedModeMemo,
           memo.profileID == profile.id,
           memo.patchJSON == profile.override.patchJSON {
            return memo.mode
        }
        guard let raw = runtimeSourceYAML(for: profile),
              let generated = try? ProfileRuntimeConfigBuilder.buildProduction(
                raw: raw,
                profile: profile,
                runtimeOverride: runtime
              ),
              let json = try? ConfigTransforms.yamlToJSON(generated),
              let decoded = try? JSONSerialization.jsonObject(with: Data(json.utf8)),
              let object = decoded as? [String: Any],
              let rawMode = object["mode"] as? String,
              let mode = Profile.OutboundMode(rawValue: rawMode.lowercased()) else {
            derivedModeMemo = (profile.id, profile.override.patchJSON, .rule)
            return .rule
        }
        derivedModeMemo = (profile.id, profile.override.patchJSON, mode)
        return mode
    }

     
     
     
     
    func settingsProfile(for profile: Profile) -> Profile {
        var projected = FlClashRuntimeConfig.sanitizedProfile(
            profile
        )
        var patch = OverridePatch(
            patchJSON: projected.override.patchJSON
        )
        let runtime = FlClashRuntimeConfig.load(
            from: runtimeDefaults
        )
        patch.overlayTopLevelKeys(
            OverridePatch.globalRuntimeKeys,
            from: OverridePatch(patchJSON: runtime.patchJSON)
        )
        projected.override.patchJSON = patch.patchJSON
        projected.override.dnsOverridesProfiles = runtime.dnsOverridesProfiles
        projected.outboundMode = OverridePatch(
            patchJSON: runtime.patchJSON
        ).mode.flatMap(Profile.OutboundMode.init(rawValue:))
        return projected
    }

     
     
    func updateProxyChains(_ draft: ProfileProxyChainDraft) throws {
        guard let profileStore,
              let latest = profileStore.load().first(where: { $0.id == draft.profileID }) else {
            throw PipelineError.sourceUnavailable("the profile is no longer available")
        }
        let updated = try draft.applying(to: latest)
        if let rawYAML = runtimeSourceYAML(for: latest) {
            do {
                _ = try ProfileRuntimeConfigBuilder.runtimePreview(
                    raw: rawYAML,
                    profile: updated
                )
            } catch let error as LegacyRelayMigrationError {
                 
                 
                 
                 
                guard draft.removesLegacyRelayConfirmation(
                    requiredBy: error,
                    from: latest
                ) else {
                    throw error
                }
            }
        } else if !draft.proxyChain.isEmpty || !draft.legacyRelayMigrations.isEmpty {
            throw PipelineError.sourceUnavailable(
                "Sync or prepare this profile before configuring proxy chains."
            )
        }
        try updateConfiguration(updated)
    }

     
     
     
     
     
     
     
     
     
     
    nonisolated(unsafe) var runtimePreviewValidator: @Sendable (String, Profile) throws -> Void = {
        raw, profile in
        _ = try ProfileRuntimeConfigBuilder.runtimePreview(raw: raw, profile: profile)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    nonisolated static func refusalBelongsToActivation(_ message: String) -> Bool {
        message.contains("is remote (HTTP)")
    }

    nonisolated(unsafe) var coreAcceptsDocument: @Sendable (String, URL) throws -> Void = {
        document, container in
         
         
         
         
         
#if os(macOS)
        try AppCoreSetup.withConfiguration(container: container) {
            var error: NSError?
            guard HakoCheckConfig(document, &error) else { throw error ?? HakoCoreRefusal() }
        }
#else
        _ = try AppConfigurationPreflight.validate(
            document,
            container: container,
            fallbackCode: 2
        )
#endif
    }

     
     
     
     
     
     
     
    func updateProxyNode(originalJSON: String, editedJSON: String) async throws {
        guard let profileStore,
              let profileID = activeProfileID ?? ProfileCenterPolicy.automaticSelectionID(
                profiles: profiles,
                activeProfileID: nil
              ),
              let latest = profileStore.load().first(where: { $0.id == profileID }) else {
            throw PipelineError.sourceUnavailable("there is no selected profile to edit")
        }
        let storedSource = sidecarYAML(for: latest)
        guard ProxyNodeEditPolicy.isEditable(hasStoredSource: storedSource != nil),
              let sourceYAML = storedSource else {
            throw PipelineError.sourceUnavailable(
                ProxyNodeEditPolicy.unavailableReason
            )
        }

        let original = try Self.proxyMapping(from: originalJSON)
        let edited = try Self.proxyMapping(from: editedJSON)
        guard let name = original["name"] as? String,
              !name.isEmpty,
              edited["name"] as? String == name,
              edited["type"] as? String == original["type"] as? String else {
            throw ProxyNodeOverrideError.invalidConfiguration
        }

         
         
         
         
        let originalMapping = try Self.onlyProxy(in: Self.singleProxyYAML(original))
        let editedMapping = try Self.onlyProxy(in: Self.singleProxyYAML(edited))
        var patch = Self.mergePatch(from: originalMapping, to: editedMapping)
        patch.removeValue(forKey: "name")
        patch.removeValue(forKey: "type")
        let patchData = try JSONSerialization.data(
            withJSONObject: patch,
            options: [.sortedKeys]
        )
        let patchJSON = String(decoding: patchData, as: UTF8.self)

        var updated = latest
        var nodeOverrides = updated.proxyNodeOverrides ?? ProxyNodeOverrideSpec()
        nodeOverrides.setPatch(patchJSON, for: name)
        updated.proxyNodeOverrides = nodeOverrides.isEmpty ? nil : nodeOverrides

         
         
        let validate = runtimePreviewValidator
        let candidate = updated
        try await Task.detached(priority: .userInitiated) {
            try validate(sourceYAML, candidate)
        }.value
        try updateConfiguration(updated)
    }

     
     
    func proxyNodeOverridePatch(named name: String) -> String? {
        guard let profileStore,
              let profileID = activeProfileID ?? ProfileCenterPolicy.automaticSelectionID(
                profiles: profiles,
                activeProfileID: nil
              ),
              let latest = profileStore.load().first(where: { $0.id == profileID }) else {
            return nil
        }
        return latest.proxyNodeOverrides?.patch(for: name)
    }

     
     
    func removeProxyNodeOverride(named name: String) throws {
        guard let profileStore,
              let profileID = activeProfileID ?? ProfileCenterPolicy.automaticSelectionID(
                profiles: profiles,
                activeProfileID: nil
              ),
              let latest = profileStore.load().first(where: { $0.id == profileID }) else {
            throw PipelineError.sourceUnavailable("there is no selected profile to edit")
        }
        var updated = latest
        var nodeOverrides = updated.proxyNodeOverrides ?? ProxyNodeOverrideSpec()
        nodeOverrides.removePatch(for: name)
        updated.proxyNodeOverrides = nodeOverrides.isEmpty ? nil : nodeOverrides
        try updateConfiguration(updated)
    }

    private static func proxyMapping(from json: String) throws -> [String: Any] {
        guard let mapping = try JSONSerialization.jsonObject(with: Data(json.utf8))
                as? [String: Any] else {
            throw ProxyNodeOverrideError.invalidConfiguration
        }
        return mapping
    }

    private static func singleProxyYAML(_ mapping: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: ["proxies": [mapping]],
            options: [.sortedKeys]
        )
        return try ConfigTransforms.jsonToYAML(String(decoding: data, as: UTF8.self))
    }

    private static func onlyProxy(in yaml: String) throws -> [String: Any] {
        let json = try ConfigTransforms.yamlToJSON(yaml)
        guard let root = try JSONSerialization.jsonObject(with: Data(json.utf8))
                as? [String: Any],
              let mapping = (root["proxies"] as? [[String: Any]])?.first else {
            throw ProxyNodeOverrideError.invalidConfiguration
        }
        return mapping
    }

    private static func mergePatch(
        from original: [String: Any],
        to edited: [String: Any]
    ) -> [String: Any] {
        var patch: [String: Any] = [:]
        for key in Set(original.keys).union(edited.keys) {
            guard let editedValue = edited[key] else {
                patch[key] = NSNull()
                continue
            }
            guard let originalValue = original[key] else {
                 
                 
                 
                 
                if editedValue is NSNull { continue }
                patch[key] = editedValue
                continue
            }
            if let oldObject = originalValue as? [String: Any],
               let newObject = editedValue as? [String: Any] {
                let nested = mergePatch(from: oldObject, to: newObject)
                if !nested.isEmpty { patch[key] = nested }
            } else if !jsonValuesEqual(originalValue, editedValue) {
                patch[key] = editedValue
            }
        }
        return patch
    }

    private static func jsonValuesEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        guard JSONSerialization.isValidJSONObject([lhs]),
              JSONSerialization.isValidJSONObject([rhs]),
              let left = try? JSONSerialization.data(withJSONObject: [lhs], options: [.sortedKeys]),
              let right = try? JSONSerialization.data(withJSONObject: [rhs], options: [.sortedKeys])
        else { return false }
        return left == right
    }

     
     
     
     
    func updateAdvancedOverrides(_ draft: ProfileAdvancedOverridesDraft) throws {
        guard let profileStore,
              let latest = profileStore.load().first(where: { $0.id == draft.profileID }) else {
            throw ProfileAdvancedOverridesError.profileChanged
        }

        let availableScriptIDs = Set(ScriptLibrary.load().map(\.id))
        let updated = try draft.applying(
            to: latest,
            availableScriptIDs: availableScriptIDs
        )
        let profileOwned = FlClashRuntimeConfig.sanitizedProfile(updated)
        if let rawYAML = runtimeSourceYAML(for: latest) {
            do {
                _ = try ProfileRuntimeConfigBuilder.runtimePreview(
                    raw: rawYAML,
                    profile: profileOwned,
                    runtimeOverride: FlClashRuntimeConfig.load(
                        from: runtimeDefaults
                    )
                )
            } catch {
                 
                 
                 
                 
                 
                throw ProfileAdvancedOverridesError.validationFailed(
                    reason: (error as NSError).localizedDescription
                )
            }
        }
        try updateConfiguration(profileOwned)
    }

     
     
     
     
    func providerDefinitionsDraft(for profile: Profile) throws -> ProfileProviderDefinitionsDraft {
        guard let profileStore,
              let latest = profileStore.load().first(where: { $0.id == profile.id }) else {
            throw ProfileProviderDefinitionError.profileChanged
        }
        let baseline = try providerDefinitionsBaseline(for: latest)
        return try ProfileProviderDefinitionsDraft(
            profile: latest,
            baselineYAML: baseline
        )
    }

     
     
     
     
     
    func providerDefinitionsDraftAsync(
        for profile: Profile
    ) async throws -> ProfileProviderDefinitionsDraft {
        guard let latest = profiles.first(where: { $0.id == profile.id }),
              let raw = runtimeSourceYAML(for: latest) else {
            throw ProfileResourceSummaryError.sourceUnavailable
        }
        return try await Self.providerDraft(profile: latest, raw: raw)
    }

    struct ProviderDraftKey: Equatable {
        let profile: Profile
        let raw: String
    }

     
     
     
     
     
     
    @MainActor
    static let lastProviderDraft = HakoLastPreparation<
        ProviderDraftKey, Result<ProfileProviderDefinitionsDraft, ProfileProviderDefinitionError>
    >()

    @MainActor
    static func prewarmProviderDraft(profile: Profile, raw: String) async {
        _ = try? await providerDraft(profile: profile, raw: raw)
    }

    @MainActor
    static func providerDraft(
        profile latest: Profile, raw: String
    ) async throws -> ProfileProviderDefinitionsDraft {
        let key = ProviderDraftKey(profile: latest, raw: raw)
        let outcome = await lastProviderDraft.value(for: key) {
            let began = DispatchTime.now().uptimeNanoseconds
            let made: Result<ProfileProviderDefinitionsDraft, ProfileProviderDefinitionError> =
                await Task.detached(priority: .userInitiated) {
                    do {
                        let baseline = try ProfileRuntimeConfigBuilder.buildProduction(
                            raw: raw,
                            profile: latest,
                            applyProviderDefinitions: false
                        )
                        return .success(
                            try ProfileProviderDefinitionsDraft(
                                profile: latest,
                                baselineYAML: baseline
                            )
                        )
                    } catch {
                        return .failure(.invalidConfiguration)
                    }
                }.value
            HakoPerf.span(
                "providers.draft.prepare",
                milliseconds: Double(
                    DispatchTime.now().uptimeNanoseconds - began
                ) / 1_000_000,
                detail: "yamlBytes=\(raw.utf8.count)"
            )
            return made
        }
        return try outcome.get()
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func updateCustomNodePayload(
        _ definitionJSON: String?, for profileID: String
    ) throws {
        guard let profileStore,
              let latest = profileStore.load().first(where: { $0.id == profileID })
        else { throw ProfileProviderDefinitionError.profileChanged }

        var spec = latest.providerDefinitions ?? ProfileProviderDefinitionSpec()
        let name = CustomNodePayload.providerName
        if let json = definitionJSON {
            if let at = spec.proxyProviders.firstIndex(where: { $0.name == name }) {
                spec.proxyProviders[at].definitionJSON = json
            } else {
                spec.proxyProviders.append(
                    ProfileProviderDefinitionMutation(name: name, definitionJSON: json)
                )
            }
        } else {
            spec.proxyProviders.removeAll { $0.name == name }
        }

        var updated = latest
        updated.providerDefinitions = spec.isEmpty ? nil : spec

         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        let began = DispatchTime.now().uptimeNanoseconds
        defer {
            HakoPerf.span(
                "save.customNodePayload",
                milliseconds: Double(
                    DispatchTime.now().uptimeNanoseconds - began
                ) / 1_000_000,
                detail: "providers=\(spec.proxyProviders.count)"
            )
        }
         
         
         
         
        try updateConfiguration(updated)
    }

    func updateProviderDefinitions(_ draft: ProfileProviderDefinitionsDraft) throws {
        guard let profileStore, let workingDir,
              let latest = profileStore.load().first(where: { $0.id == draft.profileID }) else {
            throw ProfileProviderDefinitionError.profileChanged
        }
        let baseline = try providerDefinitionsBaseline(for: latest)
        var updated = try draft.applying(
            to: latest,
            currentBaselineYAML: baseline
        )
        guard let raw = runtimeSourceYAML(for: latest) else {
            throw ProfileResourceSummaryError.sourceUnavailable
        }
        let previousResources = externalResourceData(for: latest)

        do {
            let generated = try ProfileRuntimeConfigBuilder.buildProduction(
                raw: raw,
                profile: updated
            )
            let json = try ConfigTransforms.yamlToJSON(generated)
            guard let root = try JSONSerialization.jsonObject(with: Data(json.utf8))
                    as? [String: Any] else {
                throw ProfileProviderDefinitionError.invalidConfiguration
            }
            try replaceProviderResources(
                draft: draft,
                latest: latest,
                updated: &updated,
                runtimeRoot: root,
                previousResources: previousResources,
                workingDir: workingDir
            )
            try updateConfiguration(updated)
        } catch let bounded as ProfileProviderDefinitionError {
            try? ProfileExternalResourceStore.replace(
                previousResources,
                profileID: latest.id,
                coreHomeDir: workingDir
            )
            throw bounded
        } catch {
            try? ProfileExternalResourceStore.replace(
                previousResources,
                profileID: latest.id,
                coreHomeDir: workingDir
            )
             
             
             
             
             
             
             
             
             
             
             
             
             
            throw ProfileProviderDefinitionError.buildRefused(
                error.localizedDescription
            )
        }
    }

    private func replaceProviderResources(
        draft: ProfileProviderDefinitionsDraft,
        latest: Profile,
        updated: inout Profile,
        runtimeRoot root: [String: Any],
        previousResources: [String: Data],
        workingDir: URL
    ) throws {
        let providerCapabilityPrefixes = ["proxy-provider.", "rule-provider."]
        var references = (latest.externalResources ?? []).filter { reference in
            !providerCapabilityPrefixes.contains(where: reference.capabilityID.hasPrefix)
        }
        var resources: [String: Data] = [:]
        for reference in references {
            guard let data = previousResources[reference.storageKey] else {
                throw ProfileExternalResourceError.storedResourceMissing(
                    field: reference.fieldPath.joined(separator: ".")
                )
            }
            resources[reference.storageKey] = data
        }

        let requirements = IOSExternalResourceCatalog.requirements(root: root).filter {
            $0.capability.section == .proxyProvider
                || $0.capability.section == .ruleProvider
        }
        for requirement in requirements {
            let kind: ProfileProviderKind = requirement.capability.section == .proxyProvider
                ? .proxy : .rule
            let reference = ProfileExternalResourceImporter.reference(
                profileID: latest.id,
                requirement: requirement
            )
            let data: Data
            if let selected = draft.managedFile(for: requirement.proxyName, kind: kind) {
                let selectedName = selected.fileName.lowercased()
                let requiredName = requirement.rawValue
                    .replacingOccurrences(of: "\\", with: "/")
                    .split(separator: "/")
                    .last
                    .map(String.init)?.lowercased() ?? ""
                guard selectedName == requiredName else {
                    throw ProfileProviderDefinitionError.missingManagedFile
                }
                data = selected.data
            } else if (latest.externalResources ?? []).contains(reference),
                      let existing = previousResources[reference.storageKey] {
                data = existing
            } else {
                throw ProfileProviderDefinitionError.missingManagedFile
            }
            references.append(reference)
            resources[reference.storageKey] = data
        }
        updated.externalResources = references.isEmpty
            ? nil : Array(Set(references)).sorted { $0.storageKey < $1.storageKey }

        try ProfileExternalResourceStore.replace(
            resources,
            profileID: latest.id,
            coreHomeDir: workingDir
        )
    }

    private func providerDefinitionsBaseline(for profile: Profile) throws -> String {
        guard let raw = runtimeSourceYAML(for: profile) else {
            throw ProfileResourceSummaryError.sourceUnavailable
        }
        do {
            return try ProfileRuntimeConfigBuilder.buildProduction(
                raw: raw,
                profile: profile,
                applyProviderDefinitions: false
            )
        } catch {
             
             
             
             
             
            throw ProfileProviderDefinitionError.buildRefused(
                error.localizedDescription
            )
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private func updateGlobalConfiguration(
        _ candidate: Profile,
        replacing keys: Set<String>,
        configureSpec: ((inout OverrideSpec) -> Void)? = nil,
        runtimeAlreadyCarriesChange: Bool = false
    ) throws {
        guard let profileStore else {
            throw PipelineError.sourceUnavailable(
                "the shared profile store is unavailable"
            )
        }
        let previousProfiles = profileStore.load()
        guard let candidateIndex = previousProfiles.firstIndex(
            where: { $0.id == candidate.id }
        ) else {
            throw PipelineError.sourceUnavailable(
                "the profile is no longer available"
            )
        }

        let previousRuntime = FlClashRuntimeConfig.load(
            from: runtimeDefaults
        )
        var updatedRuntime = FlClashRuntimeConfig.replacingGlobalFields(
            in: previousRuntime,
            with: candidate.override.patchJSON,
            keys: keys
        )
        configureSpec?(&updatedRuntime)
        let sanitizedCandidate = FlClashRuntimeConfig.sanitizedProfile(
            candidate
        )
        var updatedProfiles = previousProfiles
        updatedProfiles[candidateIndex] = sanitizedCandidate

        do {
            try profileStore.save(updatedProfiles)
            FlClashRuntimeConfig.save(
                updatedRuntime,
                in: runtimeDefaults
            )
            guard FlClashRuntimeConfig.load(
                from: runtimeDefaults
            ) == updatedRuntime else {
                throw PipelineError.preflightFailed(
                    "the app-wide runtime preference could not be persisted"
                )
            }
        } catch {
            try? profileStore.save(previousProfiles)
            FlClashRuntimeConfig.save(
                previousRuntime,
                in: runtimeDefaults
            )
            recordFailure(
                error,
                context: .activation,
                operation: .activation(candidate.id),
                preservesLastKnownGood: true
            )
            throw error
        }

        statusMessage = "Runtime settings saved for all profiles"
        clearFailure()
        load()

        guard let activeProfileID,
              let active = updatedProfiles.first(
                  where: { $0.id == activeProfileID }
              ) else {
            return
        }
        switch ProfileSettingsRestagePolicy.action(
            profileID: active.id,
            activeProfileID: activeProfileID,
            vpnStatus: vpn.status,
            runtimeAlreadyCarriesChange: runtimeAlreadyCarriesChange
        ) {
        case .persistOnly:
            break
        case .restageOnly:
            startActivation(
                active,
                applyToTunnel: false,
                preferCachedSource: true,
                because: HakoPerf.Reason.globalConfiguration
            )
        case .restageAndApply:
            startActivation(
                active,
                applyToTunnel: true,
                preferCachedSource: true
            )
        }
    }

     
    private func updateConfiguration(_ profile: Profile) throws {
        let funnelBegan = DispatchTime.now().uptimeNanoseconds
        defer {
            HakoPerf.span(
                "save.updateConfiguration",
                milliseconds: Double(
                    DispatchTime.now().uptimeNanoseconds - funnelBegan
                ) / 1_000_000,
                detail: "profile=\(profile.id)"
            )
        }
        guard let profileStore else {
            throw PipelineError.sourceUnavailable("the shared profile store is unavailable")
        }
        do {
            try profileStore.upsert(profile)
            statusMessage = .format("%@ saved", [profile.label])
            clearFailure()
            load()
            savedConfigurationGeneration &+= 1
        } catch {
            recordFailure(
                error,
                context: .localImport,
                operation: nil,
                preservesLastKnownGood: true
            )
            throw error
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func updateEdited(
        _ profile: Profile,
        sourceYAML: String?,
        resourceFiles: [ExternalResourceImportFile] = [],
        disablingAutoUpdate: Bool = false
    ) async throws {
        guard let profileStore, let workingDir else { return }
        if let sourceYAML, let library = configurationLibraryStore {
            let snapshot = try await Task.detached { try library.snapshot() }.value
            if let recipe = snapshot.recipes.first(where: { $0.id == profile.id }), recipe.preservesOriginal != true {
                guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
                changingConfigurationLibrary = true
                defer { changingConfigurationLibrary = false }
                let prepared = try await Task.detached(priority: .userInitiated) {
                    let files = try ConfigurationCenterSourceBridge.capturedFiles(profile: profile, yaml: sourceYAML, workingDir: workingDir)
                    let replacement = try ConfigurationCenterSourceBridge.payload(label: profile.label,
                        origin: .file(profile.label + ".yaml"), original: Data(sourceYAML.utf8), yaml: sourceYAML,
                        resources: files + resourceFiles, id: "edited-" + UUID().uuidString)
                    return try library.prepareWholeSourceEditing(profile.id, replacement: replacement,
                        expectedGeneration: snapshot.generation, resolveInput: ConfigurationCenterSourceBridge.boundInput)
                }.value
                try await saveConfigurationPlan(candidate: prepared.candidate, payloads: prepared.payloads,
                    compositions: [profile.id: prepared.composition], generation: snapshot.generation)
                return
            }
            if let recipe = snapshot.recipes.first(where: { $0.id == profile.id }), recipe.preservesOriginal == true {
                guard !changingConfigurationLibrary else { throw ConfigurationLibraryError.busy }
                changingConfigurationLibrary = true
                defer { changingConfigurationLibrary = false }
                let prepared = try await Task.detached {
                    let previous = try library.payload(recipe.ruleSource)
                    var replacement = try ConfigurationCenterSourceBridge.payload(label: profile.label,
                        origin: previous.record.origin, original: Data(sourceYAML.utf8), yaml: sourceYAML,
                        resources: resourceFiles, id: previous.record.id)
                    replacement.record.registersSuppliedRules = true
                    replacement.record.updateIntervalHours = previous.record.updateIntervalHours
                    replacement.record.userAgent = previous.record.userAgent
                    replacement.record.dnsOverHTTPS = previous.record.dnsOverHTTPS
                    if resourceFiles.isEmpty {
                        replacement = .init(record: replacement.record, original: replacement.original,
                            documentJSON: replacement.documentJSON, resourceFiles: previous.resourceFiles)
                    }
                    return try library.prepareSourceUpdate(replacement, expectedGeneration: snapshot.generation,
                        updatingPinnedConsumers: true, resolveInput: ConfigurationCenterSourceBridge.boundInput)
                }.value
                try await saveConfigurationPlan(candidate: prepared.candidate, payloads: prepared.payloads,
                    compositions: prepared.compositions, generation: snapshot.generation)
                return
            }
        }
        let previous = profileStore.load().first(where: { $0.id == profile.id }) ?? profile
        let previousSource = sidecarYAML(for: previous)
        let previousResources = externalResourceData(for: previous)
        var updated = ProfileMetadataUpdate.normalizingSourceChange(
            previous: previous, updated: profile
        )
        if let sourceYAML {
             
             
             
             
             
             
             
            let hydrated = sourceYAML
            let resourceSource = externalResourceSource(previous.source)
            let containerForCore = container
            let coreGate = coreAcceptsDocument
            let committed = updated
            let prepared = try await Task
                .detached(priority: .userInitiated) {
                     
                     
                     
                     
                     
                     
                     
                     
                    try ConfigTransforms.validateSource(hydrated)
                    if let container = containerForCore {
                        do {
                            try coreGate(hydrated, container)
                        } catch let refusal where Self.refusalBelongsToActivation(
                            refusal.localizedDescription
                        ) {
                             
                             
                             
                             
                             
                             
                        }
                    }
                    let prepared = try ProfileExternalResourceImporter.prepare(
                        yaml: hydrated,
                        profileID: previous.id,
                        source: resourceSource,
                        files: resourceFiles,
                        existingReferences: previous.externalResources ?? [],
                        existingPublicResources: previousResources
                    )
                     
                     
                     
                     
                    _ = try ProfileRuntimeConfigBuilder.runtimePreview(
                        raw: prepared.yaml,
                        profile: committed
                    )
                    return prepared
                }.value
            do {
                try ProfileExternalResourceStore.replace(
                    prepared.publicResources,
                    profileID: previous.id,
                    coreHomeDir: workingDir
                )
                updated.externalResources = prepared.references.isEmpty
                    ? nil : prepared.references
                updated.usesLocalSourceOverride = true
                if disablingAutoUpdate, case .url = updated.source {
                    updated.autoUpdate = false
                }
                 
                 
                 
                 
                 
                 
                 
                try profileStore.upsert(updated)
                 
                try cacheSourceYAML(prepared.yaml, for: updated)
            } catch {
                try? profileStore.upsert(previous)
                try? ProfileExternalResourceStore.replace(
                    previousResources,
                    profileID: previous.id,
                    coreHomeDir: workingDir
                )
                restoreSourceYAML(previousSource, for: previous)
                throw error
            }
        } else {
            try profileStore.upsert(updated)
        }
        load()
         
         
        savedConfigurationGeneration &+= 1

    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func baseYAML(for profile: Profile) -> String? {
        let key = projectionKey(for: profile)
        if let cached = baseYAMLCache[profile.id], cached.key == key {
            return cached.value
        }
        let value = RunningCoreDeviations.baseDocument(
            profile: profile,
            sidecarYAML: sourceYAML(for: profile)
        ) ?? uiProjectedYAML(for: profile)
        baseYAMLCache[profile.id] = (key, value)
        return value
    }

     
     
     
    func cachedUIProjectedYAML(for profile: Profile) -> String? {
        let key = projectionKey(for: profile)
        if let cached = projectedYAMLCache[profile.id], cached.key == key {
            return cached.value
        }
        return nil
    }

     
     
     
     
    func uiProjectionInputs(for profile: Profile) -> (key: String, sourceYAML: String?) {
        (projectionKey(for: profile), sourceYAML(for: profile))
    }

     
     
    func rememberUIProjectedYAML(_ value: String?, key: String, for profile: Profile) {
        projectedYAMLCache[profile.id] = (key, value)
    }

     
     
     
     
     
     
     
     
    func loadUIProjectedYAML(for profile: Profile) async -> String? {
        if let cached = cachedUIProjectedYAML(for: profile) { return cached }
        let key = projectionKey(for: profile)
        let source = await loadSourceYAML(for: profile)
        let value = await Task.detached(priority: .userInitiated) {
            CustomNodesGroupMaterializer.projectForUI(
                sourceYAML: source,
                profile: profile
            )
        }.value
        rememberUIProjectedYAML(value, key: key, for: profile)
        return value
    }

     
     
     
     
    func loadPresentedProxiesYAML(for profile: Profile) async -> String? {
        let scriptBody = ScriptLibrary.load().first { $0.id == profile.selectedScriptID }?.body
        let key = ProxiesPresentedDocument.key(projectionKey: projectionKey(for: profile), profile: profile, scriptBody: scriptBody)
        if let cached = presentedProxiesYAMLCache[profile.id], cached.key == key { return cached.value }
        let source = await loadSourceYAML(for: profile)
        let fallback = await loadUIProjectedYAML(for: profile)
        let value = await Task.detached(priority: .userInitiated) {
            ProxiesPresentedDocument.make(source: source, profile: profile, fallback: fallback)
        }.value
        presentedProxiesYAMLCache[profile.id] = (key, value)
        return value
    }

    func uiProjectedYAML(for profile: Profile) -> String? {
        let key = projectionKey(for: profile)
        if let cached = projectedYAMLCache[profile.id], cached.key == key {
            return cached.value
        }
        let value = CustomNodesGroupMaterializer.projectForUI(
            sourceYAML: sourceYAML(for: profile),
            profile: profile
        )
        projectedYAMLCache[profile.id] = (key, value)
        return value
    }

     
     
     
     
     
     
     
     
     
     
     
    func effectiveYAML(for profile: Profile) -> String? {
        let key = effectiveYAMLKey(for: profile)
        if let cached = effectiveYAMLCache[profile.id], cached.key == key {
            return cached.value
        }
        let value = previewText(for: profile)
        effectiveYAMLCache[profile.id] = (key, value)
        return value
    }

    private func effectiveYAMLKey(for profile: Profile) -> String {
        var parts = [projectionKey(for: profile)]
         
         
         
         
         
         
         
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        if let encoded = try? encoder.encode(FlClashRuntimeConfig.load()) {
            parts.append("\(encoded.hashValue)")
        }
        parts.append(profile.postMergeScriptID ?? "-")
        parts.append(ScriptSettings.enabled() ? "script" : "-")
        return parts.joined(separator: "|")
    }

    private func projectionKey(for profile: Profile) -> String {
        var parts: [String] = [profile.id]
        if let workingDir {
            let sidecar = workingDir
                .appendingPathComponent("store/\(profile.id)/source.yaml")
            let attributes = try? FileManager.default
                .attributesOfItem(atPath: sidecar.path)
            let size = (attributes?[.size] as? NSNumber)?.intValue ?? -1
            let modified = (attributes?[.modificationDate] as? Date)?
                .timeIntervalSince1970 ?? -1
            parts.append("\(size)|\(modified)")
             
             
             
            parts.append(profile.activeRevision ?? "-")
        }
        parts.append(profile.lastUpdatedAt.map { "\($0.timeIntervalSince1970)" } ?? "-")
        parts.append(profile.override.patchJSON ?? "-")
        if let definitions = profile.providerDefinitions,
           let encoded = try? JSONEncoder().encode(definitions) {
            parts.append("\(encoded.hashValue)")
        }
         
         
         
         
         
        parts.append(profile.sourceCredentialsRedacted == true ? "1" : "0")
        let references = (profile.sourceCredentials ?? [])
            + (profile.proxyCredentials ?? [])
        if !references.isEmpty,
           let encoded = try? JSONEncoder().encode(references) {
            parts.append("\(encoded.hashValue)")
             
             
             
             
            if profile.sourceCredentialsRedacted == true {
                parts.append("\(credentialFingerprint(for: references))")
            }
        }
         
         
         
        if let overrides = profile.proxyNodeOverrides,
           let encoded = try? JSONEncoder.sortedKeys.encode(overrides) {
            parts.append("o:\(encoded.count)|\(encoded.hashValue)")
        }
        if let chain = profile.proxyChain,
           let encoded = try? JSONEncoder.sortedKeys.encode(chain) {
            parts.append("c:\(encoded.count)|\(encoded.hashValue)")
        }
        return parts.joined(separator: "\u{1}")
    }

     
     
     
     
     
    private func credentialFingerprint(
        for references: [ProxyCredentialReference]
    ) -> Int {
        var hasher = Hasher()
        for key in references.map(\.key).sorted() {
            hasher.combine(key)
            hasher.combine(credentials.get(key) ?? Data())
        }
        return hasher.finalize()
    }

    func move(from source: IndexSet, to destination: Int) {
        guard let profileStore else { return }
        profiles = ProfileReorder.apply(profiles, from: source, to: destination)
        try? profileStore.save(profiles)
        load()
    }

     
    private var tunnelIsRunning: Bool {
        vpn.status == "connected" || vpn.status == "reasserting"
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func configurationLibrarySources(for profile: Profile) -> [String]? {
        guard let snapshot = try? configurationLibraryStore?.snapshot(),
              let recipe = snapshot.recipes.first(where: { $0.id == profile.id }) else { return nil }
        var seen = Set<String>()
        return (recipe.sources + [recipe.ruleSource]).compactMap { reference -> String? in
            guard seen.insert(reference.id).inserted,
                  let record = snapshot.sources.first(where: { $0.id == reference.id }),
                  case .subscription = record.origin, record.isRetainedSnapshot != true else { return nil }
            return reference.id
        }
    }

     
     
    struct ConfigurationSourceRefresh {
        var changed: [String] = []
         
         
         
         
         
         
         
         
        var failures: [ProviderDownloadFailure] = []
    }

     
     
     
     
     
     
     
     
     
    func refreshConfigurationSources(_ references: [String]) async throws -> ConfigurationSourceRefresh {
         
         
        let before = (try? configurationLibraryStore?.snapshot()) ?? nil
        let records = Dictionary(uniqueKeysWithValues: (before?.sources ?? []).map { ($0.id, $0) })
        let versions = records.mapValues(\.version)
        var outcome = ConfigurationSourceRefresh()
        for reference in references {
            do {
                try await refreshConfigurationSource(reference)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let record = records[reference]
                var link: String?
                if case let .subscription(url)? = record?.origin { link = url }
                outcome.failures.append(.init(provider: record?.label ?? reference, url: link, underlying: error))
            }
        }
        let after = (try? configurationLibraryStore?.snapshot()) ?? nil
        outcome.changed = references.filter { reference in
            guard let now = after?.sources.first(where: { $0.id == reference })?.version else { return false }
            return versions[reference] != now
        }
        return outcome
    }

     
     
     
     
    private func restageAfterSourceRefresh(_ profileID: String, changed: [String]) async {
        guard !changed.isEmpty, profileID == activeProfileID, tunnelIsRunning,
              let latest = profiles.first(where: { $0.id == profileID }) else { return }
        startActivation(latest, applyToTunnel: true, preferCachedSource: true,
                        because: HakoPerf.Reason.profileSync)
        await waitForPendingActivation()
    }

     
     
     
    func sync(_ profile: Profile) {
         
         
         
         
         
         
         
         
         
         
         
         
        if let references = configurationLibrarySources(for: profile) {
             
             
             
            guard !references.isEmpty else { return }
            clearFailure()
            statusMessage = .format("Syncing %@…", [profile.label])
            Task { [weak self] in
                guard let self else { return }
                do {
                    let outcome = try await self.refreshConfigurationSources(references)
                     
                     
                    self.load()
                    await self.restageAfterSourceRefresh(profile.id, changed: outcome.changed)
                     
                     
                     
                    if outcome.failures.isEmpty {
                        self.statusMessage = .format("%@ synced", [profile.label])
                        self.clearFailure()
                    } else {
                        self.recordFailure(ProviderDownloadFailuresError(failures: outcome.failures),
                                           context: .subscription, operation: nil, preservesLastKnownGood: true)
                    }
                } catch {
                    self.recordFailure(error, context: .subscription, operation: nil, preservesLastKnownGood: true)
                }
            }
            return
        }
        if profile.id == activeProfileID {
             
             
             
             
             
             
            startActivation(profile, applyToTunnel: tunnelIsRunning, because: HakoPerf.Reason.profileSync)
            return
        }
        guard case .url = profile.source else { return }
        clearFailure()
        statusMessage = .format("Syncing %@…", [profile.label])
        Task { [weak self] in
            guard let self else { return }
            let subscriptions = SubscriptionManager(
                downloader: self.downloader, credentials: self.credentials)
            do {
                guard let profileStore = self.profileStore,
                      let workingDir = self.workingDir else {
                    throw PipelineError.sourceUnavailable(
                        "the shared profile store is unavailable"
                    )
                }
                let result = try await SubscriptionSourceRefresher.refresh(
                    profile: profile,
                    manager: subscriptions,
                    profileStore: profileStore,
                    credentials: self.credentials,
                    workingDirectory: workingDir
                )
                self.load()
                let heldBack = self.profiles.first(where: { $0.id == profile.id })?.suppressedUpdates?.count ?? 0
                self.statusMessage = result == .unchanged
                    ? .format("%@ is up to date", [profile.label])
                    : heldBack > 0
                        ? .format("%@ synced · %@ change(s) held back by your settings", [profile.label, String(heldBack)])
                        : .format("%@ synced", [profile.label])
                self.clearFailure()
            } catch {
                self.recordFailure(
                    error,
                    context: .subscription,
                    operation: .sync(profile.id)
                )
            }
        }
    }

     
     
     
     
     
     
    static func subscriptionProfiles(in profiles: [Profile]) -> [Profile] {
        profiles.filter {
            if case .url = $0.source { return true }
            return false
        }
    }

     
    var hasSubscriptionProfile: Bool {
        !Self.subscriptionProfiles(in: profiles).isEmpty
    }

     
     
    var isSyncingAll: Bool { batchTask != nil }

    func syncAll() {
        guard batchTask == nil else { return }
        let candidates = Self.subscriptionProfiles(in: profiles)
        batchReport = BatchUpdateReport(
            title: "Profile Sync",
            expectedCount: candidates.count
        )
        guard !candidates.isEmpty else { return }
        isBatchSyncing = true
        clearFailure()
        let runID = UUID()
        batchRunID = runID
        batchTask = Task { [weak self] in
            guard let self else { return }
            for profile in candidates {
                guard self.batchRunID == runID else { return }
                if Task.isCancelled {
                    self.markBatchCancelled()
                    break
                }
                self.busyProfileID = profile.id
                self.statusMessage = .format("Syncing %@…", [profile.label])
                do {
                     
                     
                     
                     
                     
                    let state = try await withThrowingTaskGroup(
                        of: BatchUpdateState.self
                    ) { group in
                        group.addTask { try await self.performBatchSync(profile) }
                        group.addTask {
                            try await Task.sleep(
                                nanoseconds: UInt64(Self.batchItemLimit * 1_000_000_000)
                            )
                            throw URLError(.timedOut)
                        }
                        defer { group.cancelAll() }
                        guard let first = try await group.next() else {
                            throw URLError(.timedOut)
                        }
                        return first
                    }
                    guard self.batchRunID == runID else { return }
                    self.recordBatchItem(
                        id: profile.id,
                        label: profile.label,
                        state: state,
                        message: state == .unchanged
                            ? "Already up to date."
                            : "The validated source was saved."
                    )
                } catch is CancellationError {
                    guard self.batchRunID == runID else { return }
                    self.markBatchCancelled()
                    break
                } catch {
                    guard self.batchRunID == runID else { return }
                    self.recordBatchFailure(error, profile: profile)
                }
                self.busyProfileID = nil
                self.load()
            }
            guard self.batchRunID == runID else { return }
            self.busyProfileID = nil
            self.isBatchSyncing = false
            self.batchRunID = nil
            self.batchTask = nil
            self.load()
            if let report = self.batchReport {
                 
                 
                 
                 
                 
                self.statusMessage = report.wasCancelled
                    ? "Profile sync cancelled"
                    : "Profile sync finished"
            }
        }
    }

     
     
     
     
    func refreshLegacyProfileAwaiting(_ profile: Profile) async throws -> BatchUpdateState {
        busyProfileID = profile.id
        defer { busyProfileID = nil; load() }
        return try await withThrowingTaskGroup(of: BatchUpdateState.self) { group in
            group.addTask { try await self.performBatchSync(profile) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(Self.batchItemLimit * 1_000_000_000))
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw URLError(.timedOut) }
            return first
        }
    }

    func cancelBatchSync() {
        guard let task = batchTask else { return }
         
         
         
         
         
         
        batchRunID = nil
        batchTask = nil
        task.cancel()
        busyProfileID = nil
        isBatchSyncing = false
        markBatchCancelled()
        statusMessage = "Profile sync cancelled"
    }

    func dismissBatchReport() {
         
         
         
         
        if isBatchSyncing {
            cancelBatchSync()
        }
        batchReport = nil
    }

    func retryBatchItem(id: String) {
        guard batchTask == nil,
              let profile = profiles.first(where: { $0.id == id }) else { return }
        isBatchSyncing = true
        let runID = UUID()
        batchRunID = runID
        batchTask = Task { [weak self] in
            guard let self else { return }
            self.busyProfileID = profile.id
            do {
                let state = try await self.performBatchSync(profile)
                guard self.batchRunID == runID else { return }
                self.recordBatchItem(
                    id: profile.id,
                    label: profile.label,
                    state: state,
                    message: state == .unchanged
                        ? "Already up to date."
                        : "The validated source was saved."
                )
            } catch is CancellationError {
                guard self.batchRunID == runID else { return }
                self.markBatchCancelled()
            } catch {
                guard self.batchRunID == runID else { return }
                self.recordBatchFailure(error, profile: profile)
            }
            guard self.batchRunID == runID else { return }
            self.busyProfileID = nil
            self.isBatchSyncing = false
            self.batchRunID = nil
            self.batchTask = nil
            self.load()
            self.drainPendingActivation()
        }
    }

     
     
     
     
     
     
     
     
     
     
    private func performBatchSync(_ profile: Profile) async throws -> BatchUpdateState {
        try Task.checkCancellation()

         
         
         
         
         
        if let references = configurationLibrarySources(for: profile) {
            guard !references.isEmpty else { return .unchanged }
            let outcome = try await refreshConfigurationSources(references)
             
             
             
            load()
            await restageAfterSourceRefresh(profile.id, changed: outcome.changed)
            guard outcome.failures.isEmpty else {
                throw ProviderDownloadFailuresError(failures: outcome.failures)
            }
            return outcome.changed.isEmpty ? .unchanged : .updated
        }

        let subscriptions = SubscriptionManager(
            downloader: downloader,
            credentials: credentials
        )
        guard let profileStore, let workingDir else {
            throw PipelineError.sourceUnavailable("the shared profile store is unavailable")
        }
        let result = try await SubscriptionSourceRefresher.refresh(
            profile: profile,
            manager: subscriptions,
            profileStore: profileStore,
            credentials: credentials,
            workingDirectory: workingDir
        )
        let state: BatchUpdateState = result == .unchanged ? .unchanged : .updated

        if state == .updated, profile.id == activeProfileID, tunnelIsRunning {
            try await republishToRunningTunnel(profile)
        }
        return state
    }

     
     
     
     
     
     
    private func republishToRunningTunnel(_ profile: Profile) async throws {
        guard let container,
              let store = try? ConfigResourceStore(containerURL: container) else {
            throw PipelineError.sourceUnavailable(
                "the shared configuration store is unavailable"
            )
        }
        let coordinator = try vpn.activationCoordinator(store: store, container: container)
        _ = try await coordinator.activate(
            profile: profile,
            sourceYAML: try storedSourceYAML(for: profile)
        )
        guard let activeYAML = try store.loadCurrent().text else { return }
         
         
         
         
        let preflight = await Task.detached(priority: .userInitiated) { () -> ([String], PreflightOutcome) in
            (
                (try? ConfigTransforms.planResources(mergedYAML: activeYAML).notices) ?? [],
                PreflightService.check(finalYAML: activeYAML, container: container)
            )
        }.value
        notices = preflight.0
        let outcome = preflight.1
        if let intentJSON = outcome.intentJSON,
           let intent = try? JSONDecoder().decode(
            PlatformConfigIntent.self,
            from: Data(intentJSON.utf8)
           ) {
            await vpn.applyActiveConfiguration(nextIntent: intent)
        }
    }

    private func recordBatchFailure(_ error: Error, profile: Profile) {
        let context: ConfigurationFailureContext = profile.id == activeProfileID
            ? .activation : .subscription
        guard let failure = ConfigurationFailureClassifier.classify(
            error,
            context: context,
            preservesLastKnownGood: true
        ) else { return }
        recordBatchItem(
            id: profile.id,
            label: profile.label,
            state: .failed,
            message: failure.message,
            failure: failure
        )
    }

    private func recordBatchItem(
        id: String,
        label: String,
        state: BatchUpdateState,
        message: String?,
        failure: ConfigurationFailure? = nil
    ) {
        guard var report = batchReport else { return }
        report.wasCancelled = false
        report.record(BatchUpdateItem(
            id: id,
            label: label,
            state: state,
            message: message,
            failure: failure
        ))
        batchReport = report
    }

    private func markBatchCancelled() {
        guard var report = batchReport else { return }
        report.wasCancelled = true
        batchReport = report
    }

    func previewText(for profile: Profile) -> String? {
         
         
         
         
         
        if let container,
           let revision = profile.activeRevision,
           let loaded = try? ConfigResourceStore(containerURL: container)
               .loadConfiguration(profileID: profile.id, revision: revision) {
            return loaded.text
        }
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        guard let source = try? hydratedSourceYAML(for: profile) else {
            return sidecarYAML(for: profile)
        }
         
         
         
        return try? ProfileRuntimeConfigBuilder.buildProduction(raw: source, profile: profile)
    }

     
     
     
    func loadSavedConfigurationPreview(
        for profileID: String,
        build: @escaping (String, Profile) throws -> String = {
            try ProfileRuntimeConfigBuilder.buildProduction(raw: $0, profile: $1)
        }
    ) async throws -> String {
        guard let profile = profiles.first(where: { $0.id == profileID }),
              let workingDir else {
            throw PipelineError.sourceUnavailable("The saved configuration is unavailable.")
        }
        return try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
             
             
            guard let source = Self.sidecarYAML(for: profile, workingDir: workingDir) else {
                throw PipelineError.sourceUnavailable("The saved configuration is unavailable.")
            }
            let text = try build(source, profile)
            try Task.checkCancellation()
            return text
        }.value
    }

     
     
    func loadAppliedConfigurationPreview(for profileID: String) async throws -> String? {
        guard let profile = profiles.first(where: { $0.id == profileID }),
              let container else { return nil }
        return try await Task.detached(priority: .userInitiated) {
            let store = try ConfigResourceStore(containerURL: container)
             
             
            let active = try store.activeIdentity()
            guard let revision = active?.profileID == profileID
                ? active?.revision : profile.activeRevision else { return nil }
            return try store
                .loadConfiguration(profileID: profileID, revision: revision).text
        }.value
    }

     
     
    func loadCachedPreviewText(for profileID: String) async -> String? {
        try? await loadSavedConfigurationPreview(for: profileID)
    }


     
     
    func loadCachedExportDocument(for profileID: String) async -> (String, String)? {
        guard let profile = profiles.first(where: { $0.id == profileID }) else { return nil }
        guard let text = capturedSourceText(for: profile) else { return nil }
        let name = profile.label.isEmpty ? "profile" : profile.label
        return ("\(name).yaml", text)
    }

     
     
    func exportDocument(for profile: Profile) -> (String, String)? {
        let name = profile.label.isEmpty ? "profile" : profile.label
        if let captured = capturedSourceText(for: profile) {
            return ("\(name).yaml", captured)
        }
        guard let text = previewText(for: profile) else { return nil }
        return ("\(name).yaml", text)
    }

    func subscriptionLink(for profile: Profile) -> String? {
        if case .url(let url) = profile.source { return url }
        return nil
    }

     
     
     
     
    private func forgetCachedSource(_ id: String? = nil) {
        if let id { sourceYAMLCache[id] = nil } else { sourceYAMLCache.removeAll() }
    }

    private func sidecarURL(for profile: Profile) -> URL? {
        workingDir?.appendingPathComponent("store/\(profile.id)/source.yaml")
    }

     
     
    func sourceLocation(for profile: Profile) -> URL? { sidecarURL(for: profile) }

     
     
    func loadSourceYAML(for profile: Profile) async -> String? {
        if let library = configurationLibraryStore,
           let raw = try? await Task.detached(operation: { () throws -> String? in
               guard let recipe = try library.snapshot().recipes.first(where: { $0.id == profile.id }),
                     recipe.preservesOriginal == true else { return nil }
               let payload = try library.payload(recipe.ruleSource)
               if let text = String(data: payload.original, encoding: .utf8),
                  (try? ConfigTransforms.validateSource(text)) != nil { return text }
               return try ConfigTransforms.jsonToYAML(payload.documentJSON)
           }).value { return raw }
        if let cached = sourceYAMLCache[profile.id] { return cached }
        guard let url = sidecarURL(for: profile) else { return sourceYAML(for: profile) }
        let value = await Task.detached(priority: .userInitiated) {
            try? String(contentsOf: url, encoding: .utf8)
        }.value
        sourceYAMLCache[profile.id] = value
        return value
    }

    func sourceYAML(for profile: Profile) -> String? {
         
         
         
         
        if let cached = sourceYAMLCache[profile.id] { return cached }
        let value = (try? hydratedSourceYAML(for: profile)) ?? sidecarYAML(for: profile)
        sourceYAMLCache[profile.id] = value
        return value
    }

     
     
     
     
     
     
     
     
     
     
    func capturedSourceText(for profile: Profile) -> String? {
        guard let workingDir else { return sourceYAML(for: profile) }
        return ProfileSourceStore.capturedText(
            workingDirectory: workingDir, profileID: profile.id
        ) ?? sourceYAML(for: profile)
    }

     
     
    func hasEditableSource(for profile: Profile) -> Bool {
        if let remembered = editableSourceCache[profile.id] { return remembered }
        guard let workingDir else { return false }
        let sidecar = workingDir.appendingPathComponent("store/\(profile.id)/source.yaml")
        editableSourceStatsForTesting += 1
        let exists = FileManager.default.fileExists(atPath: sidecar.path)
        editableSourceCache[profile.id] = exists
        return exists
    }

    func runtimeSourceYAML(for profile: Profile) -> String? {
        sidecarYAML(for: profile)
    }

     
     
     
     
     
     
     
    func udpFallbackGuardInput(for profile: Profile) async -> ConfigTransforms.UDPFallbackGuardInput? {
        guard let raw = runtimeSourceYAML(for: profile) else { return nil }
        return await Task.detached(priority: .userInitiated) {
            try? ProfileRuntimeConfigBuilder.udpFallbackGuardInput(raw: raw, profile: profile)
        }.value
    }

     
     
     
     
    private func sidecarYAML(for profile: Profile) -> String? {
        guard let workingDir else { return nil }
        let sidecar = workingDir.appendingPathComponent("store/\(profile.id)/source.yaml")
        return try? String(contentsOf: sidecar, encoding: .utf8)
    }

    private func cacheSourceYAML(_ yaml: String, for profile: Profile) throws {
        forgetCachedSource(profile.id)
        guard let workingDir else { throw PipelineError.sourceUnavailable(profile.label) }
        try sourceWriter(yaml, profile, workingDir)
        editableSourceCache.removeAll()
    }

     
     
     
     
     
     
    private static func writeSourceYAML(
        _ yaml: String,
        _ profile: Profile,
        _ workingDir: URL
    ) throws {
        let sidecar = workingDir.appendingPathComponent("store/\(profile.id)/source.yaml")
        try FileManager.default.createDirectory(
            at: sidecar.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(yaml.utf8).write(
            to: sidecar,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    private func restoreSourceYAML(_ yaml: String?, for profile: Profile) {
        guard let workingDir else { return }
        let sidecar = workingDir.appendingPathComponent("store/\(profile.id)/source.yaml")
        if let yaml {
            try? Self.writeSourceYAML(yaml, profile, workingDir)
        } else {
            try? FileManager.default.removeItem(at: sidecar)
            editableSourceCache.removeAll()
        }
    }

    private func externalResourceData(for profile: Profile) -> [String: Data] {
        guard let workingDir else { return [:] }
        return Self.externalResourceData(for: profile, workingDir: workingDir)
    }

     
     
    nonisolated private static func externalResourceData(
        for profile: Profile,
        workingDir: URL
    ) -> [String: Data] {
        Dictionary(uniqueKeysWithValues: (profile.externalResources ?? []).compactMap { reference in
            let url = workingDir.appendingPathComponent(
                "store/\(profile.id)/resources/\(reference.storageKey)"
            )
            return (try? Data(contentsOf: url)).map { (reference.storageKey, $0) }
        })
    }

     
    nonisolated private static func sidecarYAML(for profile: Profile, workingDir: URL) -> String? {
        let sidecar = workingDir.appendingPathComponent("store/\(profile.id)/source.yaml")
        return try? String(contentsOf: sidecar, encoding: .utf8)
    }

    private func hydratedSourceYAML(for profile: Profile) throws -> String {
        guard let yaml = sidecarYAML(for: profile) else {
            throw PipelineError.sourceUnavailable(
                "the saved source for this profile is unavailable"
            )
        }
         
        return yaml
    }

     
     
    nonisolated private static func duplicateResourceFiles(
        sourceYAML: String,
        profile: Profile,
        dataByKey: [String: Data]
    ) throws -> [ExternalResourceImportFile] {
        let json = try ConfigTransforms.yamlToJSON(sourceYAML)
        guard let root = try JSONSerialization.jsonObject(with: Data(json.utf8))
                as? [String: Any] else {
            throw ProfileExternalResourceError.invalidConfiguration
        }
        var filesByName: [String: Data] = [:]
        for requirement in IOSExternalResourceCatalog.requirements(root: root)
            where requirement.capability.confidentiality == .publicData {
            let sourceDigest = ProfileExternalResourceImporter.sha256(
                Data(requirement.rawValue.utf8)
            )
            guard let reference = (profile.externalResources ?? []).first(where: {
                $0.capabilityID == requirement.capability.id
                    && $0.proxy == requirement.proxyName
                    && $0.fieldPath == requirement.capability.fieldPath
                    && $0.sourceValueSHA256 == sourceDigest
            }), let data = dataByKey[reference.storageKey] else {
                throw ProfileExternalResourceError.storedResourceMissing(
                    field: requirement.capability.fieldPath.joined(separator: ".")
                )
            }
            let fileName = requirement.rawValue
                .replacingOccurrences(of: "\\", with: "/")
                .split(separator: "/")
                .last
                .map(String.init) ?? requirement.rawValue
            if let previous = filesByName[fileName.lowercased()], previous != data {
                throw ProfileExternalResourceError.ambiguousSelection(
                    field: requirement.capability.fieldPath.joined(separator: ".")
                )
            }
            filesByName[fileName.lowercased()] = data
        }
        return filesByName.keys.sorted().compactMap { name in
            filesByName[name].map { ExternalResourceImportFile(fileName: name, data: $0) }
        }
    }

    private func uniqueCopyLabel(base: String, suffix: String) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = (trimmed.isEmpty ? "Profile" : trimmed) + suffix
        let existing = Set(profiles.map { $0.label.localizedLowercase })
        if !existing.contains(root.localizedLowercase) { return root }
        var index = 2
        while existing.contains("\(root) \(index)".localizedLowercase) { index += 1 }
        return "\(root) \(index)"
    }

    private func safeProfileFileName(_ label: String) -> String {
        let unsafe = CharacterSet(charactersIn: "/\\:")
        let sanitized = label.components(separatedBy: unsafe).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stem = String((sanitized.isEmpty ? "Profile" : sanitized).prefix(80))
        return "\(stem).yaml"
    }

    private func externalResourceSource(_ source: Profile.Source) -> IOSExternalResourceSource {
        switch source {
        case .url: return .subscription
        case .file: return .localFile
        case .clipboard: return .clipboard
        }
    }

     

     
     
     
     
     
     
     
    func startActivation(
        _ profile: Profile,
        applyToTunnel: Bool = true,
        preferCachedSource: Bool = false,
        because reason: String = "unspecified"
    ) {
         
         
         
        HakoPerf.note(
            "activation.requested by=\(reason) applyToTunnel=\(applyToTunnel)"
        )


        let request = ActivationRequest(
            profile: profile,
            applyToTunnel: applyToTunnel,
            preferCachedSource: preferCachedSource
        )
        clearFailure()
        guard activationTask == nil else {
             
             
             
            pendingActivation = request
            return
        }
         
         
         
         
         
        guard busyProfileID == nil else {
            pendingActivation = request
            statusMessage = .format(
                "%@ will switch when the current update finishes.",
                [request.profile.label]
            )
            return
        }
        runActivation(request)
    }

    private func runActivation(_ request: ActivationRequest) {
        activationAppliesToTunnel = request.applyToTunnel
        isActivating = true
        activationTask = Task { [weak self] in
            guard let self else { return }
            await self.activate(
                request.profile,
                applyToTunnel: request.applyToTunnel,
                preferCachedSource: request.preferCachedSource
            )
            self.activationTask = nil
            if let pending = self.pendingActivation {
                self.pendingActivation = nil
                 
                 
                 
                self.runActivation(pending)
            } else {
                self.activationAppliesToTunnel = nil
                self.isActivating = false
            }
        }
    }

     
     
     
    private func drainPendingActivation() {
        guard activationTask == nil, busyProfileID == nil,
              let pending = pendingActivation else { return }
        pendingActivation = nil
        runActivation(pending)
    }

    func cancelActivation() {
        activationCancellationGeneration &+= 1
        pendingActivation = nil
        activationTask?.cancel()
    }

     
     
     
    func waitForPendingActivation() async {
        while let task = activationTask {
            await task.value
        }
    }

    var failureProfile: Profile? {
        guard let failedOperation else { return nil }
        let id: String
        switch failedOperation {
        case .sync(let profileID), .activation(let profileID): id = profileID
        }
        return profiles.first { $0.id == id }
    }

    func retryLastFailure() {
        guard let failedOperation,
              let profile = failureProfile else { return }
        switch failedOperation {
        case .sync:
            sync(profile)
        case .activation:
            startActivation(profile)
        }
    }

    private func activate(
        _ profile: Profile,
        applyToTunnel: Bool,
        preferCachedSource: Bool
    ) async {
        guard let container, busyProfileID == nil else { return }
        busyProfileID = profile.id
        statusMessage = .format("Preparing %@…", [profile.label])
        notices = []
        planErrors = []
        defer { busyProfileID = nil }
        var pipelineSucceeded = false
        do {
            let store = try ConfigResourceStore(containerURL: container)
            let coordinator = try vpn.activationCoordinator(store: store, container: container)
            let sourceYAML = try storedSourceYAML(
                for: profile,
                preferCachedSource: preferCachedSource
            )
             
             
             
             
             
             
             
            _ = try await Task.detached(priority: .userInitiated) {
                try await coordinator.activate(
                    profile: profile, sourceYAML: sourceYAML
                )
            }.value

            let activeYAML = try store.loadCurrent().text ?? ""
            statusMessage = .format("%@ staged; applying to tunnel…", [profile.label])
             
            let preflight = await Task.detached(priority: .userInitiated) { () -> ([String], PreflightOutcome) in
                (
                    (try? ConfigTransforms.planResources(mergedYAML: activeYAML).notices) ?? [],
                    PreflightService.check(finalYAML: activeYAML, container: container)
                )
            }.value
            notices = preflight.0
            let outcome = preflight.1
            if applyToTunnel,
               let intentJSON = outcome.intentJSON,
               let intent = try? JSONDecoder().decode(PlatformConfigIntent.self,
                                                      from: Data(intentJSON.utf8)) {
                await vpn.applyActiveConfiguration(nextIntent: intent)
            }
            statusMessage = applyToTunnel
                ? .format("%@ is active", [profile.label])
                : .format("%@ saved for the next connection", [profile.label])
            clearFailure()
            pipelineSucceeded = true
        } catch is CancellationError {
            statusMessage = "Update cancelled"
            clearFailure()
        } catch let PipelineError.planRejected(failures) {
            planErrors = failures.map { "\($0.field): \($0.reason)" }
            recordFailure(
                PipelineError.planRejected(failures),
                context: .activation,
                operation: .activation(profile.id)
            )
        } catch {
            recordFailure(
                error,
                context: .activation,
                operation: .activation(profile.id)
            )
        }
        load()
         
         
         
         
         
        if pipelineSucceeded, lastFailure == nil, activeProfileID != profile.id {
            recordFailure(
                PipelineError.activationReadback,
                context: .activation,
                operation: .activation(profile.id)
            )
        }
    }

    private func clearFailure() {
        lastFailure = nil
        failedOperation = nil
        planErrors = []
    }

     
     
     
     
     
     
     
     
    func dismissFailure() {
        clearFailure()
    }

    private func recordFailure(
        _ error: Error,
        context: ConfigurationFailureContext,
        operation: FailedOperation?,
        preservesLastKnownGood: Bool = true
    ) {
        guard let failure = ConfigurationFailureClassifier.classify(
            error,
            context: context,
            preservesLastKnownGood: preservesLastKnownGood
        ) else {
            clearFailure()
            return
        }
        lastFailure = failure
        failedOperation = operation
        statusMessage = .copy(failure.title)
    }

     
     
    private func storedSourceYAML(
        for profile: Profile,
        preferCachedSource: Bool = false
    ) throws -> String? {
        if case .url = profile.source,
           profile.usesLocalSourceOverride != true,
           !preferCachedSource {
            return nil
        }
        guard let workingDir else { throw PipelineError.sourceUnavailable(profile.label) }
        let sidecar = workingDir.appendingPathComponent("store/\(profile.id)/source.yaml")
        if preferCachedSource,
           case .url = profile.source,
           !FileManager.default.fileExists(atPath: sidecar.path) {
             
             
            return nil
        }
        guard let yaml = try? String(contentsOf: sidecar, encoding: .utf8) else {
            if case .url = profile.source {
                 
                 
                 
                return nil
            }
            throw PipelineError.sourceUnavailable(
                "original YAML for '\(profile.label)' is gone; re-add the profile")
        }
        return yaml
    }
}


 
struct ConfigTextDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.yaml, .plainText]

    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
