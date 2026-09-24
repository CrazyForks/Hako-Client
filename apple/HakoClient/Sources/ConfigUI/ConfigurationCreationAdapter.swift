import HakoClientKit
import HakoClientUI
import SwiftUI
import UniformTypeIdentifiers

 
 
struct ConfigurationCreationAdapter: View {
    @Environment(\.hakoShellLayout) private var shellLayout
    @ObservedObject var model: ProfilesViewModel
     
     
     
     
     
    var changed: ((ConfigurationLibrarySnapshot) -> Void)? = nil
    var editingProfileID: String? = nil
    var editingStep: ConfigurationCreationDraft.Step? = nil
    @State private var draft = ConfigurationCreationDraft()
    @State private var library = ConfigurationLibrarySnapshot()
    @State private var baseline = ConfigurationCreationDraft()
    @State private var inspectedSourceID: String?
    @State private var creationID = UUID().uuidString.lowercased()
    @State private var legacyPayloads: [String: ConfigurationSourcePayload] = [:]
    @State private var ready = false
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var importKind: HakoConfigurationSourceKind?
    @State private var firstStepImportKind: HakoConfigurationSourceKind?
     
    @State private var importsOriginal = false
    @State private var showsSourceLibrary = false
    @State private var showsRuleLibrary = false
    @State private var dismiss = HakoDismissHandle()
    @Environment(\.hakoProductModalDismiss) private var productModalDismiss

    var body: some View {
        HakoFeatureNavigationContainer {
            creationContent
            .hakoCapturesDismiss(dismiss)
            .task { await loadLibrary() }
            .hakoProductModal(isPresented: Binding(get: { inspectedSourceID != nil },
                set: { if !$0 { inspectedSourceID = nil } }), role: .page) {
                if let id = inspectedSourceID, let source = draft.sources(in: library).first(where: { $0.id == id }) {
                    ConfigurationNodeScopeAdapter(model: model, source: source,
                        staged: draft.newSources.first { $0.record.id == id }, initial: draft.nodeScopes?[id],
                        save: { scope in
                            var scopes = draft.nodeScopes ?? [:]
                            scopes[id] = scope?.isEmpty == true ? nil : scope
                            draft.nodeScopes = scopes.isEmpty ? nil : scopes
                            if scope?.isEmpty == true { draft.selectedSourceIDs.removeAll { $0 == id } }
                            else if !draft.selectedSourceIDs.contains(id) { draft.selectedSourceIDs.append(id) }
                            inspectedSourceID = nil
                        }, close: { inspectedSourceID = nil })
                }
            }
            .hakoProductModal(item: $importKind, role: .page) { kind in
                ConfigurationSourceImportAdapter(model: model, kind: kind, choosesKind: true,
                    finishImport: { importKind = nil }) { payload in
                        try Self.acceptImportedSource(payload, into: &draft, isEditing: editingProfileID != nil)
                    }
            }
            .hakoProductModal(isPresented: $showsSourceLibrary, role: .page) {
                ConfigurationSourceLibraryAdapter(model: model, library: library,
                    changed: applyLibrary, close: { showsSourceLibrary = false })
            }
            .hakoProductModal(isPresented: $showsRuleLibrary, role: .page) {
                ConfigurationRuleLibraryAdapter(model: model, library: library,
                    changed: applyLibrary, close: { showsRuleLibrary = false })
            }
        }
    }

    @ViewBuilder
    private var creationContent: some View {
        if ready && (firstStepImportKind != nil || draft.needsInitialNodeImport(in: library,
            hasLegacyNodes: legacyPayloads.values.contains { $0.record.nodeCount > 0 || $0.record.providerCount > 0 },
            isEditing: editingProfileID != nil)) {
             
             
            ConfigurationSourceImportAdapter(model: model, kind: firstStepImportKind ?? .subscription, choosesKind: true,
                isFirstConfigurationStep: true, finishImport: {
                    if firstStepImportKind != nil { firstStepImportKind = nil }
                    else { close() }
                }) { payload in
                     
                     
                     
                     
                    if importsOriginal { draft.useOriginal(payload) }
                    else { try Self.acceptImportedSource(payload, into: &draft, isEditing: false) }
                    importsOriginal = false
                    firstStepImportKind = nil
                }
        } else {
            HakoConfigurationCreationView(draft:$draft,library:library,
                palette: .hakoProduct, presentationClass: shellLayout == .regularSidebar ? .regularTouch : .compactTouch,
                icon: { AnyView(HakoSymbolImage(symbol: $0)) },
                legacy: model.profiles.compactMap { profile in
                    guard let payload = legacyPayloads[profile.id] else { return nil }
                    return .init(id: profile.id, label: profile.label, nodeCount: payload.record.nodeCount,
                        providerCount: payload.record.providerCount)
                },
                isBusy:busy,isReady:ready,error:errorMessage,
                reload: { Task { await loadLibrary() } },
                addSource: { kind in
                    if editingProfileID == nil { firstStepImportKind = kind }
                    else { importKind = kind }
                },
                selectLegacy: { id in
                    if let payload = legacyPayloads[id] { accept(payload) }
                },
                importWholeConfiguration: {
                    importsOriginal = true
                    firstStepImportKind = .subscription
                },
                finish:finish,
                cancel:close, isEditing: editingProfileID != nil, baseline: baseline, editingStep: editingStep,
                sourceDetails: { inspectedSourceID = $0 },
                manageSources: { showsSourceLibrary = true },
                manageRules: { showsRuleLibrary = true },
                completionNodes: { value in AnyView(completionContents(draft: value, nodes: true)) },
                completionRules: { value in AnyView(completionContents(draft: value, nodes: false)) })
        }
    }

    private func completionContents(draft: ConfigurationCreationDraft, nodes: Bool) -> some View {
        ConfigurationCompletionContentsAdapter(draft: draft, library: model.configurationLibraryStore,
            generation: library.generation, nodes: nodes)
    }

    private func loadLibrary() async {
        guard !ready, !busy else { return }
        errorMessage = nil
        busy = true
        defer { busy = false }
        do {
            try await model.recoverConfigurationPublications()
            do { try await model.registerLegacyConfigurationSources() }
            catch { errorMessage = error.localizedDescription }
            guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            library = try await Task.detached { try store.snapshot() }.value
            if editingProfileID == nil, draft.selectedRuleID == nil {
                draft.selectedRuleID = ConfigurationBuiltins.basicRuleID
            }
            if let id = editingProfileID {
                if let recipe = library.recipes.first(where: { $0.id == id }) {
                    let fallbackRule = library.rules.contains { $0.id == recipe.ruleSchemeID } || ConfigurationBuiltins.schemes.contains { $0.id == recipe.ruleSchemeID }
                    draft = Self.editingDraft(recipe: recipe, label: model.profiles.first(where: { $0.id == id })?.label ?? recipe.label,
                        selectedRuleID: fallbackRule ? recipe.ruleSchemeID : ConfigurationBuiltins.basicRuleID)
                } else {
                     
                     
                    let source = try await model.configurationSourceFromLegacy(id)
                    accept(source)
                    draft.selectedRuleID = source.record.hasRules ? "rules-" + source.record.id : ConfigurationBuiltins.basicRuleID
                    draft.label = source.record.label
                    draft.dnsMode = .source
                }
                draft.connectAfterCreation = false
                draft.step = editingStep ?? .sources
            }
             
             
             
            legacyPayloads = try await model.configurationLegacyNodeSources(in: library)
             
             
            baseline = draft
            ready = true
        } catch { errorMessage = error.localizedDescription }
    }

    private func applyLibrary(_ updated: ConfigurationLibrarySnapshot) {
        let removedSources = Set(library.sources.map(\.id)).subtracting(updated.sources.map(\.id))
        let removedRules = Set(library.rules.map(\.id)).subtracting(updated.rules.map(\.id))
        draft.selectedSourceIDs.removeAll { removedSources.contains($0) }
        baseline.selectedSourceIDs.removeAll { removedSources.contains($0) }
        if let selected = draft.selectedRuleID, removedRules.contains(selected) { draft.selectedRuleID = ConfigurationBuiltins.basicRuleID }
        if let selected = baseline.selectedRuleID, removedRules.contains(selected) { baseline.selectedRuleID = ConfigurationBuiltins.basicRuleID }
        library = updated
    }

     
     
    static func acceptImportedSource(_ payload: ConfigurationSourcePayload,
                                     into draft: inout ConfigurationCreationDraft, isEditing: Bool) throws {
        if isEditing { draft.add(payload, rule: nil) }
        else { try draft.acceptInitialNodeImport(payload) }
    }

    private func accept(_ payload: ConfigurationSourcePayload) {
        let hasRules = payload.record.hasRules && payload.record.registersSuppliedRules != false
        let rule: ConfigurationRuleScheme? = hasRules
            ? .init(id:"rules-" + payload.record.id,label:payload.record.label,kind:.supplied,sourceID:payload.record.id) : nil
        draft.add(payload,rule:rule)
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true; errorMessage = nil
        Task {
            defer { busy = false }
            do { try await operation() }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func finish(_ completion: @escaping (Bool) -> Void) {
        guard ready, !busy else { completion(false); return }
        busy = true; errorMessage = nil
        var candidate = draft
        candidate.connectAfterCreation = false
        Task {
            defer { busy = false }
            do {
                if let id = editingProfileID {
                    try await model.editConfiguration(candidate, id: id, generation: library.generation)
                } else {
                    _ = try await model.createConfiguration(candidate,generation:library.generation,id:creationID)
                }
                 
                 
                 
                 
                baseline = draft
                if let changed, let store = model.configurationLibraryStore,
                   let saved = try? await Task.detached(operation: { try store.snapshot() }).value {
                    changed(saved)
                }
                completion(true)
                close()
            } catch { errorMessage = error.localizedDescription; completion(false) }
        }
    }

    private func close() { (productModalDismiss ?? { dismiss() })() }
}

struct ConfigurationNodeSourceAdapter: View {
    var editorState: CustomNodesEditorState? = nil
    var isFirstConfigurationStep = false
    var tabHeader: ((Bool) -> AnyView)? = nil
    let accept: (ConfigurationSourcePayload) async throws -> Void
    @State private var profile = Profile(id: UUID().uuidString.lowercased(), label: "Custom Nodes",
        source: .clipboard, autoUpdate: false, updateIntervalHours: 12,
        subscriptionInfo: nil, selectedMap: [:], activeRevision: nil, order: 0, lastUpdatedAt: nil)
    @State private var dismiss = HakoDismissHandle()
    @Environment(\.hakoProductModalDismiss) private var productModalDismiss

    private let emptyNodeDocument = "proxies: []\n"
    var body: some View {
        CustomNodesView(profile: profile, sourceYAML: emptyNodeDocument,
            tabHeader: tabHeader, editorState: editorState,
            loadDraft: { try ProfileProviderDefinitionsDraft(profile: profile, baselineYAML: emptyNodeDocument) },
            saveDraft: { _ in throw ConfigurationLibraryError.unreadable },
            savePayloadAsync: { definition in
                let payload = try await Task.detached {
                    let nodes = try CustomNodePayload.payload(inDefinition: definition)
                    guard !nodes.isEmpty else { throw CustomNodeAppendError.missingName }
                    let document = try JSONSerialization.data(withJSONObject: ["proxies": nodes])
                    let yaml = try ConfigTransforms.jsonToYAML(String(decoding: document, as: UTF8.self))
                    return try ConfigurationCenterSourceBridge.payload(
                        label: nodes.count == 1 ? (nodes[0]["name"] as? String ?? "Custom Nodes") : "Custom Nodes",
                        origin: .customNodes, original: Data(yaml.utf8), yaml: yaml)
                }.value
                try await accept(payload)
            },
            onSaved: { if !isFirstConfigurationStep { (productModalDismiss ?? { dismiss() })() } },
            libraryDraft: true, isFirstConfigurationStep: isFirstConfigurationStep,
            renameNode: { _, _ in })
        .hakoProductModalRoot(title: isFirstConfigurationStep ? "Create Nodes 1/2" : HakoConfigurationAddition.nodes.title)
        .hakoCapturesDismiss(dismiss)
    }
}

 
 
private struct ConfigurationSourceDetailAdapter: View {
    @Environment(\.locale) private var locale
    @ObservedObject var model: ProfilesViewModel
    let source: ConfigurationSourceRecord
    let library: ConfigurationLibrarySnapshot
    let changed: (ConfigurationLibrarySnapshot) -> Void
    let close: () -> Void
    @State private var busy = false
    @State private var updating = false
    @State private var updateStatus: String?
    @State private var errorMessage: String?
    @State private var confirmsRuleReplacement = false
    @State private var showsNodeSource = false

    var body: some View {
        HakoFeatureNavigationContainer {
            HakoConfigurationSourceDetailView(source: source,
                configurations: library.recipes.filter { $0.sources.contains(where: { $0.id == source.id }) || $0.ruleSource.id == source.id }.map(\.label),
                isBusy: busy, error: errorMessage ?? updateIssueMessage(library, sourceID: source.id, locale: locale),
                isUpdating: updating, updateStatus: updateStatus, update: { refreshSource() }, save: { name, settings, completion in
                    perform(completion: completion) {
                        if let settings {
                            changed(try await model.saveConfigurationSourceSettings(source.id, draft: settings,
                                label: name, generation: library.generation))
                        } else {
                            changed(try await model.renameConfigurationSource(source.id, label: name, generation: library.generation))
                        }
                    }
                }, close: close, deleteSource: {
                    perform {
                        changed(try await model.deleteConfigurationSource(source.id, generation: library.generation))
                        close()
                    }
                }, editSource: { showsNodeSource = true })
                .hakoProductModal(isPresented: $showsNodeSource, role: .page) {
                    ConfigurationNodeSourceEditor(model: model, record: source, changed: changed)
                }
                .confirmationDialog("Update Conflict", isPresented: $confirmsRuleReplacement, titleVisibility: .visible) {
                    Button("Use Profile URL Rules", role: .destructive) {
                        refreshSource(replacingRules: true)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("Your rule edits conflict with this update. Use the profile URL rules to replace your edits, or cancel to keep the current profile. You can copy your rule scheme before updating.") }
        }
    }
    private func refreshSource(replacingRules: Bool = false) {
        guard !busy else { return }
        updating = true; updateStatus = nil
        perform(completion: { succeeded in
            updating = false
            if succeeded { updateStatus = HakoCopy.string("Sources updated", locale: locale) + ": 1" }
        }) {
            try await model.refreshConfigurationSource(source.id, replaceEditedRules: replacingRules,
                expectedVersion: replacingRules ? source.version : nil)
            guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            changed(try await Task.detached { try store.snapshot() }.value)
        }
    }
    private func perform(completion: @escaping (Bool) -> Void = { _ in },
                         _ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { completion(false); return }
        busy = true; errorMessage = nil
        Task {
            defer { busy = false }
            do { try await operation(); completion(true) }
            catch {
                errorMessage = HakoConfigurationUpdateCopy.message(error, locale: locale)
                if error is ConfigurationRuleReplay.Conflict { confirmsRuleReplacement = true }
                completion(false)
            }
        }
    }
}

 
 
struct ConfigurationSourceImportAdapter: View {
    @ObservedObject var model: ProfilesViewModel
    let kind: HakoConfigurationSourceKind
    var purpose: AddProfilePurpose = .source
    var choosesKind = false
    var isFirstConfigurationStep = false
    var externalTabHeader: ((Bool) -> AnyView)? = nil
    var importRuleCollection: (() -> Void)? = nil
    @State private var chosenKind: HakoConfigurationSourceKind?
    @State private var pendingKind: HakoConfigurationSourceKind?
    @State private var confirmsTabDiscard = false
    var finishImport: (() -> Void)? = nil
    let accept: (ConfigurationSourcePayload) async throws -> Void
    @State private var registerRules = false
    @State private var showsChainForm = false
    @StateObject private var nodeDraft = CustomNodesEditorState()
    @StateObject private var chainDraft = ConfigurationChainEditorDraft()
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var dismiss = HakoDismissHandle()
    @Environment(\.hakoProductModalDismiss) private var productModalDismiss

    private var activeKind: HakoConfigurationSourceKind { chosenKind ?? kind }
    var body: some View {
        Group {
            if activeKind == .customNodes {
                if showsChainForm {
                    ConfigurationChainEditor(model: model, existing: nil, draft: chainDraft,
                        tabHeader: { AnyView(VStack(spacing: 10) {
                            if choosesKind { kindTabs(dirty: chainDraft.isDirty) }
                            nodeKindTabs
                        }) }, isFirstConfigurationStep: isFirstConfigurationStep,
                        accept: accept, close: close, onSaved: isFirstConfigurationStep ? {} : nil)
                } else {
                    ConfigurationNodeSourceAdapter(editorState: nodeDraft, isFirstConfigurationStep: isFirstConfigurationStep, tabHeader: { dirty in
                        AnyView(VStack(spacing: 10) {
                            if choosesKind { kindTabs(dirty: dirty) }
                            nodeKindTabs
                        })
                    }, accept: accept)
                    .environment(\.hakoProductModalDismiss, close)
                }
            } else {
                AddProfileView(initialTab: activeKind == .file ? .file : .link, purpose: purpose, dismissAfterSave: purpose != .source,
                    availableTabs: choosesKind ? [.link, .file] : [.link, .file, .blank],
                    tabHeader: externalTabHeader ?? (choosesKind ? { dirty in AnyView(kindTabs(dirty: dirty)) } : nil),
                    sourceKind: (choosesKind || externalTabHeader != nil) ? activeKind : nil,
                    blankFileEntry: choosesKind, isFirstConfigurationStep: isFirstConfigurationStep,
                    registerSuppliedRules: nil, importRuleCollection: importRuleCollection,
                    createEmpty: {}, saveAsync: { label, source, raw, resources in
                        var payload: ConfigurationSourcePayload
                        switch source {
                        case .url(let url): payload = try await model.fetchConfigurationSource(url: url, label: label)
                        case .file(let file):
                            guard let raw else { throw ConfigurationLibraryError.unreadable }
                            payload = try await Task.detached {
                                try ConfigurationCenterSourceBridge.payload(label: label.isEmpty ? file : label,
                                    origin: .file(file), original: Data(raw.utf8), yaml: raw, resources: resources)
                            }.value
                        case .clipboard:
                            guard let raw else { throw ConfigurationLibraryError.unreadable }
                            payload = try await Task.detached {
                                try ConfigurationCenterSourceBridge.payload(label: label.isEmpty ? "Configuration" : label,
                                    origin: .file("Configuration.yaml"), original: Data(raw.utf8), yaml: raw, resources: resources)
                            }.value
                        }
                        try await Self.completeImport(payload, purpose: purpose,
                            isFirstConfigurationStep: isFirstConfigurationStep, accept: accept, close: close)
                    }, save: { _, _, _, _ in })
                .environment(\.hakoProductModalDismiss, close)
            }
        }
        .hakoCapturesDismiss(dismiss)
        .alert("Import Failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(verbatim: errorMessage ?? "") }
    }
     
     
    @MainActor
    static func completeImport(_ payload: ConfigurationSourcePayload, purpose: AddProfilePurpose,
                               isFirstConfigurationStep: Bool,
                               accept: (ConfigurationSourcePayload) async throws -> Void,
                               close: () -> Void) async throws {
        var value = payload
        if purpose == .source {
            guard value.record.suppliesNodes,
                  value.record.nodeCount > 0 || value.record.providerCount > 0 else {
                throw ConfigurationLibraryError.missingNodes
            }
            value.record.registersSuppliedRules = false
        }
        try await accept(value)
        if purpose == .source && !isFirstConfigurationStep { close() }
    }

    private var nodeKindTabs: some View {
        Picker(HakoCopy.key("Type"), selection: $showsChainForm) {
            Text(HakoCopy.key("Node")).tag(false)
            Text(HakoCopy.key("Proxy Chain")).tag(true)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("configuration.source.import.kind")
        .labelsHidden()
        .padding(.horizontal, 18)
        .padding(.bottom, 2)
        .accessibilityIdentifier("configuration.source.nodeKind")
    }
    private func kindTabs(dirty: Bool) -> some View {
        Picker(HakoCopy.key("Type"), selection: Binding(get: { activeKind }, set: { next in
            guard next != activeKind else { return }
            if (dirty || chainDraft.isDirty || !nodeDraft.customRows.isEmpty) && (activeKind == .customNodes || next == .customNodes) {
                pendingKind = next
                confirmsTabDiscard = true
            } else { chosenKind = next }
        })) {
            Text(HakoCopy.key("URL")).tag(HakoConfigurationSourceKind.subscription)
            Text(HakoCopy.key("File")).tag(HakoConfigurationSourceKind.file)
            Text(HakoCopy.key("Manual")).tag(HakoConfigurationSourceKind.customNodes)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("configuration.source.import.kind")
        .labelsHidden()
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 2)
        .alert("Discard Changes?", isPresented: $confirmsTabDiscard) {
            Button("Discard Changes", role: .destructive) {
                nodeDraft.customRows = nodeDraft.openedWith
                nodeDraft.pendingRenames = []
                chainDraft.name = ""; chainDraft.entry = nil; chainDraft.exit = nil
                chosenKind = pendingKind
                pendingKind = nil
            }
            Button("Keep Editing", role: .cancel) { pendingKind = nil }
        } message: { Text("Switching tabs discards what you have not saved.") }
    }
    private func close() { (finishImport ?? productModalDismiss ?? { dismiss() })() }
}

 
 
struct ConfigurationLibraryBrowseCache {
    let generation: UInt64
    let entries: [ConfigurationCollectionEntry]
    func matches(_ snapshot: ConfigurationLibrarySnapshot) -> Bool { generation == snapshot.generation }
}

 
struct ConfigurationSourceLibraryAdapter: View {
    @Environment(\.locale) private var locale
    @ObservedObject var model: ProfilesViewModel
    @State var library: ConfigurationLibrarySnapshot
    let changed: (ConfigurationLibrarySnapshot) -> Void
    let close: () -> Void
    var embedded = false
    var showsClose = true
    var browseCache: Binding<ConfigurationLibraryBrowseCache?>? = nil
    @State private var ready = false
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var updateProgress: String?
    @State private var importKind: HakoConfigurationSourceKind?
    @State private var inspectedSourceID: String?
    @State private var showsManagement = false
    @State private var collections: [ConfigurationCollectionEntry] = []
    @State private var inspectedCollection: ConfigurationCollectionEntry?

    var body: some View {
        ConfigurationLibraryNavigation(embedded: embedded) {
            HakoConfigurationSourceLibraryView(library: library, palette: .hakoProduct, isReady: ready || library.generation > 0 || browseCache?.wrappedValue != nil, isBusy: busy, error: errorMessage ?? updateIssueMessage(library, locale: locale),
                add: { importKind = $0 }, open: { showsManagement = false; inspectedSourceID = $0 },
                reload: { Task { await reload() } }, close: close, updateAll: updateAll, status: statusMessage, updateProgress: updateProgress, isCenterSection: embedded, showsClose: showsClose,
                collections: visibleCollections, openCollection: { inspectedCollection = $0 })
            .task(id: library.generation) {
                if !ready {
                    if browseCache?.wrappedValue != nil || library.generation > 0 { ready = true }
                    else { await reload() }
                }
                await loadCollections()
            }
            .onChange(of: inspectedCollection == nil) { closed in
                if closed { Task { await loadCollections(force: true) } }
            }
            .hakoProductModal(item: $inspectedCollection, role: .page) { entry in
                ConfigurationCollectionAdapter(model: model, entry: entry, changed: { library = $0; changed($0) }, close: { inspectedCollection = nil })
            }
            .hakoProductModal(item: $importKind, role: .page) { kind in
                ConfigurationSourceImportAdapter(model: model, kind: kind, choosesKind: true) { payload in
                    let updated = try await model.addConfigurationSource(payload, generation: library.generation)
                    library = updated; changed(updated)
                }
            }
            .hakoProductModal(isPresented: Binding(get: { inspectedSourceID != nil },
                set: { if !$0 { inspectedSourceID = nil } }), role: .page) {
                if let id = inspectedSourceID, let source = library.sources.first(where: { $0.id == id }) {
                    Group {
                        if source.nodeChain != nil {
                            ConfigurationChainDetail(model: model, source: source,
                                changed: { updated in library = updated; changed(updated) },
                                close: { inspectedSourceID = nil })
                        } else {
                            ConfigurationDocumentBrowserAdapter(model: model, sourceID: source.id, title: source.label, kind: .nodes, embedded: false,
                                canEditNodes: source.origin == .customNodes && source.isRetainedSnapshot != true,
                                changed: { updated in library = updated; changed(updated) },
                                manage: { showsManagement = true }, close: { inspectedSourceID = nil })
                        }
                    }
                    .hakoProductModal(isPresented: $showsManagement, role: .page) {
                        ConfigurationSourceDetailAdapter(model: model, source: source, library: library,
                            changed: { updated in
                                library = updated; changed(updated)
                                if !updated.sources.contains(where: { $0.id == id }) {
                                    showsManagement = false
                                    inspectedSourceID = nil
                                }
                            }, close: { showsManagement = false })
                    }
                }
            }
        }
    }
    private var visibleCollections: [ConfigurationCollectionEntry] {
        if let cached = browseCache?.wrappedValue, cached.matches(library) { return cached.entries }
        return collections
    }
    private func loadCollections(force: Bool = false) async {
        if !force, let cached = browseCache?.wrappedValue, cached.matches(library) {
            collections = cached.entries
            return
        }
        guard let store = model.configurationLibraryStore else { return }
        do {
            let snapshot = library
            let loaded = try await Task.detached { try ConfigurationCollectionContentBridge.catalog(store, snapshot: snapshot) }.value
            guard !Task.isCancelled, library.generation == snapshot.generation else { return }
            collections = loaded
            browseCache?.wrappedValue = .init(generation: snapshot.generation, entries: loaded)
        }
        catch { errorMessage = error.localizedDescription }
    }
    private func updateAll() {
        guard !busy, let store = model.configurationLibraryStore else { return }
        busy = true; errorMessage = nil; statusMessage = nil
        let sources = library.availableSources
        Task { @MainActor in
            defer { busy = false; updateProgress = nil }
            var result = await ConfigurationCollectionContentBridge.updateNodeLibrary(sources,
                updateSource: { source in try await model.refreshConfigurationSource(source.id) },
                collections: {
                    try await Task.detached {
                        try ConfigurationCollectionContentBridge.catalog(store, snapshot: store.snapshot())
                    }.value
                }, updateCollection: { entry in
                    let source = try await Task.detached { try store.payload(.init(entry.source)) }.value
                    try await ConfigurationCollectionContentBridge.refresh(entry, source: source)
                }, progress: { phase, index, total, name in
                    let key = phase == .sources ? "Updating Sources…" : "Updating Node Collections…"
                    updateProgress = HakoCopy.string(key, locale: locale) + " \(index) / \(total) · " + name
                })
            do {
                library = try await Task.detached { try store.snapshot() }.value
                changed(library)
                 
                await loadCollections(force: true)
            } catch { result.failures.append(error.localizedDescription) }
            statusMessage = HakoCopy.string("Resources updated", locale: locale) + ": " + String(result.updated)
            if !result.failures.isEmpty { errorMessage = result.failures.joined(separator: "\n") }
        }
    }
    private func reload(showsLoading: Bool = true) async {
        guard !busy else { return }
        if showsLoading { busy = true }
        errorMessage = nil; statusMessage = nil
        defer { if showsLoading { busy = false } }
        do {
            guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            do { try await model.registerLegacyConfigurationSources() }
            catch { errorMessage = error.localizedDescription }
            library = try await Task.detached { try store.snapshot() }.value
            changed(library); ready = true
        } catch { errorMessage = error.localizedDescription }
    }
}

struct ConfigurationRuleLibraryAdapter: View {
    @Environment(\.locale) private var locale
    let model: ProfilesViewModel
    @State var library: ConfigurationLibrarySnapshot
    let changed: (ConfigurationLibrarySnapshot) -> Void
    let close: () -> Void
    var embedded = false
    var showsClose = true
    var browseCache: Binding<ConfigurationLibraryBrowseCache?>? = nil
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var updateProgress: String?
    @State private var updateStatus: String?
    @State private var openedSchemeID: String?
    @State private var importing = false
    @State private var importingCollection = false
    @State private var addMode = 1
    @State private var pendingAddMode: Int?
    @State private var confirmsAddTabDiscard = false
    @State private var collections: [ConfigurationCollectionEntry] = []
    @State private var inspectedCollection: ConfigurationCollectionEntry?
    @State private var ready = false
    var body: some View {
        ConfigurationLibraryNavigation(embedded: embedded) {
            HakoTowerRulesLibraryView(library: library, palette: .hakoProduct, busy: busy, error: errorMessage,
                open: { openedSchemeID = $0 },
                refresh: { id in perform {
                    guard let scheme = library.effectiveRuleScheme(id) else { throw ConfigurationLibraryError.missingDependency(id) }
                    try await model.refreshConfigurationSource(scheme.sourceID); try await reload()
                } }, delete: { id in perform { apply(try await model.deleteConfigurationRuleScheme(id, generation: library.generation)) } },
                add: { addMode = 1; importing = true }, close: close, showsClose: showsClose,
                collections: visibleCollections, openCollection: { inspectedCollection = $0 },
                updateAll: visibleCollections.contains(where: { $0.id.kind == .rules && $0.collection.type == "http" && $0.source.isRetainedSnapshot != true }) ? updateAllRuleSets : nil,
                updateProgress: updateProgress, updateStatus: updateStatus)
            .task {
                if !ready {
                    if browseCache?.wrappedValue != nil { ready = true; await loadCollections() }
                    else { perform { try await reload(); ready = true } }
                }
            }
            .hakoProductModal(isPresented: $importing, role: .form) {
                Group {
                    switch addMode {
                    case 1, 2:
                        ConfigurationSourceImportAdapter(model: model, kind: addMode == 1 ? .subscription : .file,
                            purpose: .rules, externalTabHeader: { AnyView(ruleAddTabs(dirty: $0)) },
                            importRuleCollection: { importingCollection = true }, finishImport: { importing = false }) { payload in
                            if payload.record.ruleCount > 0 {
                                apply(try await model.addConfigurationRuleScheme(payload, generation: library.generation))
                            } else {
                                var value = payload; value.record.suppliesNodes = false; value.record.registersSuppliedRules = false
                                guard !ConfigurationCollection.read(sourceID: value.record.id,
                                    document: try OrderedJSON.parse(value.documentJSON), kind: .rules).isEmpty else {
                                    throw ConfigurationLibraryError.missingRules
                                }
                                apply(try await model.addConfigurationSource(value, generation: library.generation))
                            }
                            importing = false
                        }.id(addMode)
                    case 3:
                        ConfigurationNewRuleAdapter(model: model, library: library, tabHeader: { AnyView(ruleAddTabs(dirty: $0)) }, changed: apply, close: { importing = false })
                    default: EmptyView()
                    }
                }
                .hakoProductModal(isPresented: $importingCollection, role: .form) {
                    ConfigurationCollectionImportAdapter(model: model, library: library, changed: apply,
                        close: { importingCollection = false })
                }
            }
            .alert("Discard Changes?", isPresented: $confirmsAddTabDiscard) {
                Button("Keep Editing", role: .cancel) { pendingAddMode = nil }
                Button("Discard Changes", role: .destructive) { if let next = pendingAddMode { addMode = next }; pendingAddMode = nil }
            } message: { Text("Switching tabs discards what you have not saved.") }
            .onChange(of: openedSchemeID == nil) { closed in
                if closed { Task { await loadCollections() } }
            }
            .onChange(of: inspectedCollection == nil) { closed in
                if closed { Task { await loadCollections(force: true) } }
            }
            .hakoProductModal(item: $inspectedCollection, role: .page) { entry in
                ConfigurationCollectionAdapter(model: model, entry: entry, changed: apply, close: { inspectedCollection = nil })
            }
            .hakoProductModal(isPresented: Binding(get: { openedSchemeID != nil }, set: { if !$0 { openedSchemeID = nil } }), role: .page) {
                if let id = openedSchemeID, let scheme = library.effectiveRuleScheme(id) {
                    ConfigurationTowerRuleCustomizationAdapter(model: model, scheme: scheme, library: library, pushed: false,
                        changed: apply, close: { openedSchemeID = nil })
                }
            }
        }
    }
    private func ruleAddTabs(dirty: Bool) -> some View {
        Picker("Add Rules", selection: Binding(get: { addMode }, set: { next in
            guard next != addMode else { return }
            if dirty { pendingAddMode = next; confirmsAddTabDiscard = true } else { addMode = next }
        })) {
            Text(HakoCopy.key("URL")).tag(1)
            Text(HakoCopy.key("File")).tag(2)
            Text(HakoCopy.key("Manual")).tag(3)
        }.pickerStyle(.segmented).padding(.horizontal, 20).padding(.bottom, 8)
            .accessibilityIdentifier("configuration.rules.add.tabs")
    }
    private func apply(_ value: ConfigurationLibrarySnapshot) {
        guard library.generation != value.generation else { return }
        library = value; changed(value)
         
         
        if openedSchemeID == nil { Task { await loadCollections() } }
    }
    private func reload() async throws {
        do { try await model.registerLegacyConfigurationSources() } catch { errorMessage = error.localizedDescription }
        guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        apply(try await Task.detached { try store.snapshot() }.value)
    }
    private var visibleCollections: [ConfigurationCollectionEntry] {
        if let cached = browseCache?.wrappedValue, cached.matches(library) { return cached.entries }
        return collections
    }
    private func loadCollections(force: Bool = false) async {
        if !force, let cached = browseCache?.wrappedValue, cached.matches(library) {
            collections = cached.entries
            return
        }
        guard let store = model.configurationLibraryStore else { return }
        do {
            let snapshot = library
            let loaded = try await Task.detached { try ConfigurationCollectionContentBridge.catalog(store, snapshot: snapshot) }.value
            guard !Task.isCancelled, library.generation == snapshot.generation else { return }
            collections = loaded
            browseCache?.wrappedValue = .init(generation: snapshot.generation, entries: loaded)
        }
        catch { errorMessage = error.localizedDescription }
    }
    private func updateAllRuleSets() {
        guard !busy, let store = model.configurationLibraryStore else { return }
        busy = true; errorMessage = nil; updateStatus = nil
        let entries = visibleCollections
        Task { @MainActor in
            defer { busy = false; updateProgress = nil }
            let result = await ConfigurationCollectionContentBridge.updateRuleCollections(entries, update: { entry in
                let source = try await Task.detached { try store.payload(.init(entry.source)) }.value
                try await ConfigurationCollectionContentBridge.refresh(entry, source: source)
            }, progress: { index, total, name in
                updateProgress = "\(index) / \(total) · " + name
            })
             
            await loadCollections(force: true)
            updateStatus = HakoCopy.string("Rule sets updated", locale: locale) + ": " + String(result.updated)
            if !result.failures.isEmpty { errorMessage = result.failures.joined(separator: "\n") }
        }
    }
    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true; errorMessage = nil
        Task { @MainActor in defer { busy = false }; do { try await operation() } catch { errorMessage = error.localizedDescription } }
    }
}

private struct ConfigurationTowerRuleCustomizationAdapter: View {
    let model: ProfilesViewModel
    let scheme: ConfigurationRuleScheme
    @State var library: ConfigurationLibrarySnapshot
    var pushed = false
    let changed: (ConfigurationLibrarySnapshot) -> Void
    let close: () -> Void
    private struct LoadedEditor: Sendable {
        let draft: ConfigurationRuleDraft
        let resetDocument: String
        let ruleSetKeys: Set<String>
    }
    @State private var initial: LoadedEditor?
    @State private var identityDraft: ConfigurationRuleDraft?
    @State private var errorMessage: String?
    var body: some View {
        HakoFeatureNavigationContainer(ownsNavigationContainer: !pushed) {
            Group {
                if let initial {
                    HakoTowerRuleCustomizationView(draft: initial.draft, localSets: library.localRuleSets ?? [],
                        resetDocument: initial.resetDocument, palette: .hakoProduct, pushed: pushed, ruleSetKeys: initial.ruleSetKeys,
                        save: save, download: ConfigurationTowerRuleReader.rules,
                        saveLocal: { value in apply(try await model.saveConfigurationLocalRuleSet(value)); return (try await reloadDraft(), library.localRuleSets ?? []) },
                        deleteLocal: { id in apply(try await model.saveConfigurationLocalRuleSet(nil, deleting: id)); return (try await reloadDraft(), library.localRuleSets ?? []) },
                        copy: { draft, name in
                            let saved = try await save(draft)
                            apply(try await model.copyConfigurationRuleScheme(saved.schemeID, label: name, generation: library.generation))
                        }, close: close,
                        manualEditor: { draft, accept in AnyView(ConfigurationTowerManualRuleEditor(draft: draft, accept: accept)) })
                } else if let errorMessage {
                    Form { Text(verbatim: errorMessage); Button("Retry") { Task { await load() } }; Button("Close", action: close) }
                } else { ProgressView() }
            }.task { if initial == nil { await load() } }
        }
    }
    private func apply(_ value: ConfigurationLibrarySnapshot) { library = value; changed(value) }
    private func load() async {
        do {
            guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            let selected = scheme
            let loaded = try await Task.detached {
                _ = ConfigurationRuleCatalog.builtIn
                let draft = try ConfigurationRuleDraft(scheme: selected, payload: store.ruleSchemePayload(selected.id))
                let currentBase = try selected.baseSchemeID.flatMap { ConfigurationBuiltins.isNative($0) ? try ConfigurationBuiltins.source(for: $0)?.documentJSON : nil }
                return LoadedEditor(draft: draft, resetDocument: currentBase ?? selected.initialDocumentJSON ?? draft.originalDocument.serialized(),
                    ruleSetKeys: draft.referencedRuleSets)
            }.value
            identityDraft = loaded.draft; initial = loaded
        } catch { errorMessage = error.localizedDescription }
    }
    private func reloadDraft() async throws -> ConfigurationRuleDraft {
        guard let store = model.configurationLibraryStore, let current = library.effectiveRuleScheme(identityDraft?.schemeID ?? scheme.id) else { throw ConfigurationLibraryError.unreadable }
        let previous = identityDraft
        let result = try await Task.detached {
            let loaded = try ConfigurationRuleDraft(scheme: current, payload: store.ruleSchemePayload(current.id))
            return previous.map { loaded.preservingIdentity(from: $0) } ?? loaded
        }.value
        identityDraft = result
        return result
    }
    private func save(_ draft: ConfigurationRuleDraft) async throws -> ConfigurationRuleDraft {
        apply(try await model.saveConfigurationRuleCustomization(draft, generation: library.generation))
        guard let store = model.configurationLibraryStore,
              let current = library.ruleSchemeAfterSavingCustomization(draft.schemeID) else { throw ConfigurationLibraryError.unreadable }
        let result = try await Task.detached {
            try ConfigurationRuleDraft(scheme: current, payload: store.ruleSchemePayload(current.id)).preservingIdentity(from: draft)
        }.value
        identityDraft = result
        return result
    }
}

private struct ConfigurationTowerRuleImportAdapter: View {
    @ObservedObject var model: ProfilesViewModel
    let generation: UInt64
    let changed: (ConfigurationLibrarySnapshot) -> Void
    let close: () -> Void
    @State private var link = ""
    @State private var name = ""
    @State private var busy = false
    @State private var errorMessage: String?
    var body: some View {
        HakoFeatureNavigationContainer {
            Form {
                Section("Rule URL") { TextField("URL", text: $link, prompt: Text("https://…")).accessibilityIdentifier("configuration.rule.import.url").autocorrectionDisabled().textInputAutocapitalization(.never) }
                Section("Name (Optional)") { TextField("Leave blank to use the file name", text: $name).accessibilityIdentifier("configuration.rule.import.name") }
                Section { Text("导入 Clash YAML 规则方案。").font(.footnote).foregroundStyle(.secondary) }
                if let errorMessage { Text(verbatim: errorMessage).foregroundStyle(.orange) }
            }.disabled(busy).hakoPageTitle("Import Rules")
            .hakoToolbarUnlessInPanel {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: close).disabled(busy) }
                ToolbarItem(placement: .confirmationAction) { Button(busy ? "正在下载…" : "导入") { submit() }.disabled(busy || link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .hakoRegistersDeparture(isDirty: !link.isEmpty || !name.isEmpty, isBusy: busy, save: { submit($0) }, discard: { link = ""; name = "" })
        }
    }
    private func submit(_ completion: @escaping (Bool) -> Void = { _ in }) {
        guard !busy, !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { completion(false); return }
        busy = true; errorMessage = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                let payload = try await model.fetchConfigurationSource(url: ConfigurationTowerRuleReader.normalizedURL(link), label: name)
                changed(try await model.addConfigurationRuleScheme(payload, generation: generation)); completion(true); close()
            } catch { errorMessage = error.localizedDescription; completion(false) }
        }
    }
}

private struct ConfigurationChainChoice: Identifiable, Sendable {
    let hop: ConfigurationNodeChain.Hop
    let sourceLabel: String
    var id: String { hop.source.id + "/" + hop.nodeName }
}

 
private final class ConfigurationChainEditorDraft: ObservableObject {
    var isDirty: Bool { !name.isEmpty || entry != nil || exit != nil }
    @Published var name: String
    @Published var entry: ConfigurationNodeChain.Hop?
    @Published var exit: ConfigurationNodeChain.Hop?
    init(existing: ConfigurationSourceRecord? = nil) {
        name = existing?.label ?? ""; entry = existing?.nodeChain?.entry; exit = existing?.nodeChain?.exit
    }
}

private struct ConfigurationChainEditor: View {
    @Environment(\.hakoInsideProductModalPresentation) private var insideProductModal
    let model: ProfilesViewModel
    let existing: ConfigurationSourceRecord?
    let accept: (ConfigurationSourcePayload) async throws -> Void
    let close: () -> Void
    @StateObject private var draft: ConfigurationChainEditorDraft
    private let tabHeader: (() -> AnyView)?
    private let onSaved: (() -> Void)?
    private let isFirstConfigurationStep: Bool
    private var name: String { get { draft.name } nonmutating set { draft.name = newValue } }
    private var entry: ConfigurationNodeChain.Hop? { get { draft.entry } nonmutating set { draft.entry = newValue } }
    private var exit: ConfigurationNodeChain.Hop? { get { draft.exit } nonmutating set { draft.exit = newValue } }
    @State private var choices: [ConfigurationChainChoice] = []
    @State private var loadedGeneration: UInt64?
    @State private var pickingEntry: Bool?
    @State private var search = ""
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var confirmsDiscard = false

    init(model: ProfilesViewModel, existing: ConfigurationSourceRecord?, draft: ConfigurationChainEditorDraft? = nil,
        tabHeader: (() -> AnyView)? = nil, isFirstConfigurationStep: Bool = false, accept: @escaping (ConfigurationSourcePayload) async throws -> Void, close: @escaping () -> Void, onSaved: (() -> Void)? = nil) {
        self.tabHeader = tabHeader; self.onSaved = onSaved
        self.isFirstConfigurationStep = isFirstConfigurationStep
        self.model = model; self.existing = existing; self.accept = accept; self.close = close
        _draft = StateObject(wrappedValue: draft ?? ConfigurationChainEditorDraft(existing: existing))
    }
    private var dirty: Bool { name != (existing?.label ?? "") || entry != existing?.nodeChain?.entry || exit != existing?.nodeChain?.exit }
    private var canSave: Bool { !busy && loadedGeneration != nil && entry != nil && exit != nil && entry != exit && dirty }
    var body: some View {
        HakoFeatureNavigationContainer {
            VStack(spacing: 0) {
                if let tabHeader { tabHeader().disabled(busy) }
                Form {
                Section { TextField("Name", text: $draft.name, prompt: Text("Entry → Exit")).accessibilityIdentifier("configuration.chain.name") }
                Section {
                    Text("This Device")
                    hopRow("Entry Node", hop: entry) { pickingEntry = true; search = "" }
                    hopRow("Exit Node", hop: exit) { pickingEntry = false; search = "" }
                    Text("Destination Website")
                } header: { Text("Connection Order") }
                if loadedGeneration == nil { ProgressView("Loading Nodes") }
                else if choices.isEmpty { Text("Add nodes to Node Library first.").foregroundStyle(.secondary) }
                if let errorMessage { Section { Text(verbatim: errorMessage).foregroundStyle(.orange) } }
                }
            }
            .disabled(busy)
            .hakoPageTitle(.copy(isFirstConfigurationStep ? "Create Nodes 1/2" : (tabHeader != nil ? HakoConfigurationAddition.nodes.title : (existing == nil ? "Add Proxy Chain" : "Edit Proxy Chain"))))
            .hakoToolbarUnlessInPanel {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if dirty { confirmsDiscard = true } else { close() } }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) { Button { save() } label: { HakoActionProgressLabel(.copy(isFirstConfigurationStep ? "Next" : "Done"), isBusy: busy) }.disabled(!canSave) }
            }
            .hakoProductModalRoot(title: isFirstConfigurationStep ? "Create Nodes 1/2" : (tabHeader != nil ? HakoConfigurationAddition.nodes.title : "Proxy Chain"))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if insideProductModal { HakoModalActionBar(primaryTitle: isFirstConfigurationStep ? "Next" : "Done", primaryDisabled: !canSave, isBusy: busy) { save() } }
            }
            .interactiveDismissDisabled(dirty || busy)
            .hakoRegistersDeparture(isDirty: dirty, isBusy: busy, save: { save($0) }, discard: {
                name = existing?.label ?? ""; entry = existing?.nodeChain?.entry; exit = existing?.nodeChain?.exit
            })
            .hakoUnsavedChangesAlert(isPresented: $confirmsDiscard, message: "This proxy chain has unsaved changes.",
                isBusy: busy, saveDisabled: !canSave, save: { save() }, discard: {
                    name = existing?.label ?? ""; entry = existing?.nodeChain?.entry; exit = existing?.nodeChain?.exit
                    close()
                })
            .task { if loadedGeneration == nil { await load() } }
            .hakoProductModal(isPresented: Binding(get: { pickingEntry != nil }, set: { if !$0 { pickingEntry = nil } }), role: .page) {
                HakoFeatureNavigationContainer {
                    List {
                        ForEach(choices.filter { search.isEmpty || $0.hop.nodeName.localizedCaseInsensitiveContains(search) || $0.sourceLabel.localizedCaseInsensitiveContains(search) }) { choice in
                            Button {
                                if pickingEntry == true { entry = choice.hop } else { exit = choice.hop }
                                pickingEntry = nil
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(verbatim: choice.hop.nodeName).foregroundStyle(.primary)
                                        Text(verbatim: choice.sourceLabel).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: (pickingEntry == true ? entry : exit) == choice.hop ? HakoSymbol.checkmarkCircleFill.name : HakoSymbol.circle.name)
                                        .foregroundStyle(.tint)
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                    .hakoProductModalSearchable(text: $search)
                    .hakoPageTitle(pickingEntry == true ? "Entry Node" : "Exit Node")
                    .hakoToolbarUnlessInPanel {
                        ToolbarItem(placement: .cancellationAction) { HakoSheetCloseButton(dismiss: { pickingEntry = nil }) }
                    }
                }
            }
        }
    }
    private func hopRow(_ title: String, hop: ConfigurationNodeChain.Hop?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: HakoSymbol.arrowDown.name).foregroundStyle(.secondary)
                Text(HakoCopy.key(title))
                Spacer()
                if let hop { Text(verbatim: hop.nodeName).lineLimit(1).truncationMode(.middle) }
                else { Text("Choose Node") }
                Image(systemName: HakoSymbol.infoCircle.name).foregroundStyle(Color.blue)
            }
        }.disabled(loadedGeneration == nil || choices.isEmpty)
    }
    private func load() async {
        do {
            guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            let loaded = try await Task.detached {
                let snapshot = try store.snapshot()
                var choices: [ConfigurationChainChoice] = []
                for record in snapshot.availableSources where record.suppliesNodes && record.nodeChain == nil {
                    let payload = try store.payload(.init(record))
                    guard case .array(let nodes) = try OrderedJSON.parse(payload.documentJSON).topLevelValue("proxies") else { continue }
                    for node in nodes {
                        guard case .string(let name) = node.topLevelValue("name") else { continue }
                        if case .string(let dialer) = node.topLevelValue("dialer-proxy"), !dialer.isEmpty, dialer != "DIRECT" { continue }
                        choices.append(.init(hop: .init(source: .init(record), nodeName: name), sourceLabel: record.label))
                    }
                }
                return (choices, snapshot.generation)
            }.value
            choices = loaded.0; loadedGeneration = loaded.1
        } catch { errorMessage = error.localizedDescription }
    }
    private func save(_ completion: @escaping (Bool) -> Void = { _ in }) {
        guard canSave, let entry, let exit, let generation = loadedGeneration else { completion(false); return }
        busy = true; errorMessage = nil
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = existing ?? ConfigurationSourceRecord(label: "", origin: .customNodes)
        Task {
            defer { busy = false }
            do {
                guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
                let payload = try await Task.detached {
                    guard try store.snapshot().generation == generation else { throw ConfigurationLibraryError.staleGeneration }
                    var record = record
                    record.label = label.isEmpty ? entry.nodeName + " → " + exit.nodeName : label
                    return try ConfigurationNodeChain.materialize(record: record, chain: .init(entry: entry, exit: exit), load: store.payload)
                }.value
                try await accept(payload); completion(true)
                name = existing?.label ?? ""; self.entry = existing?.nodeChain?.entry; self.exit = existing?.nodeChain?.exit
                (onSaved ?? close)()
            } catch { errorMessage = error.localizedDescription; completion(false) }
        }
    }
}

private struct ConfigurationChainDetail: View {
    let model: ProfilesViewModel
    let source: ConfigurationSourceRecord
    let changed: (ConfigurationLibrarySnapshot) -> Void
    let close: () -> Void
    @State private var editing = false
    @State private var deleting = false
    @State private var busy = false
    @State private var errorMessage: String?
    private func chainHopLine(_ name: String) -> some View {
        HStack {
            Image(systemName: HakoSymbol.arrowDown.name).foregroundStyle(.secondary)
            Text(verbatim: name).lineLimit(1).truncationMode(.middle)
        }
    }
    var body: some View {
        HakoFeatureNavigationContainer {
            Form {
                if let chain = source.nodeChain {
                    Section {
                         
                         
                         
                        Text("This Device")
                        chainHopLine(chain.entry.nodeName)
                        chainHopLine(chain.exit.nodeName)
                        Text("Destination Website")
                    } header: { Text("Connection Order") }
                }
                Section { Button("Delete Proxy Chain", role: .destructive) { deleting = true } }
                if let errorMessage { Text(verbatim: errorMessage).foregroundStyle(.orange) }
            }.disabled(busy)
            .hakoPageTitle(.verbatim(source.label), watchAs: "Proxy Chain")
            .hakoToolbarUnlessInPanel {
                ToolbarItem(placement: .cancellationAction) { HakoSheetCloseButton(dismiss: close).disabled(busy) }
                ToolbarItem(placement: .primaryAction) { Button("Edit") { editing = true }.disabled(busy) }
            }
            .interactiveDismissDisabled(busy)
            .hakoProductModal(isPresented: $editing, role: .page) {
                ConfigurationChainEditor(model: model, existing: source, accept: { payload in
                    changed(try await model.saveConfigurationChain(.init(source), replacement: payload))
                }, close: { editing = false })
            }
            .hakoDeleteConfirmation(source.label, isPresented: $deleting,
                actionTitle: .copy("Delete Proxy Chain"),
                message: .copy("Saved profiles keep this chain. Its original nodes remain in the library."),
                identifier: "configuration.chain.delete.confirm") {
                    busy = true
                    Task {
                        defer { busy = false }
                        do {
                            guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
                            let generation = try await Task.detached { try store.snapshot().generation }.value
                            changed(try await model.deleteConfigurationSource(source.id, generation: generation)); close()
                        } catch { errorMessage = error.localizedDescription }
                    }
            }
        }
    }
}

private struct ConfigurationNodeSourceEditor: View {
    let model: ProfilesViewModel
    let record: ConfigurationSourceRecord
    let changed: (ConfigurationLibrarySnapshot) -> Void
    @State private var yaml: String?
    @State private var version: ConfigurationSourceVersion?
    @State private var errorMessage: String?
    private var profile: Profile {
        .init(id: record.id, label: record.label, source: .clipboard, autoUpdate: false,
            updateIntervalHours: 0, subscriptionInfo: nil, selectedMap: [:], activeRevision: nil,
            order: 0, lastUpdatedAt: nil)
    }
    var body: some View {
        Group {
            if let yaml, let version {
                ProfileEditView(profile: profile, rawYAML: yaml, editorTitle: "Edit Nodes Source") { _, text, files, _ in
                    guard let text else { return }
                    guard files.isEmpty else { throw CocoaError(.featureUnsupported) }
                    changed(try await model.saveConfigurationNodeSource(version, yaml: text))
                }
            } else if let errorMessage {
                Form {
                    Text(verbatim: errorMessage).foregroundStyle(.orange)
                    Button("Retry") { Task { await load() } }
                }
            } else { ProgressView("Opening Editor") }
        }.task { if yaml == nil { await load() } }
    }
    private func load() async {
        errorMessage = nil
        do {
            guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            let id = record.id
            let loaded = try await Task.detached {
                guard let current = try store.snapshot().sources.first(where: { $0.id == id }) else {
                    throw ConfigurationLibraryError.missingDependency(id)
                }
                let payload = try store.payload(.init(current))
                guard case .object(let entries) = try OrderedJSON.parse(payload.documentJSON) else {
                    throw ConfigurationLibraryError.unreadable
                }
                let nodes = OrderedJSON.object(entries.filter { ["proxies", "proxy-providers"].contains($0.key) })
                return (try ConfigTransforms.jsonToYAML(nodes.serialized()), ConfigurationSourceVersion(current))
            }.value
            yaml = loaded.0; version = loaded.1
        } catch { errorMessage = error.localizedDescription }
    }
}

 
private struct ConfigurationTowerManualRuleEditor: View {
    let draft: ConfigurationRuleDraft
    let accept: (ConfigurationRuleDraft) async throws -> Void
    @State private var source: String?
    @State private var errorMessage: String?
    @Environment(\.hakoProductModalDismiss) private var dismiss

     
     
    private var document: Profile {
        Profile(id: draft.schemeID, label: draft.label, source: .clipboard,
            autoUpdate: false, updateIntervalHours: 0, subscriptionInfo: nil,
            selectedMap: [:], activeRevision: nil, order: 0, lastUpdatedAt: nil)
    }
    var body: some View {
        Group {
            if let source {
                ProfileEditView(profile: document, rawYAML: source, editorTitle: "Edit Rules Source") { _, yaml, resources, _ in
                    guard let yaml else { return }
                     
                     
                    guard resources.isEmpty else { throw CocoaError(.featureUnsupported) }
                    let original = draft
                    let value = try await Task.detached(priority: .userInitiated) {
                        let root = try OrderedJSON.parse(ConfigTransforms.yamlToJSON(yaml))
                        if case .object(let entries) = root,
                           entries.contains(where: { !ConfigurationRuleDocument.keys.contains($0.key) }) {
                            throw NSError(domain: "ConfigurationRuleEditor", code: 1, userInfo: [
                                NSLocalizedDescriptionKey: HakoCopy.string("Only rules and policy groups belong here. Add nodes in Node Library.", locale: .current)])
                        }
                        var updated = original
                        try updated.replaceContents(root)
                        return updated
                    }.value
                    try await accept(value)
                }
            } else if let errorMessage {
                Form {
                    Text(verbatim: errorMessage).foregroundStyle(.orange)
                    Button("Retry") { Task { await load() } }
                    Button("Close") { dismiss?() }
                }
            } else {
                ProgressView("Opening Editor").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { if source == nil { await load() } }
    }
    private func load() async {
        errorMessage = nil
        let snapshot = draft
        do {
            source = try await Task.detached(priority: .userInitiated) {
                try ConfigTransforms.jsonToYAML(snapshot.currentDocument().serialized())
            }.value
        } catch { errorMessage = error.localizedDescription }
    }
}

enum ConfigurationTowerRuleReader {
    static func normalizedURL(_ value: String) -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var parts = URLComponents(string: value) else { return value }
        if parts.host == "github.com" {
            let path = parts.path.split(separator: "/").map(String.init)
            if path.count > 4, path[2] == "blob" {
                parts.host = "raw.githubusercontent.com"; parts.path = "/" + ([path[0], path[1]] + Array(path.dropFirst(3))).joined(separator: "/")
            }
        }
        return parts.string ?? value
    }
    static func rules(_ input: String) async throws -> [String] {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: normalizedURL(text)), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
            var request = URLRequest(url: url); request.timeoutInterval = 30
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  data.count <= 32 * 1024 * 1024, let decoded = String(data: data, encoding: .utf8) else { throw ConfigurationLibraryError.unreadable }
            text = decoded
        }
        let raw = text
        return try await Task.detached {
            let lines: [String]
            if raw.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("payload:") {
                let object = try OrderedJSON.parse(ConfigTransforms.yamlToJSON(raw))
                guard case .array(let values) = object.topLevelValue("payload") else { throw ConfigurationLibraryError.missingRules }
                lines = try values.map { guard case .string(let value) = $0 else { throw ConfigurationLibraryError.missingRules }; return value }
            } else {
                lines = raw.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("//") }
            }
            guard !lines.isEmpty else { throw ConfigurationLibraryError.missingRules }
            let document = OrderedJSON.object([
                ("rule-providers", .object([("check", .object([("type", .string("inline")), ("behavior", .string("classical")), ("payload", .array(lines.map(OrderedJSON.string)))]))])),
                ("rules", .array([.string("RULE-SET,check,DIRECT"), .string("MATCH,DIRECT")]))
            ])
            try ConfigTransforms.validateSource(document.serialized())
            return lines
        }.value
    }
}

private struct ConfigurationRuleEditingAdapter: View {
    @ObservedObject var model: ProfilesViewModel
    @Environment(\.locale) private var locale
    let scheme: ConfigurationRuleScheme
    let generation: UInt64
    let changed: (ConfigurationLibrarySnapshot) -> Void
    let close: () -> Void
    @State private var initialDraft: ConfigurationRuleDraft?
    @State private var busy = false
    @State private var errorMessage: String?

    var body: some View {
        HakoFeatureNavigationContainer {
            Group {
                if let initialDraft {
                    HakoConfigurationRuleEditingView(draft: initialDraft, isBusy: busy, error: errorMessage,
                        save: { draft, completion in
                            guard !busy else { completion(false); return }
                            busy = true; errorMessage = nil
                            Task {
                                defer { busy = false }
                                do { changed(try await model.saveConfigurationRuleDraft(draft, generation: generation)); completion(true) }
                                catch { errorMessage = error.localizedDescription; completion(false) }
                            }
                        }, close: close, ruleEditor: { raw, draft, accept, delete in
                            AnyView(HakoFeatureNavigationContainer {
                                RuleBuilderAdapter(raw: raw, options: ConfigurationGroupEditorBridge.ruleOptions(draft), showsPersonalMetadata: true,
                                    delete: delete, enabled: draft.isEnabled(raw), comment: draft.note(for: raw),
                                    saveDetails: { raw, enabled, comment in accept(raw, enabled, comment) },
                                    save: { raw in accept(raw, true, "") })
                            })
                        }, groupEditor: { draft, groupID, accept in
                            AnyView(ConfigurationGroupEditorBridge.editor(draft: draft, groupID: groupID, locale: locale, accept: accept))
                        })
                } else if let errorMessage {
                    Form { Text(verbatim: errorMessage); Button("Close", action: close) }
                } else { ProgressView() }
            }
            .task {
                guard initialDraft == nil else { return }
                do {
                    guard let library = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
                    let payload = try await Task.detached {
                        guard try library.snapshot().generation == generation else { throw ConfigurationLibraryError.staleGeneration }
                        return try library.ruleSchemePayload(scheme.id)
                    }.value
                    initialDraft = try await Task.detached {
                        try ConfigurationRuleDraft(scheme: scheme, payload: payload)
                    }.value
                } catch { errorMessage = error.localizedDescription }
            }
        }
    }
}

private struct ConfigurationNewRuleAdapter: View {
    @ObservedObject var model: ProfilesViewModel
    let library: ConfigurationLibrarySnapshot
    var tabHeader: ((Bool) -> AnyView)? = nil
    let changed: (ConfigurationLibrarySnapshot) -> Void
    let close: () -> Void
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var options: RulePolicyOptions = .empty
    @Environment(\.locale) private var locale

     
     
     
     
     
    var body: some View {
        HakoFeatureNavigationContainer {
            RuleBuilderAdapter(raw: "", options: options, showsPersonalMetadata: true,
                pageTitle: HakoConfigurationAddition.rules.title,
                saveDetails: { raw, enabled, note in submit(raw, enabled: enabled, note: note) },
                save: { raw in submit(raw, enabled: true, note: "") })
            .disabled(busy)
            .safeAreaInset(edge: .top, spacing: 0) { if let tabHeader { tabHeader(false).disabled(busy) } }
            .alert("Cannot Save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") {}
            } message: {
                Text(verbatim: errorMessage ?? "")
            }
            .task { await loadOptions() }
        }
    }

    private var activeRecipe: ConfigurationRecipe? {
        guard let id = model.activeProfileID else { return nil }
        return library.recipes.first { $0.id == id }
    }

    private var plan: QuickRulePlan {
        QuickRulePlan.make(activeSchemeID: activeRecipe?.ruleSchemeID, schemes: library.rules,
            myRulesLabel: HakoCopy.string("My Rules", locale: locale))
    }

     
     
    private func loadOptions() async {
        guard let store = model.configurationLibraryStore else { return }
        let schemeID: String
        switch plan { case .reuse(let id): schemeID = id; case .copy(let base): schemeID = base }
        guard let scheme = library.effectiveRuleScheme(schemeID) else { return }
        let loaded: RulePolicyOptions? = await Task.detached(priority: .userInitiated) {
            guard let payload = try? store.ruleSchemePayload(schemeID),
                  let draft = try? ConfigurationRuleDraft(scheme: scheme, payload: payload) else { return nil }
            return ConfigurationGroupEditorBridge.ruleOptions(draft)
        }.value
        if let loaded { options = loaded }
    }

    private func submit(_ raw: String, enabled: Bool, note: String) {
        guard !busy else { return }
        busy = true; errorMessage = nil
        Task { @MainActor in
            defer { busy = false }
            do { try await create(raw, enabled: enabled, note: note); close() }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func create(_ raw: String, enabled: Bool, note: String) async throws {
        guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        var snapshot = library
        let myRules = HakoCopy.string("My Rules", locale: locale)
        let schemeID: String
        switch plan {
        case .reuse(let id):
            schemeID = id
        case .copy(let base):
            let before = Set(snapshot.rules.map(\.id))
            snapshot = try await model.copyConfigurationRuleScheme(base, label: myRules, generation: snapshot.generation)
            guard let made = snapshot.rules.first(where: { !before.contains($0.id) }) else { throw ConfigurationLibraryError.invalidIdentifier }
            schemeID = made.id
        }
        guard let scheme = snapshot.rules.first(where: { $0.id == schemeID }) else { throw ConfigurationLibraryError.missingDependency(schemeID) }
        var draft = try await Task.detached(priority: .userInitiated) {
            try ConfigurationRuleDraft(scheme: scheme, payload: try store.ruleSchemePayload(schemeID))
        }.value
        draft.insertRuleFirst(raw)
        if let first = draft.rows.first { draft.setRule(raw, enabled: enabled, note: note, rowID: first.id) }
        snapshot = try await model.saveConfigurationRuleDraft(draft, generation: snapshot.generation)
        if let active = model.activeProfileID,
           let recipe = snapshot.recipes.first(where: { $0.id == active }),
           recipe.ruleSchemeID != schemeID {
            var edit = ConfigurationCreationAdapter.editingDraft(recipe: recipe,
                label: model.profiles.first(where: { $0.id == active })?.label ?? recipe.label)
            edit.selectedRuleID = schemeID
            try await model.editConfiguration(edit, id: active, generation: snapshot.generation)
            snapshot = try await Task.detached { try store.snapshot() }.value
        }
        changed(snapshot)
    }
}

private struct ConfigurationRuleGroupsAdapter: View {
    @ObservedObject var model: ProfilesViewModel
    let scheme: ConfigurationRuleScheme
    let close: () -> Void
    @State private var groups: [ConfigurationRuleGroupSnapshot] = []
    @State private var loading = true
    @State private var errorMessage: String?
    var body: some View {
        HakoFeatureNavigationContainer {
            HakoConfigurationRuleGroupsView(groups: groups, isLoading: loading, error: errorMessage,
                reload: { Task { await load() } }, close: close)
                .task { await load() }
        }
    }
    private func load() async {
        loading = true; errorMessage = nil
        defer { loading = false }
        do {
            guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            let id = scheme.id
            groups = try await Task.detached {
                let payload = try store.ruleSchemePayload(id)
                return try ConfigurationRuleGroupSnapshot.read(OrderedJSON.parse(payload.documentJSON))
            }.value
        } catch { errorMessage = error.localizedDescription }
    }
}

 
enum ConfigurationGroupEditorBridge {
    static func applying(_ edited: CustomProxyGroup, to original: OrderedJSON) throws -> OrderedJSON {
        let baseline = CustomProxyGroup(json: original.foundationValue as? [String: Any] ?? [:]).json
        let updated = edited.json
        var result = original
        for key in Set(baseline.keys).union(updated.keys).sorted() {
            if let before = baseline[key] as? NSObject, let after = updated[key] as? NSObject, before.isEqual(after) { continue }
            if let value = updated[key] {
                let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys])
                result = result.settingTopLevel(key, to: try OrderedJSON.parse(String(decoding: data, as: UTF8.self)))
            } else { result = result.removingTopLevel(key) }
        }
        return result
    }
    static func ruleOptions(_ draft: ConfigurationRuleDraft) -> RulePolicyOptions {
        let root = (try? draft.document().foundationValue as? [String: Any]) ?? [:]
        return RulePolicyOptions(groups: draft.groups.map { ($0.name, $0.type) }, proxies: [],
            ruleSets: (root["rule-providers"] as? [String: Any] ?? [:]).keys.sorted(),
            subRuleNames: (root["sub-rules"] as? [String: Any]).map { $0.keys.sorted() })
    }
    @MainActor static func editor(draft: ConfigurationRuleDraft, groupID: UUID?, locale: Locale, accept: @escaping (OrderedJSON) -> Void) -> some View {
        let original = groupID.flatMap { id in draft.groups.first { $0.id == id }?.document }
            ?? .object([("name", .string("")), ("type", .string("select")), ("include-all", .scalar("true"))])
        let group = CustomProxyGroup(json: original.foundationValue as? [String: Any] ?? [:])
        let root = draft.currentDocument().foundationValue as? [String: Any] ?? [:]
        let nodes = (root["proxies"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        let otherNames = Set(draft.groups.filter { $0.id != groupID }.map(\.name))
        return CustomProxyGroupEditor(group: group, existingNames: otherNames, profileProxyNames: nodes,
            validationContext: .init(nodeNames: Set(nodes), groupNames: otherNames,
                providerNames: Set((root["proxy-providers"] as? [String: Any] ?? [:]).keys), siblingGroupNames: otherNames),
            validateChange: { edited in
                do {
                    var candidate = draft
                    try candidate.setGroup(applying(edited, to: original), groupID: groupID)
                    return nil
                } catch { return HakoConfigurationRuleGroupCopy.message(error, locale: locale) }
            }, save: { edited in
                 
                if let value = try? applying(edited, to: original) { accept(value) }
            })
    }
}

 
private struct ConfigurationDocumentBrowserAdapter: View {
    enum Kind { case nodes, rules }
    @ObservedObject var model: ProfilesViewModel
    let sourceID: String
    let title: String
    var schemeID: String? = nil
    let kind: Kind
    var embedded = false
    var canEditNodes = false
    var changed: (ConfigurationLibrarySnapshot) -> Void = { _ in }
    var manage: (() -> Void)? = nil
    let close: () -> Void
    @State private var sections: [HakoConfigurationReadSection] = []
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var payload: ConfigurationSourcePayload?
    @State private var editingIndex: Int?
    @State private var editingNode: ProxyNodeRecord?
    @State private var inspectedNode: ProxyNodeRecord?
    @State private var nodeDensity = HakoProxiesRowDensity.from(HakoProxiesDisplayPreferences.load())
    @State private var adding = false
    @State private var deletingIndex: Int?
    @State private var busy = false
    @State private var consumers: [String] = []
    var body: some View {
        ConfigurationLibraryNavigation(embedded: embedded) {
            Group {
                if let editingNode, let index = editingIndex, let payload {
                    ProxyNodeDetailsView(record: editingNode, retest: {}, saveNode: { _, json in
                        let updated = try await model.saveConfigurationCustomNode(.init(payload.record), nodeJSON: json, index: index)
                        changed(updated)
                    }, showsTesting: false, onDone: {
                        self.editingNode = nil; editingIndex = nil
                        Task { await load() }
                    }, commitTitle: "Save")
                    .environment(\.hakoProductModalDismiss, {
                        self.editingNode = nil; editingIndex = nil
                    })
                    .safeAreaInset(edge: .bottom) {
                        Button("Delete Node", role: .destructive) { deletingIndex = index }.padding()
                    }
                } else {
                    HakoConfigurationContentsView(title: title, sections: sections,
                        loading: loading, error: errorMessage, reload: { Task { await load() } }, close: close,
                        showsClose: !embedded, openNode: kind == .nodes ? openNode : nil,
                        deleteNode: canEditNodes ? { deletingIndex = $0 } : nil,
                        addNode: canEditNodes ? { adding = true } : nil, isBusy: busy, manage: manage, nodeDensity: nodeDensity)
                        .environment(\.hakoProductModalDismiss, close)
                }
            }
            .task { await load() }
            .hakoProductModal(item: $inspectedNode, role: .page) { node in
                ProxyNodeDetailSheet(nodeName: node.name, yaml: nil, providersDir: nil,
                    suppliedDetails: node.protocolDetails)
            }
            .hakoProductModal(isPresented: $adding, role: .page) {
                ConfigurationNodeSourceAdapter { imported in
                    guard let payload,
                          case .array(let nodes) = try OrderedJSON.parse(imported.documentJSON).topLevelValue("proxies"),
                          nodes.count == 1 else { throw ConfigurationLibraryError.unreadable }
                    let updated = try await model.saveConfigurationCustomNode(.init(payload.record), nodeJSON: nodes[0].serialized(), index: nil)
                    changed(updated)
                    await load()
                }
            }
            .hakoDeleteConfirmation(deletingIndex.flatMap { index in sections.flatMap(\.rows).first(where: { $0.nodeIndex == index })?.title } ?? HakoCopy.string("Node", locale: .current),
                isPresented: Binding(get: { deletingIndex != nil }, set: { if !$0 { deletingIndex = nil } }),
                actionTitle: .copy("Delete Node"),
                message: .copy("This node will be removed from the source and profiles that follow its updates."),
                identifier: "configuration.node.delete.confirm") { [deletingIndex] in
                    if let index = deletingIndex { remove(index) }
                }
            .disabled(busy)
            .interactiveDismissDisabled(busy)
        }
    }
    private func openNode(_ index: Int) {
        if canEditNodes { edit(index); return }
        guard let json = sections.flatMap(\.rows).first(where: { $0.nodeIndex == index })?.content,
              let node = CustomNodesView.record(fromNodeJSON: json) else {
            errorMessage = ConfigurationLibraryError.unreadable.localizedDescription
            return
        }
        inspectedNode = node
    }
    private func edit(_ index: Int) {
        do {
            guard let payload,
                  case .array(let nodes) = try OrderedJSON.parse(payload.documentJSON).topLevelValue("proxies"),
                  nodes.indices.contains(index),
                  let node = CustomNodesView.record(fromNodeJSON: nodes[index].serialized()) else { throw ConfigurationLibraryError.unreadable }
            editingNode = node; editingIndex = index
        } catch { errorMessage = error.localizedDescription }
    }
    private func remove(_ index: Int) {
        guard let payload, !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                changed(try await model.deleteConfigurationCustomNode(.init(payload.record), index: index))
                editingNode = nil; editingIndex = nil; deletingIndex = nil
                await load()
            } catch {
                 
                 
                editingNode = nil; editingIndex = nil; deletingIndex = nil
                errorMessage = error.localizedDescription
            }
        }
    }
    private func load() async {
        loading = true; errorMessage = nil
        defer { loading = false }
        do {
            guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            let id = sourceID, scheme = schemeID, nodes = kind == .nodes
            let loaded = try await Task.detached {
                let snapshot = try store.snapshot()
                let payload: ConfigurationSourcePayload
                if let scheme { payload = try store.ruleSchemePayload(scheme) }
                else {
                    guard let source = snapshot.sources.first(where: { $0.id == id }) else { throw ConfigurationLibraryError.missingDependency(id) }
                    payload = try store.payload(.init(source))
                }
                let document = try OrderedJSON.parse(payload.documentJSON)
                var result: [HakoConfigurationReadSection] = []
                if nodes {
                    if case .array(let values) = document.topLevelValue("proxies") {
                        result.append(.init(title: "Nodes", rows: values.enumerated().map { index, node in
                            let name = node.topLevelValue("name")?.foundationValue as? String ?? String(index + 1)
                            let type = node.topLevelValue("type")?.foundationValue as? String ?? ""
                            return .init(title: name, subtitle: type, content: node.serialized(), nodeIndex: index)
                        }))
                    }
                } else {
                    if case .array(let rules) = document.topLevelValue("rules") {
                        result.append(.init(title: "Rules", rows: rules.map { .init(title: $0.foundationValue as? String ?? $0.serialized()) }))
                    }
                    if case .object(let entries) = document.topLevelValue("sub-rules") {
                        result.append(.init(title: "Sub-rules", rows: entries.map { .init(title: $0.key, content: $0.value.serialized()) }))
                    }
                }
                let key = nodes ? "proxy-providers" : "rule-providers"
                let collections = ConfigurationCollection.read(sourceID: id, document: document, kind: nodes ? .nodes : .rules)
                if !nodes && !collections.isEmpty {
                    result.append(.init(title: nodes ? "Node Collections" : "Rule Collections", rows: collections.map {
                        .init(title: $0.name, collection: $0)
                    }))
                }
                let users = snapshot.recipes.filter { $0.sources.contains(where: { $0.id == id }) || $0.ruleSource.id == id }.map(\.label)
                return (result, payload, users)
            }.value
            sections = loaded.0; payload = loaded.1; consumers = loaded.2
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct ConfigurationLibraryNavigation<Content: View>: View {
    let embedded: Bool
    @ViewBuilder var content: () -> Content
    var body: some View {
        if embedded { content() }
        else { HakoFeatureNavigationContainer { content() } }
    }
}


private struct ConfigurationNodeScopeAdapter: View {
    @ObservedObject var model: ProfilesViewModel
    let source: ConfigurationSourceRecord
    let staged: ConfigurationSourcePayload?
    let initial: ConfigurationNodeScope?
    let save: (ConfigurationNodeScope?) -> Void
    let close: () -> Void
    @State private var collections: [ConfigurationCollection]?
    @State private var nodes: [HakoConfigurationSelectableNode] = []
    @State private var error: String?
    var body: some View {
        HakoFeatureNavigationContainer {
            Group {
                if let collections {
                    HakoConfigurationNodeScopeView(source: source, collections: collections, nodes: nodes, initial: initial, save: save, close: close)
                } else if let error { Text(verbatim: error).foregroundStyle(.red) }
                else { ProgressView() }
            }.task {
                do {
                    let store = model.configurationLibraryStore
                    let result = try await Task.detached {
                        let payload: ConfigurationSourcePayload
                        if let staged { payload = staged }
                        else {
                            guard let store else { throw ConfigurationLibraryError.unreadable }
                            payload = try store.payload(.init(source))
                        }
                        let document = try OrderedJSON.parse(payload.documentJSON)
                        let nodes: [HakoConfigurationSelectableNode]
                        if case .array(let entries) = document.topLevelValue("proxies") {
                            nodes = entries.compactMap { node in
                                guard let name = node.topLevelValue("name")?.foundationValue as? String else { return nil }
                                return .init(name: name, type: node.topLevelValue("type")?.foundationValue as? String ?? "")
                            }
                        } else { nodes = [] }
                        return (ConfigurationCollection.read(sourceID: source.id, document: document, kind: .nodes), nodes)
                    }.value
                    nodes = result.1
                    collections = result.0
                } catch { self.error = error.localizedDescription }
            }
        }
    }
}

private func updateIssueMessage(_ library: ConfigurationLibrarySnapshot, sourceID: String? = nil, locale: Locale) -> String? {
    let issues = (library.updateIssues ?? []).filter { sourceID == nil || $0.sourceID == sourceID }
    guard !issues.isEmpty else { return nil }
    let names = issues.map { issue in
        library.recipes.first { $0.id == issue.itemID }?.label
            ?? library.sources.first { $0.id == issue.itemID }?.label ?? issue.itemID
    }
    return HakoCopy.string("Some references are unavailable. Previous versions were kept:", locale: locale)
        + " " + names.joined(separator: ", ")
}

struct ConfigurationCollectionAdapter: View {
    let model: ProfilesViewModel
    let entry: ConfigurationCollectionEntry
    let changed: (ConfigurationLibrarySnapshot) -> Void
    let close: () -> Void
    @State private var page = ConfigurationCollectionContentBridge.Page()
    @State private var rows: [HakoConfigurationReadRow] = []
    @State private var query = ""
    @State private var loading = false
    @State private var error: String?
    @State private var management = false
    @State private var editor = false
    @State private var deleting = false
    @State private var inspectedNode: ProxyNodeRecord?
    @State private var requestID = UUID()
    private var status: String {
        var parts = [entry.source.label]
        if let count = page.count { parts.append("\(count) " + (entry.id.kind == .nodes ? "个节点" : "条规则")) }
        if let date = page.updatedAt { parts.append("更新于 " + date.formatted(date: .abbreviated, time: .shortened)) }
        if let message = page.message { parts.append(message) }
        return parts.joined(separator: " · ")
    }
    var body: some View {
        HakoFeatureNavigationContainer {
            HakoConfigurationCollectionContentsView(title: entry.collection.name, rows: rows, query: $query,
                status: status, error: error, loading: loading,
                refresh: entry.collection.type == "http" ? { Task { await load(refresh: true) } } : nil,
                next: page.nextOffset.map { offset in { Task { await load(offset: offset) } } },
                openNode: { index in
                    guard page.nodes.indices.contains(index) else { return }
                    inspectedNode = CustomNodesView.record(fromNodeJSON: page.nodes[index])
                }, manage: { management = true }, close: close,
                details: entry.id.kind == .rules ? { AnyView(identitySections) } : nil,
                actions: entry.id.kind == .rules ? { AnyView(managementActions) } : nil, subscriptionUsage: page.subscriptionUsage)
                .task(id: query) {
                    if !query.isEmpty { try? await Task.sleep(nanoseconds: 180_000_000) }
                    guard !Task.isCancelled else { return }
                    await load()
                }
                .hakoProductModal(item: $inspectedNode, role: .page) { node in
                    ProxyNodeDetailSheet(nodeName: node.name, yaml: nil, providersDir: nil, suppliedDetails: node.protocolDetails)
                }
                .hakoProductModal(isPresented: $management, role: .page) {
                    HakoFeatureNavigationContainer {
                        Form { identitySections; managementActions }
                            .hakoPageTitle(.verbatim(entry.collection.name), watchAs: "Collection Management")
                            .hakoToolbarUnlessInPanel {
                                ToolbarItem(placement: .cancellationAction) { HakoSheetCloseButton(dismiss: { management = false }) }
                            }
                    }
                }
        }
    }
    private var identitySections: some View {
        Group {
            Section("Source") { Text(verbatim: entry.source.label) }
            Section {
                HStack { Text("Name"); Spacer(); Text(verbatim: entry.collection.name) }
                if entry.id.kind == .nodes { HStack { Text("Type"); Spacer(); Text(verbatim: entry.collection.type) } }
                if let location = entry.collection.location { Text(verbatim: location).textSelection(.enabled) }
            }
        }.accessibilityIdentifier("configuration.collection.settings")
    }
    private var managementActions: some View {
        Group {
            if entry.id.kind == .rules {
                Section {
                    Button("Add Rule Scheme") {
                        Task {
                            do {
                                guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
                                let updated = try await Task.detached {
                                    try store.addRuleScheme(collection: entry, expectedGeneration: store.snapshot().generation)
                                }.value
                                changed(updated); close()
                            } catch { self.error = error.localizedDescription; management = false }
                        }
                    }
                }
            }
            Section { Button("Edit Source") { editor = true }.buttonStyle(.plain).foregroundStyle(.primary) }
            Section { Button("Delete Collection", role: .destructive) { deleting = true } }
        }
        .hakoDeleteConfirmation(entry.collection.name, isPresented: $deleting,
            actionTitle: .copy("Delete Collection"),
            message: .copy("Remove this collection from its source. Profiles that reference it must choose another collection first."),
            identifier: "configuration.collection.delete.confirm") {
                Task {
                    do { changed(try await model.saveConfigurationCollection(entry, definitionJSON: nil)); close() }
                    catch { self.error = error.localizedDescription; management = false }
                }
        }
        .hakoProductModal(isPresented: $editor, role: .page) {
            let profile = Profile(id: entry.source.id, label: entry.collection.name, source: .clipboard,
                autoUpdate: false, updateIntervalHours: 0, subscriptionInfo: nil, selectedMap: [:], activeRevision: nil, order: 0, lastUpdatedAt: nil)
            ProfileEditView(profile: profile, rawYAML: entry.collection.definition.serialized(), editorTitle: "Edit Source") { _, text, files, _ in
                guard let text, files.isEmpty else { throw ConfigurationLibraryError.unreadable }
                let json = try ConfigTransforms.yamlToJSON(text)
                changed(try await model.saveConfigurationCollection(entry, definitionJSON: json))
                close()
            }
        }
    }
    private func load(refresh: Bool = false, offset: Int = 0) async {
        if refresh && loading { return }
        let token = UUID(); requestID = token; loading = true; error = nil
        defer { if requestID == token { loading = false } }
        do {
            guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            let source = try await Task.detached { try store.payload(.init(entry.source)) }.value
            if refresh { try await ConfigurationCollectionContentBridge.refresh(entry, source: source) }
            let search = query
            let loaded = try await Task.detached {
                let page = try ConfigurationCollectionContentBridge.page(entry, source: source, query: search, offset: offset)
                let rows: [HakoConfigurationReadRow]
                if entry.id.kind == .nodes {
                    rows = page.nodes.enumerated().map { index, json in
                        let node = try? OrderedJSON.parse(json)
                        return .init(title: node?.topLevelValue("name")?.foundationValue as? String ?? "", subtitle: node?.topLevelValue("type")?.foundationValue as? String, nodeIndex: index)
                    }
                } else { rows = page.lines.map { .init(title: $0) } }
                return (page, rows)
            }.value
            guard requestID == token, !Task.isCancelled else { return }
            page = loaded.0
            if offset == 0 { rows = loaded.1 } else { rows += loaded.1 }
        } catch {
            guard requestID == token else { return }
            self.error = error.localizedDescription
             
        }
    }
}

private struct ConfigurationCollectionImportAdapter: View {
    let model: ProfilesViewModel
    let library: ConfigurationLibrarySnapshot
    var tabHeader: ((Bool) -> AnyView)? = nil
    let changed: (ConfigurationLibrarySnapshot) -> Void
    let close: () -> Void
    @State private var name = ""
    @State private var link = ""
    @State private var behavior = "domain"
    @State private var format = "yaml"
    @State private var fileData: Data?
    @State private var fileName: String?
    @State private var pickingFile = false
    @State private var busy = false
    @State private var error: String?
    private var dirty: Bool { !name.isEmpty || !link.isEmpty || fileData != nil }
    private var missingRequired: Bool { name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (fileData == nil && link.isEmpty) }
    @Environment(\.hakoInsideProductModalPresentation) private var insideProductModal
    var body: some View {
        HakoFeatureNavigationContainer {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("configuration.rules.import.name")
                    TextField("URL", text: $link).autocorrectionDisabled().textInputAutocapitalization(.never)
                        .disabled(fileData != nil)
                        .accessibilityIdentifier("configuration.rules.import.url")
                    Button(fileName ?? "选择集合文件") { pickingFile = true }.buttonStyle(.plain).foregroundStyle(.primary)
                    if fileData != nil { Button("Remove File") { fileData = nil; fileName = nil } }
                }
                Section {
                    Picker("Rule Type", selection: $behavior) {
                        Text("Domain").tag("domain"); Text("IP CIDR").tag("ipcidr"); Text("Classical").tag("classical")
                    }
                    .accessibilityIdentifier("configuration.rules.import.behavior")
                    Picker("Format", selection: $format) {
                        Text("YAML").tag("yaml"); Text("Text").tag("text")
                        if behavior != "classical" { Text("MRS").tag("mrs") }
                    }
                    .accessibilityIdentifier("configuration.rules.import.format")
                }
                if let error { Text(verbatim: error).foregroundStyle(.red) }
            }.disabled(busy)
                .onChange(of: behavior) { if $0 == "classical" && format == "mrs" { format = "yaml" } }
                .safeAreaInset(edge: .top, spacing: 0) { if let tabHeader { tabHeader(dirty).disabled(busy) } }
                .hakoPageTitle(tabHeader == nil ? "添加规则集合" : "Add Rules")
                .hakoToolbarUnlessInPanel {
                    ToolbarItem(placement: .cancellationAction) { HakoSheetCloseButton(dismiss: close) }
                    ToolbarItem(placement: .confirmationAction) { Button { save() } label: { HakoActionProgressLabel(.copy("Save"), isBusy: busy) }.disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (fileData == nil && link.isEmpty)) }
                }
                .hakoRegistersDeparture(isDirty: dirty, isBusy: busy, save: { save($0) }, discard: { name = ""; link = ""; fileData = nil; fileName = nil })
                 
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if insideProductModal {
                        HakoModalActionBar(primaryTitle: "Save", primaryDisabled: missingRequired, isBusy: busy, onPrimary: { save() })
                    }
                }
                .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.data]) { result in
                    do {
                        let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        fileData = try Data(contentsOf: url); fileName = url.lastPathComponent
                        if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
                        if url.pathExtension.lowercased() == "mrs" { format = "mrs" }
                    } catch { self.error = error.localizedDescription }
                }
        }
    }
    private func save(_ completion: @escaping (Bool) -> Void = { _ in }) {
        guard !busy else { completion(false); return }; busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty, !title.contains(",") else { throw ConfigurationLibraryError.emptyName }
                var definition = OrderedJSON.object([("type", .string(fileData == nil ? "http" : "file")), ("behavior", .string(behavior)), ("format", .string(format))])
                if let fileName { definition = definition.settingTopLevel("path", to: .string(fileName)) }
                else {
                    guard let url = URL(string: link), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { throw ConfigurationLibraryError.unreadable }
                    definition = definition.settingTopLevel("url", to: .string(link)).settingTopLevel("interval", to: .scalar("86400"))
                }
                let document = OrderedJSON.object([("rule-providers", .object([(title, definition)]))])
                try ConfigTransforms.validateSource(document.serialized())
                var record = ConfigurationSourceRecord(label: title, origin: .file(title + ".yaml"), suppliesNodes: false)
                record.registersSuppliedRules = false; record.ruleProviderCount = 1
                let payload = ConfigurationSourcePayload(record: record, original: Data(document.serialized().utf8), documentJSON: document.serialized(),
                    resourceFiles: fileName.flatMap { name in fileData.map { [name: $0] } })
                changed(try await model.addConfigurationSource(payload, generation: library.generation)); completion(true); close()
            } catch { self.error = error.localizedDescription; completion(false) }
        }
    }
}


 
enum ConfigurationCompletionPreview {
    static func sections(draft: ConfigurationCreationDraft, library: ConfigurationLibraryStore,
                         generation: UInt64, nodes: Bool) throws -> [HakoConfigurationReadSection] {
        let prepared = try library.prepare(draft, profileID: "completion-preview", expectedGeneration: generation,
            resolveInput: ConfigurationCenterSourceBridge.boundInput)
        let document = prepared.composition.document
        if !nodes {
            func ruleRow(_ value: OrderedJSON) -> HakoConfigurationReadRow {
                let raw = value.foundationValue as? String ?? value.serialized()
                let parsed = HakoStructuredRule.parse(raw)
                return .init(title: raw, rule: .init(raw: raw, type: parsed?.action.rawValue ?? "RAW",
                    payload: parsed?.content ?? raw, target: parsed?.target ?? ""))
            }
            var sections: [HakoConfigurationReadSection] = []
            if case .array(let values) = document.topLevelValue("rules") {
                sections.append(.init(title: "Rules", rows: values.map(ruleRow)))
            }
            if case .object(let groups) = document.topLevelValue("sub-rules") {
                for group in groups {
                    if case .array(let values) = group.value {
                        sections.append(.init(title: group.key, rows: values.map(ruleRow)))
                    }
                }
            }
            return sections
        }
        var index = 0
        func row(_ node: OrderedJSON) -> HakoConfigurationReadRow {
            defer { index += 1 }
            return .init(title: node.topLevelValue("name")?.foundationValue as? String ?? String(index + 1),
                subtitle: node.topLevelValue("type")?.foundationValue as? String,
                content: node.serialized(), nodeIndex: index,
                chainedThrough: node.topLevelValue("dialer-proxy")?.foundationValue as? String)
        }
        var sections: [HakoConfigurationReadSection] = []
        if case .array(let values) = document.topLevelValue("proxies"), !values.isEmpty {
            sections.append(.init(title: "Nodes", rows: values.map(row)))
        }
        let references = prepared.recipe.sources
        let payloads = try references.map { reference in
            try prepared.payloads.first(where: { $0.record.id == reference.id }) ?? library.payload(reference)
        }
         
         
        let parents = try payloads.flatMap { payload -> [(ConfigurationSourcePayload, ConfigurationCollection, ConfigurationCollection)] in
            let original = ConfigurationCollection.read(sourceID: payload.record.id,
                document: try OrderedJSON.parse(payload.documentJSON), kind: .nodes)
            let bound = ConfigurationCollection.read(sourceID: payload.record.id,
                document: try ConfigurationCenterSourceBridge.boundInput(payload).document, kind: .nodes)
            return original.compactMap { collection in
                bound.first(where: { $0.name == collection.name }).map { (payload, collection, $0) }
            }
        }
        for collection in ConfigurationCollection.read(sourceID: "completion-preview", document: document, kind: .nodes) {
            guard let parent = parents.first(where: {
                $0.2.type == collection.type && (collection.type == "inline"
                    ? $0.2.definition.topLevelValue("payload") == collection.definition.topLevelValue("payload")
                    : $0.2.location == collection.location)
            }) else {
                sections.append(.init(title: collection.name, rows: [.init(title: collection.name + " · 尚未加载")]))
                continue
            }
            do {
                let page = try ConfigurationCollectionContentBridge.page(.init(source: parent.0.record, collection: parent.1),
                    source: parent.0, query: "")
                var rows = try page.nodes.map { row(try OrderedJSON.parse($0)) }
                if let message = page.message { rows.append(.init(title: collection.name + " · " + message)) }
                sections.append(.init(title: collection.name, rows: rows))
            } catch {
                sections.append(.init(title: collection.name, rows: [.init(title: error.localizedDescription)]))
            }
        }
        return sections
    }
}


struct ConfigurationCompletionContentsAdapter: View {
    let draft: ConfigurationCreationDraft
    let library: ConfigurationLibraryStore?
    let generation: UInt64
    let nodes: Bool
    @State private var sections: [HakoConfigurationReadSection] = []
    @State private var loading = true
    @State private var failure: String?
    @State private var inspectedNode: ProxyNodeRecord?
    @Environment(\.locale) private var locale

    var body: some View {
        HakoConfigurationContentsView(title: HakoCopy.string(nodes ? "Nodes" : "Rules", locale: locale),
            sections: sections, loading: loading, error: failure, reload: { Task { await load() } },
            close: {}, showsClose: false, openNode: nodes ? inspect : nil,
            searchPrompt: nodes ? "Search Nodes" : "Search Rules", palette: .hakoProduct)
        .task { await load() }
        .hakoProductModal(item: $inspectedNode, role: .page) { node in
            ProxyNodeDetailSheet(nodeName: node.name, yaml: nil, providersDir: nil, suppliedDetails: node.protocolDetails)
        }
    }
    private func inspect(_ index: Int) {
        guard let json = sections.flatMap(\.rows).first(where: { $0.nodeIndex == index })?.content,
              let node = CustomNodesView.record(fromNodeJSON: json) else { return }
        inspectedNode = node
    }
    private func load() async {
        loading = true; failure = nil
        defer { loading = false }
        do {
            guard let library else { throw ConfigurationLibraryError.unreadable }
            let value = draft, revision = generation, showNodes = nodes
            let result = try await Task.detached(priority: .userInitiated) {
                try ConfigurationCompletionPreview.sections(draft: value, library: library, generation: revision, nodes: showNodes)
            }.value
            guard !Task.isCancelled else { return }
            sections = result
        } catch { failure = error.localizedDescription }
    }
}

extension ConfigurationCreationAdapter {
     
     
    static func editingDraft(recipe: ConfigurationRecipe, label: String, selectedRuleID: String? = nil) -> ConfigurationCreationDraft {
        var draft = ConfigurationCreationDraft()
        draft.selectedSourceIDs = recipe.sources.map(\.id)
        draft.nodeScopes = recipe.nodeScopes
        draft.selectedRuleID = selectedRuleID ?? recipe.ruleSchemeID
        draft.label = label
        draft.dnsMode = recipe.dnsMode ?? .source
        draft.nodeNameservers = recipe.nodeNameservers
        draft.customDNSJSON = recipe.customDNSJSON
        return draft
    }
}

 
 
 
 
 
enum QuickRulePlan: Equatable {
    case reuse(String)
    case copy(base: String)

    static func make(activeSchemeID: String?, schemes: [ConfigurationRuleScheme], myRulesLabel: String) -> QuickRulePlan {
        if let activeSchemeID, schemes.contains(where: { $0.id == activeSchemeID && $0.kind == .custom }) {
            return .reuse(activeSchemeID)
        }
        if let mine = schemes.first(where: { $0.kind == .custom && $0.label == myRulesLabel }) {
            return .reuse(mine.id)
        }
        return .copy(base: activeSchemeID ?? ConfigurationBuiltins.basicRuleID)
    }
}
