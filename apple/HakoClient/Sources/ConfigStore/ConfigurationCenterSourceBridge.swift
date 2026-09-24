import CryptoKit
import Foundation
import Hako
import HakoClientKit

 
 
enum ConfigurationCenterSourceBridge {
    static func fetch(url: String, label: String, credentials: CredentialStore, downloader: HTTPFetching = ResourceDownloader()) async throws -> ConfigurationSourcePayload {
        let id = UUID().uuidString
        let profile = Profile(id:id,label:label,source:.url(url),autoUpdate:true,
            updateIntervalHours:12,subscriptionInfo:nil,selectedMap:[:],override:OverrideSpec(),
            activeRevision:nil,order:0,lastUpdatedAt:nil)
         
         
        let manager = SubscriptionManager(downloader: downloader, credentials: credentials)
        guard let fetched = try await manager.fetch(profile:profile,useConditionalValidators:false) else {
            throw PipelineError.sourceUnavailable("The profile URL returned no YAML.")
        }
        let proposed = label.trimmingCharacters(in:.whitespacesAndNewlines)
        let resolvedLabel = proposed.isEmpty ? (fetched.suggestedName ?? URL(string:url)?.host ?? "Profile URL") : proposed
        return try await Task.detached(priority:.userInitiated) {
            var result = try ConfigurationCenterSourceBridge.payload(label:resolvedLabel,origin:.subscription(url),
                original:fetched.rawSource,yaml:fetched.yaml,id:id)
            result.record.updateIntervalHours = 24
            result.record.subscriptionUsage = fetched.subscriptionInfo.map(subscriptionUsage)
            return result
        }.value
    }

    static func subscriptionUsage(_ info: SubscriptionInfo) -> ConfigurationSubscriptionUsage {
        .init(upload: info.upload, download: info.download, total: info.total, expire: info.expire)
    }

     
     
    static func profileOrigin(recipe: ConfigurationRecipe, in snapshot: ConfigurationLibrarySnapshot) -> Profile.Source {
        guard recipe.sources.count == 1, let reference = recipe.sources.first,
              let record = snapshot.sources.first(where: { $0.id == reference.id }),
              case let .subscription(link) = record.origin, !link.isEmpty else { return .clipboard }
        return .url(link)
    }
    static func prepareReplacements(compositions: [String: ConfigurationComposition], planned: ConfigurationLibrarySnapshot,
                                    payloads: [ConfigurationSourcePayload], library: ConfigurationLibraryStore,
                                    originals: [Profile], workingDir: URL, container: URL, rename: String? = nil,
                                    coreGate: @Sendable (String, URL) throws -> Void) throws -> [ConfigurationCenterPublicationBridge.Replacement] {
            try compositions.keys.sorted().map { id -> ConfigurationCenterPublicationBridge.Replacement in
                guard let previous = originals.first(where: { $0.id == id }),
                      let recipe = planned.recipes.first(where: { $0.id == id }),
                      let composition = compositions[id] else { throw ConfigurationLibraryError.missingDependency(id) }
                let prior = try String(contentsOf: ProfileSourceStore.runnableURL(workingDirectory: workingDir,
                    profileID: id), encoding: .utf8)
                var next = previous
                 
                 
                 
                 
                 
                 
                 
                next.source = ConfigurationCenterSourceBridge.profileOrigin(recipe: recipe, in: planned)
                next.autoUpdate = false
                next.subscriptionInfo = nil
                if id == rename { next.label = recipe.label; next.labelIsUserAssigned = true }
                let files = try Set(recipe.dependencies).flatMap { reference in
                    let payload = try payloads.first(where: { ConfigurationSourceVersion($0.record) == reference })
                        ?? library.payload(reference)
                    return ConfigurationCenterSourceBridge.boundFiles(payload)
                }
                let yaml = try ConfigTransforms.jsonToYAML(composition.document.serialized())
                try ConfigTransforms.validateSource(yaml)
                let resources = try ProfileExternalResourceImporter.prepare(yaml: yaml, profileID: id,
                    source: .localFile, files: files, requiringAllFiles: false)
                next.externalResources = resources.references.isEmpty ? nil : resources.references
                let runtime = try ProfileRuntimeConfigBuilder.runtimePreview(raw: resources.yaml, profile: next)
                try ConfigurationCenterSourceBridge.withValidationResources(yaml: runtime, files: files,
                    directory: workingDir) { resolved in
                    do { try coreGate(resolved, container) }
                    catch { guard ProfilesViewModel.refusalBelongsToActivation(error.localizedDescription) else { throw error } }
                }
                return .init(previous: previous, profile: next, previousYAML: prior,
                    yaml: resources.yaml, resources: resources.publicResources)
            }
    }

     
     
     
     
     
    static func refreshDueSources(container: URL, now: Date,
                                  downloader: HTTPFetching = ResourceDownloader()) async -> BackgroundRefreshOutcome {
        var outcome = BackgroundRefreshOutcome()
        let working = container.appendingPathComponent("working")
        let directory = working.appendingPathComponent("configuration-library")
#if canImport(UIKit)
        let library = ConfigurationLibraryStore(directory: directory, beginAccess: ConfigStoreSuspensionShield.beginLibraryAccess)
#else
        let library = ConfigurationLibraryStore(directory: directory)
#endif
        do {
            try await MainActor.run {
                try ConfigurationCenterPublicationBridge.recoverReplacements(library: library, workingDir: working)
            }
            let initial = try await Task.detached {
                let profiles = ProfileStore(fileURL: working.appendingPathComponent("store/profiles.json"))
                try ConfigurationCenterPublicationBridge.reconcileDeletedProfiles(library: library, profileStore: profiles)
                return try library.snapshot()
            }.value
            let due = ConfigurationSourcesDueForRefresh.select(sources: initial.availableSources, now: now)
            let credentials = CredentialStore()
            for source in due {
                if Task.isCancelled { outcome.cancelled = true; return outcome }
                outcome.attempted += 1
                do {
                    let current = try await Task.detached { try library.snapshot() }.value
                    guard let latest = current.sources.first(where: { $0.id == source.id }), latest == source,
                          case .subscription(let url) = latest.origin else { outcome.unchanged += 1; continue }
                    let fetched = try await fetch(url: url, label: latest.label, credentials: credentials, downloader: downloader)
                    let prepared = try await Task.detached { () -> (PreparedConfigurationSourceUpdate, [ConfigurationCenterPublicationBridge.Replacement]) in
                        let previous = try library.payload(.init(latest))
                        var record = latest
                        record.version = fetched.record.version; record.updatedAt = fetched.record.updatedAt
                        record.nodeCount = fetched.record.nodeCount; record.providerCount = fetched.record.providerCount
                        record.groupCount = fetched.record.groupCount; record.ruleCount = fetched.record.ruleCount
                        record.subscriptionUsage = fetched.record.subscriptionUsage
                        let replacement = ConfigurationSourcePayload(record: record, original: fetched.original,
                            documentJSON: fetched.documentJSON, resourceFiles: previous.resourceFiles)
                        let plan = try library.prepareSourceUpdate(replacement, expectedGeneration: current.generation,
                            resolveInput: boundInput)
                        let originals = ProfileStore(fileURL: working.appendingPathComponent("store/profiles.json")).load()
                        let replacements = try prepareReplacements(compositions: plan.compositions, planned: plan.candidate,
                            payloads: plan.payloads, library: library, originals: originals, workingDir: working,
                            container: container, coreGate: { yaml, container in
#if os(macOS)
                                try AppCoreSetup.withConfiguration(container: container) {
                                    var error: NSError?
                                    guard HakoCheckConfig(yaml, &error) else { throw error ?? HakoCoreRefusal() }
                                }
#else
                                _ = try AppConfigurationPreflight.validate(yaml, container: container, fallbackCode: 2)
#endif
                            })
                        return (plan, replacements)
                    }.value
                    try Task.checkCancellation()
                     
                     
                     
                     
                     
                    let recomposedIDs = Set(prepared.0.compositions.keys)
                    try await MainActor.run {
                        try Task.checkCancellation()
                        try ConfigurationCenterPublicationBridge.replace(prepared.1, candidate: prepared.0.candidate,
                            payloads: prepared.0.payloads, library: library, workingDir: working, expectedGeneration: current.generation)
                    }
                    outcome.updated += 1
                     
                     
                     
                     
                     
                     
                    await restageInUseIfRecomposed(recomposedIDs, container: container, working: working,
                        credentials: credentials, downloader: downloader, now: now, outcome: &outcome)
                } catch { outcome.record(error) }
            }
        } catch { outcome.record(error) }
        if outcome.updated > 0 {
            await MainActor.run {
                NotificationCenter.default.post(name: .hakoConfigurationSourcesRefreshed, object: nil)
            }
        }
        return outcome
    }

     
     
     
     
    private static func restageInUseIfRecomposed(_ recomposedIDs: Set<String>, container: URL, working: URL,
                                                 credentials: CredentialStore, downloader: HTTPFetching,
                                                 now: Date, outcome: inout BackgroundRefreshOutcome) async {
        guard let store = try? ConfigResourceStore(containerURL: container),
              let active = try? store.activePointer(), recomposedIDs.contains(active.profileID) else { return }
        let profileStore = ProfileStore(fileURL: working.appendingPathComponent("store/profiles.json"))
        guard let profile = profileStore.load().first(where: { $0.id == active.profileID }),
              let document = try? String(contentsOf: ProfileSourceStore.runnableURL(workingDirectory: working,
                  profileID: active.profileID), encoding: .utf8) else { return }
        do {
            let coordinator = ProfileActivationCoordinator(
                store: store, profileStore: profileStore, credentials: credentials,
                downloader: downloader, coreHomeDir: working,
                compileRuleSets: false, activator: { _ in }, now: { now })
            _ = try await coordinator.activate(profile: profile, sourceYAML: document)
        } catch is CancellationError {
            outcome.cancelled = true
        } catch {
            outcome.record(error)
        }
    }

    static func payload(
        label: String, origin: ConfigurationSourceRecord.Origin,
        original: Data, yaml: String? = nil,
        resources: [ExternalResourceImportFile] = [],
        id: String = UUID().uuidString, version: String = UUID().uuidString
    ) throws -> ConfigurationSourcePayload {
        let yaml = try yaml ?? ProxyImportBridge.derivedSubscription(from:original).yaml
        try ConfigTransforms.validateSource(yaml)
        let json = try ConfigTransforms.yamlToJSON(yaml)
        let document = try OrderedJSON.parse(json)
        func count(_ key: String) -> Int {
            switch document.topLevelValue(key) {
            case .array(let values): return values.count
            case .object(let values): return values.count
            default: return 0
            }
        }
        var files: [String: Data] = [:]
        for resource in resources {
            if let existing = files[resource.fileName], existing != resource.data {
                throw ProfileExternalResourceError.ambiguousSelection(field:resource.fileName)
            }
            files[resource.fileName] = resource.data
        }
        var record = ConfigurationSourceRecord(id:id,label:label,origin:origin,version:version,
            nodeCount:count("proxies"),providerCount:count("proxy-providers"),
            groupCount:count("proxy-groups"),ruleCount:count("rules"), suppliesNodes: count("proxies") > 0 || count("proxy-providers") > 0)
        record.ruleProviderCount = count("rule-providers")
        let payload = ConfigurationSourcePayload(record:record,original:original,documentJSON:json,
            resourceFiles:files.isEmpty ? nil : files)
        _ = try boundInput(payload)  
        return payload
    }

    static func boundFiles(_ payload: ConfigurationSourcePayload) -> [ExternalResourceImportFile] {
        (payload.resourceFiles ?? [:]).map { name, data in
            .init(fileName:boundName(name,source:payload.record),data:data)
        }
    }

     
     
    static func withValidationResources<T>(
        yaml: String, files: [ExternalResourceImportFile], directory: URL,
        check: (String) throws -> T
    ) throws -> T {
         
         
         
        try BundledGeodataProvisioner.seedAllMissing(into: directory)
        var document = try OrderedJSON.parse(ConfigTransforms.yamlToJSON(yaml))
        guard let root = document.foundationValue as? [String: Any] else {
            throw ProfileExternalResourceError.invalidConfiguration
        }
        let requirements = IOSExternalResourceCatalog.requirements(root:root)
            .filter { $0.capability.confidentiality == .publicData }
        guard !requirements.isEmpty else { return try check(yaml) }
        let folder = directory.appendingPathComponent("configuration-validation-" + UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        for requirement in requirements {
            let name = URL(fileURLWithPath:requirement.rawValue).lastPathComponent
             
             
            guard let file = files.first(where: { $0.fileName == name }) else { continue }
            let destination = folder.appendingPathComponent(name)
            try file.data.write(to:destination,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
            document = try binding(document,requirement:requirement,path:destination.path)
        }
        return try check(ConfigTransforms.jsonToYAML(document.serialized()))
    }

    private static func binding(_ document: OrderedJSON, requirement: IOSExternalResourceRequirement,
                                path: String) throws -> OrderedJSON {
        switch requirement.capability.section {
        case .proxy:
            guard case .array(var nodes)? = document.topLevelValue("proxies"),
                  let index = nodes.firstIndex(where: { $0.topLevelValue("name") == .string(requirement.proxyName) }) else {
                throw ProfileExternalResourceError.invalidConfiguration
            }
            nodes[index] = nodes[index].setting(path:requirement.capability.fieldPath,to:.string(path))
            return document.settingTopLevel("proxies",to:.array(nodes))
        case .proxyProvider, .ruleProvider:
            let section = requirement.capability.section == .proxyProvider ? "proxy-providers" : "rule-providers"
            return document.setting(path:[section,requirement.proxyName] + requirement.capability.fieldPath,to:.string(path))
        }
    }

    static func boundInput(_ payload: ConfigurationSourcePayload) throws -> ConfigurationInput {
        let original = try OrderedJSON.parse(payload.documentJSON)
        let yaml = try ConfigTransforms.jsonToYAML(payload.documentJSON)
        let origin: IOSExternalResourceSource
        switch payload.record.origin {
        case .subscription: origin = .subscription
        case .file: origin = .localFile
        case .customNodes, .bundled: origin = .clipboard
        }
        let files = (payload.resourceFiles ?? [:]).map { ExternalResourceImportFile(fileName:$0.key,data:$0.value) }
        let prepared = try ProfileExternalResourceImporter.prepare(yaml:yaml,profileID:payload.record.id,
            source:origin,files:files,requiringAllFiles:false)
        var document = try OrderedJSON.parse(ConfigTransforms.yamlToJSON(prepared.yaml))
            .reorderingMappings(following:original)
        guard let root = document.foundationValue as? [String: Any] else {
            throw ProfileExternalResourceError.invalidConfiguration
        }
        var paths: [String: String] = [:]
        for requirement in IOSExternalResourceCatalog.requirements(root:root)
        where requirement.capability.confidentiality == .publicData {
            let basename = URL(fileURLWithPath:requirement.rawValue.replacingOccurrences(of:"\\",with:"/")).lastPathComponent
            let names = (payload.resourceFiles ?? [:]).keys.filter { $0.lowercased() == basename.lowercased() }
            paths[requirement.rawValue] = requirement.rawValue
            guard !names.isEmpty else { continue }
            guard names.count == 1, let name = names.first else {
                throw ProfileExternalResourceError.ambiguousSelection(field:requirement.capability.fieldPath.joined(separator:"."))
            }
            let bound = "./" + boundName(name,source:payload.record)
            paths[requirement.rawValue] = bound
            paths[bound] = bound
            document = try binding(document,requirement:requirement,path:bound)
        }
        return ConfigurationInput(id:payload.record.id,document:document,resourcePaths:paths,
            hiddenNodeNames: payload.record.nodeChain == nil ? [] : [ConfigurationNodeChain.entryName(for: payload.record.id)])
    }

    static func capturedFiles(profile: Profile, yaml: String, workingDir: URL) throws -> [ExternalResourceImportFile] {
        guard !(profile.externalResources ?? []).isEmpty else { return [] }
        let document = try OrderedJSON.parse(ConfigTransforms.yamlToJSON(yaml))
        guard let root = document.foundationValue as? [String: Any] else { throw ProfileExternalResourceError.invalidConfiguration }
        var files: [ExternalResourceImportFile] = []
        for requirement in IOSExternalResourceCatalog.requirements(root:root)
        where requirement.capability.confidentiality == .publicData {
            let reference = ProfileExternalResourceImporter.reference(profileID:profile.id,requirement:requirement)
            guard profile.externalResources?.contains(reference) == true else { continue }
            let file = workingDir.appendingPathComponent("store/\(profile.id)/resources/\(reference.storageKey)")
            let name = URL(fileURLWithPath:requirement.rawValue.replacingOccurrences(of:"\\",with:"/")).lastPathComponent
            files.append(.init(fileName:name,data:try Data(contentsOf:file)))
        }
        return files
    }

    private static func boundName(_ name: String, source: ConfigurationSourceRecord) -> String {
        let key = source.id + "\0" + source.version + "\0" + name
        let hash = SHA256.hash(data:Data(key.utf8)).map { String(format:"%02x",$0) }.joined()
        let suffix = URL(fileURLWithPath:name).pathExtension.lowercased()
        return "cc-" + hash + (suffix.isEmpty ? "" : "." + String(suffix.prefix(16)))
    }
}

 
 
 
enum ConfigurationLegacyRegistration {
    static func prepare(profile: Profile, snapshot: ConfigurationLibrarySnapshot,
                        load: () throws -> ConfigurationSourcePayload) throws
        -> (snapshot: ConfigurationLibrarySnapshot, payloads: [ConfigurationSourcePayload])? {
        guard profile.id != LocalDefaultProfileProvisioner.profileID,
              !(snapshot.registeredLegacyProfileIDs ?? []).contains(profile.id),
              !snapshot.recipes.contains(where: { $0.id == profile.id }) else { return nil }
        let sourceID = "legacy-" + profile.id
        var next = snapshot
        var payloads: [ConfigurationSourcePayload] = []
        let record: ConfigurationSourceRecord
        if let existing = snapshot.sources.first(where: { $0.id == sourceID }) {
            record = existing
        } else {
            var payload = try load()
            guard payload.record.id == sourceID else { throw ConfigurationLibraryError.invalidIdentifier }
            payload.record.registersSuppliedRules = true
            record = payload.record
            next.sources.append(record)
            payloads.append(payload)
        }
        if record.hasRules && !next.rules.contains(where: { $0.id == "rules-" + sourceID }) {
            next.rules.append(.init(id: "rules-" + sourceID, label: record.label, kind: .supplied, sourceID: sourceID))
        }
        next.registeredLegacyProfileIDs = (next.registeredLegacyProfileIDs ?? []) + [profile.id]
        return (next, payloads)
    }

     
     
    static func payload(profile: Profile, workingDir: URL) throws -> ConfigurationSourcePayload {
         
         
        guard !PlaintextSourceMigration.needsConversion(profile) else {
            throw PipelineError.sourceUnavailable(
                "A required credential is missing, invalid, or conflicts with the proxy identity.")
        }
        let yaml = try String(contentsOf: ProfileSourceStore.runnableURL(workingDirectory: workingDir,
            profileID: profile.id), encoding: .utf8)
        let origin: ConfigurationSourceRecord.Origin
        switch profile.source {
        case .url(let url): origin = .subscription(url)
        case .file(let file): origin = .file(file)
        case .clipboard: origin = .file(profile.label + ".yaml")
        }
        let original = Data((ProfileSourceStore.capturedText(workingDirectory: workingDir,
            profileID: profile.id) ?? yaml).utf8)
        let files = try ConfigurationCenterSourceBridge.capturedFiles(profile: profile, yaml: yaml, workingDir: workingDir)
        var payload = try ConfigurationCenterSourceBridge.payload(label: profile.label, origin: origin,
            original: original, yaml: yaml, resources: files, id: "legacy-" + profile.id)
        if case .subscription = origin {
            payload.record.updateIntervalHours = profile.autoUpdate ? profile.updateIntervalHours : nil
            payload.record.subscriptionUsage = profile.subscriptionInfo.map(ConfigurationCenterSourceBridge.subscriptionUsage)
        }
        return payload
    }

    static func customNodeSourceID(for profileID: String) -> String { "legacy-nodes-" + profileID }

     
     
     
     
     
     
     
     
     
    static func prepareCustomNodes(profile: Profile, snapshot: ConfigurationLibrarySnapshot,
                                   load: () throws -> ConfigurationSourcePayload?) throws
        -> (snapshot: ConfigurationLibrarySnapshot, payloads: [ConfigurationSourcePayload])? {
        guard !(snapshot.registeredLegacyNodeProfileIDs ?? []).contains(profile.id) else { return nil }
        let sourceID = customNodeSourceID(for: profile.id)
        var next = snapshot
        var payloads: [ConfigurationSourcePayload] = []
        if !snapshot.sources.contains(where: { $0.id == sourceID }) {
             
             
            guard let payload = try load() else { return nil }
            guard payload.record.id == sourceID, payload.record.origin == .customNodes else {
                throw ConfigurationLibraryError.invalidIdentifier
            }
            next.sources.append(payload.record)
            payloads.append(payload)
        }
        next.registeredLegacyNodeProfileIDs = (next.registeredLegacyNodeProfileIDs ?? []) + [profile.id]
        return (next, payloads)
    }

     
     
     
     
     
     
     
    static func customNodePayload(profile: Profile, workingDir: URL) throws -> ConfigurationSourcePayload? {
        guard let definition = profile.providerDefinitions?.proxyProviders
                .first(where: { $0.name == CustomNodePayload.providerName })?.definitionJSON else { return nil }
        guard !(try CustomNodePayload.payload(inDefinition: definition)).isEmpty,
              case .array(let nodes)? = try OrderedJSON.parse(definition).topLevelValue("payload") else { return nil }
        let yaml = try ConfigTransforms.jsonToYAML(OrderedJSON.object([(key: "proxies", value: .array(nodes))]).serialized())
        let files = try ConfigurationCenterSourceBridge.capturedFiles(profile: profile, yaml: yaml, workingDir: workingDir)
        return try ConfigurationCenterSourceBridge.payload(label: profile.label, origin: .customNodes,
            original: Data(yaml.utf8), yaml: yaml, resources: files, id: customNodeSourceID(for: profile.id))
    }
}

 
 
 
enum ConfigurationCollectionContentBridge {
    struct BatchResult {
        var updated = 0
        var failures: [String] = []
    }
    enum NodeUpdatePhase { case sources, collections }
    static func updateNodeLibrary(_ sources: [ConfigurationSourceRecord],
        updateSource: (ConfigurationSourceRecord) async throws -> Void,
        collections: () async throws -> [ConfigurationCollectionEntry],
        updateCollection: (ConfigurationCollectionEntry) async throws -> Void,
        progress: (NodeUpdatePhase, Int, Int, String) async -> Void) async -> BatchResult {
        var seen = Set<String>()
        let targets = sources.filter { source in
            guard source.suppliesNodes, source.isRetainedSnapshot != true,
                  case .subscription = source.origin else { return false }
            return seen.insert(source.id).inserted
        }
        var result = BatchResult()
        for (index, source) in targets.enumerated() {
            if Task.isCancelled { return result }
            await progress(.sources, index + 1, targets.count, source.label)
            do { try await updateSource(source); result.updated += 1 }
            catch is CancellationError { return result }
            catch { result.failures.append(source.label + ": " + error.localizedDescription) }
        }
        if Task.isCancelled { return result }
        do {
             
             
            let entries = try await collections()
            let downloaded = await updateCollections(entries, kind: .nodes, update: updateCollection,
                progress: { index, total, name in await progress(.collections, index, total, name) })
            result.updated += downloaded.updated
            result.failures += downloaded.failures
        } catch { result.failures.append(error.localizedDescription) }
        return result
    }
    static func updateRuleCollections(_ entries: [ConfigurationCollectionEntry],
        update: (ConfigurationCollectionEntry) async throws -> Void,
        progress: (Int, Int, String) async -> Void) async -> BatchResult {
        await updateCollections(entries, kind: .rules, update: update, progress: progress)
    }
    private static func updateCollections(_ entries: [ConfigurationCollectionEntry], kind: ConfigurationCollection.Kind,
        update: (ConfigurationCollectionEntry) async throws -> Void,
        progress: (Int, Int, String) async -> Void) async -> BatchResult {
        var seen = Set<ConfigurationCollection.ID>()
        let targets = entries.filter {
            $0.id.kind == kind && $0.collection.type == "http"
                && (kind != .nodes || $0.source.suppliesNodes)
                && $0.source.isRetainedSnapshot != true && seen.insert($0.id).inserted
        }
        var result = BatchResult()
        for (index, entry) in targets.enumerated() {
            if Task.isCancelled { break }
            await progress(index + 1, targets.count, entry.collection.name)
            do {
                try await update(entry)
                result.updated += 1
            } catch is CancellationError { break }
            catch { result.failures.append(entry.source.label + " / " + entry.collection.name + ": " + error.localizedDescription) }
        }
        return result
    }
    struct Page: Sendable {
        var nodes: [String] = []
        var lines: [String] = []
        var count: Int?
        var updatedAt: Date?
        var nextOffset: Int?
        var message: String?
        var subscriptionUsage: ConfigurationSubscriptionUsage?
    }
    static func catalog(_ library: ConfigurationLibraryStore, snapshot: ConfigurationLibrarySnapshot) throws -> [ConfigurationCollectionEntry] {
        try library.collectionCatalog(snapshot).map { entry in
            var result = entry
            if entry.collection.type == "inline" { return result }
            if entry.collection.type == "file", entry.id.kind == .nodes {
                let source = try library.payload(.init(entry.source))
                if let path = entry.collection.location,
                   let bytes = source.resourceFiles?[path] ?? source.resourceFiles?[URL(fileURLWithPath: path).lastPathComponent] {
                    result.memberCount = try? ProxyImportBridge.inspect(bytes, context: .nodeBundle).proxies.count
                }
                return result
            }
            let folder = directory(entry)
            if let data = try? Data(contentsOf: folder.appendingPathComponent("state.json")),
               let cache = try? JSONDecoder().decode(Cache.self, from: data), cache.count >= 0 {
                let filename = cache.payloadFile ?? "payload"
                if filename == URL(fileURLWithPath: filename).lastPathComponent, filename != ".", filename != "..",
                   FileManager.default.fileExists(atPath: folder.appendingPathComponent(filename).path) {
                    result.memberCount = cache.count
                    result.subscriptionUsage = cache.subscriptionUsage
                }
            }
            return result
        }
    }
    struct Cache: Codable { let count: Int; let updatedAt: Date; var payloadFile: String? = nil; var subscriptionUsage: ConfigurationSubscriptionUsage? = nil }
    static func directory(_ entry: ConfigurationCollectionEntry) -> URL {
        let key = entry.source.id + "\n" + entry.id.kind.rawValue + "\n" + entry.collection.name + "\n" + entry.collection.definition.serialized()
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("configuration-collections").appendingPathComponent(digest)
    }
     
     
     
    static func cachedNodeFiles(urlsByName: [String: String], workingDirectory: URL) -> [String: URL] {
        guard !urlsByName.isEmpty else { return [:] }
        let library = ConfigurationLibraryStore(directory: workingDirectory.appendingPathComponent("configuration-library"))
        guard let snapshot = try? library.snapshot(),
              let entries = try? library.collectionCatalog(snapshot) else { return [:] }
        let wanted = Set(urlsByName.values)
        var byURL: [String: (Date, URL)] = [:]
        for entry in entries where entry.id.kind == .nodes && entry.collection.type == "http" {
            guard let url = entry.collection.location, wanted.contains(url) else { continue }
            let folder = directory(entry)
            guard let state = try? Data(contentsOf: folder.appendingPathComponent("state.json")),
                  let cache = try? JSONDecoder().decode(Cache.self, from: state) else { continue }
            let filename = cache.payloadFile ?? "payload"
            guard filename == URL(fileURLWithPath: filename).lastPathComponent,
                  filename != ".", filename != ".." else { continue }
            let file = folder.appendingPathComponent(filename)
            guard FileManager.default.fileExists(atPath: file.path),
                  byURL[url].map({ $0.0 < cache.updatedAt }) ?? true else { continue }
            byURL[url] = (cache.updatedAt, file)
        }
        return urlsByName.compactMapValues { byURL[$0]?.1 }
    }

    static func cachedNodeFiles(yaml: String, workingDirectory: URL) -> [String: URL] {
        let definitions = ConfigTransforms.parsedRoot(forYAML: yaml)?.root["proxy-providers"] as? [String: [String: Any]] ?? [:]
        var urls = definitions.compactMapValues { value -> String? in
            guard value["type"] as? String == "http" else { return nil }
            return value["url"] as? String
        }
        var publishedFiles: [String: URL] = [:]
        for (name, definition) in definitions where definition["type"] as? String == "file" {
            guard let path = definition["path"] as? String else { continue }
            let file = URL(fileURLWithPath: path, relativeTo: workingDirectory).standardizedFileURL
            guard file.path.hasPrefix(workingDirectory.standardizedFileURL.path + "/"),
                  FileManager.default.fileExists(atPath: file.path) else { continue }
            publishedFiles[name] = file
             
             
            if let entry = ProviderCatalog.load(providersDir: file.deletingLastPathComponent())?.entries.first(where: {
                $0.kind == "proxy" && $0.name == name && $0.path == file.lastPathComponent
            }) { urls[name] = entry.url }
        }
        let files = publishedFiles.merging(cachedNodeFiles(urlsByName: urls, workingDirectory: workingDirectory)) { published, library in
            let publishedDate = (try? FileManager.default.attributesOfItem(atPath: published.path)[.modificationDate]) as? Date
            let libraryDate = (try? FileManager.default.attributesOfItem(atPath: library.path)[.modificationDate]) as? Date
            return (publishedDate ?? .distantPast) > (libraryDate ?? .distantPast) ? published : library
        }
        return files
    }

    static func page(_ entry: ConfigurationCollectionEntry, source: ConfigurationSourcePayload,
                     query: String, offset: Int = 0) throws -> Page {
        let collection = entry.collection
        let dir = directory(entry)
        let cache = try? JSONDecoder().decode(Cache.self, from: Data(contentsOf: dir.appendingPathComponent("state.json")))
        var result = Page(count: cache?.count ?? collection.inlineCount, updatedAt: cache?.updatedAt)
        let data: Data
        if collection.type == "inline" {
            let payload = collection.definition.topLevelValue("payload") ?? .array([])
            data = Data(OrderedJSON.object([(entry.id.kind == .nodes ? "proxies" : "payload", payload)]).serialized().utf8)
        } else if collection.type == "file" {
            guard let path = collection.location,
                  let value = source.resourceFiles?[path] ?? source.resourceFiles?[URL(fileURLWithPath: path).lastPathComponent] else {
                result.message = "缺少集合文件，请在来源中重新导入配套文件。"; return result
            }
            data = value
        } else {
            guard cache != nil, let bytes = try? Data(contentsOf: dir.appendingPathComponent(cache?.payloadFile ?? "payload"), options: .mappedIfSafe) else {
                result.message = entry.id.kind == .rules
                    ? "规则内容保存在链接中，点击“更新来源”下载并查看。"
                    : "节点内容保存在链接中，点击“更新来源”下载并查看。"
                return result
            }
            data = bytes
            result.subscriptionUsage = cache?.subscriptionUsage
        }
        if entry.id.kind == .nodes {
             
             
            let report = try ProxyImportBridge.inspect(data, context: .nodeBundle)
            let nodes = try report.proxies.map { value in
                String(decoding: try JSONSerialization.data(withJSONObject: value, options: .sortedKeys), as: UTF8.self)
            }
            result.count = nodes.count
            result.nodes = nodes.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
            if !report.issues.isEmpty { result.message = report.issues.map(\.message).joined(separator: "\n") }
            if ["filter", "exclude-filter", "exclude-type", "override"].contains(where: { collection.definition.topLevelValue($0) != nil }) {
                result.message = [result.message, "显示集合原始节点；筛选与覆写在运行时生效。"].compactMap { $0 }.joined(separator: "\n")
            }
        } else if collection.format == "mrs" {
            var count = 0; var error: NSError?
            guard HakoInspectProviderForIOS("rule", collection.behavior ?? "domain", "mrs", data, &count, &error) else {
                throw error ?? ConfigurationLibraryError.unreadable
            }
            result.count = count
            result.message = "MRS 格式，不提供逐条浏览。"
        } else if collection.type == "inline", case .array(let values) = collection.definition.topLevelValue("payload") {
            let lines = values.map { $0.foundationValue as? String ?? $0.serialized() }
                .filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
            result.count = values.count
            result.lines = Array(lines.dropFirst(offset).prefix(200))
            result.nextOffset = offset + result.lines.count < lines.count ? offset + result.lines.count : nil
        } else {
             
             
            var cursor = data.startIndex, skipped = 0
            while cursor < data.endIndex && result.lines.count <= 200 {
                let end = data[cursor...].firstIndex(of: 10) ?? data.endIndex
                let line = String(decoding: data[cursor..<end], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                cursor = end < data.endIndex ? end + 1 : data.endIndex
                if line.isEmpty || line.hasPrefix("#") || line == "payload:" { continue }
                if !query.isEmpty && !line.localizedCaseInsensitiveContains(query) { continue }
                if skipped < offset { skipped += 1; continue }
                result.lines.append(line)
            }
            if result.lines.count > 200 { result.lines.removeLast(); result.nextOffset = offset + 200 }
        }
        return result
    }
    static func refresh(_ entry: ConfigurationCollectionEntry, source: ConfigurationSourcePayload, downloader: HTTPFetching = ResourceDownloader()) async throws {
        guard entry.collection.type == "http" else { return }
        let definition = try entry.collection.browserDownloadDefinition()
        let root = OrderedJSON.object([(entry.id.kind.rawValue, .object([(entry.collection.name, definition)]))])
        let plan = try ConfigTransforms.planResources(mergedYAML: root.serialized())
        let kind = entry.id.kind == .nodes ? "proxy" : "rule"
        guard let provider = plan.providers.first(where: { $0.name == entry.collection.name && $0.kind == kind }) else {
            throw ConfigurationLibraryError.unreadable
        }
         
        let directory = directory(entry)
        let stage = directory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: stage) }
        let result = try await ProviderMaterializer(downloader: downloader, credentials: CredentialStore())
            .materializeDetailed(plan: .init(providers: [provider]), into: stage, publishedProvidersDir: stage,
                maxBytesEach: 32 * 1024 * 1024, forceRefresh: [provider.name],
                ageSecretKeys: try ConfigTransforms.providerAgeSecretKeys(mergedYAML: root.serialized()))
        if let warning = result.validationWarnings.first { throw NSError(domain: "Collection", code: 1, userInfo: [NSLocalizedDescriptionKey: warning.reason]) }
        guard result.firstLoadPending.isEmpty, let path = result.readPaths[provider.name] else { throw ConfigurationLibraryError.unreadable }
        let bytes = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
        if entry.id.kind == .nodes { _ = try ProxyImportBridge.inspect(bytes, context: .nodeBundle) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = UUID().uuidString + ".payload"
        try bytes.write(to: directory.appendingPathComponent(file), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try JSONEncoder().encode(Cache(count: result.entryCounts[provider.name] ?? 0, updatedAt: Date(), payloadFile: file,
            subscriptionUsage: entry.id.kind == .nodes ? result.subscriptionUserInfo[provider.name]
                .flatMap { SubscriptionInfo.parse(header: $0) }.map(ConfigurationCenterSourceBridge.subscriptionUsage) : nil))
            .write(to: directory.appendingPathComponent("state.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
