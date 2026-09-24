import HakoClientKit
import HakoClientUI
import SwiftUI
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

 
 
 
 
 
struct ProfileCenterAdapter: View {
     
     
    @Environment(\.locale)
    private var locale
    @Environment(\.hakoShellLayout) private var shellLayout
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @ObservedObject private var importRouter: ProfileImportRouter
     
     
     
     
     
     
    @ObservedObject private var model: ProfilesViewModel

    private let initialDestination: AppNavigationDestination
    private let onActiveRuntimeChanged: () -> Void

     
     
     
     
     
     
    private var activeFailure: ProfileSwitchAlertFailure? {
        model.lastFailure.map { ProfileSwitchAlertFailure($0) }
    }
    @State private var exportDocument: ConfigTextDocument?
    @State private var exportName = ""
    @State private var centerDismiss = HakoDismissHandle()
    @State private var adaptationNoticeCounts: [String: Int] = [:]
    @State private var composedProfileIDs: Set<String> = []
    @State private var configurationLibrary = ConfigurationLibrarySnapshot()
    @State private var libraryBrowseCache: ConfigurationLibraryBrowseCache?

     
     
    private let ownsNavigationContainer: Bool

    private let palette: HakoClientUI.HakoProductPalette

     
     
    private let listPresentation:
        ((HakoClientUI.HakoProfilesListPresentation) -> AnyView)?
     
    private let capabilityInterceptor:
        ((HakoClientUI.HakoProfilesCapabilityDestination) -> Bool)?

    init(
        profiles: ProfilesViewModel,
        importRouter: ProfileImportRouter,
        initialDestination: AppNavigationDestination = .profiles,
        ownsNavigationContainer: Bool = true,
         
         
         
         
        palette: HakoClientUI.HakoProductPalette = .hakoProduct,
        onActiveRuntimeChanged: @escaping () -> Void = {},
        capabilityInterceptor: (
            (HakoClientUI.HakoProfilesCapabilityDestination) -> Bool
        )? = nil,
        listPresentation: (
            (HakoClientUI.HakoProfilesListPresentation) -> AnyView
        )? = nil
    ) {
        self.ownsNavigationContainer = ownsNavigationContainer
        self.importRouter = importRouter
        self.initialDestination = initialDestination
        self.palette = palette
        self.onActiveRuntimeChanged = onActiveRuntimeChanged
        self.listPresentation = listPresentation
        self.capabilityInterceptor = capabilityInterceptor
        _model = ObservedObject(wrappedValue: profiles)
    }

    var body: some View {
        let _ = HakoPerf.count("center.body")
        HakoOptionalNavigationContainer(owns: ownsNavigationContainer) {
#if os(iOS)
            HakoConfigurationCenterSections {
                profilesPage
            } nodes: {
                ConfigurationSourceLibraryAdapter(model: model, library: configurationLibrary,
                    changed: applyCenterLibrary, close: { centerDismiss() },
                    embedded: true, showsClose: ownsNavigationContainer, browseCache: $libraryBrowseCache)
            } rules: {
                ConfigurationRuleLibraryAdapter(model: model, library: configurationLibrary,
                    changed: applyCenterLibrary, close: { centerDismiss() },
                    embedded: true, showsClose: ownsNavigationContainer, browseCache: $libraryBrowseCache)
            }
#else
            profilesPage
#endif
        }
        .hakoCapturesDismiss(centerDismiss)
        .alert(
            isPresented: Binding(
                get: { activeFailure != nil },
                set: { if !$0 { model.dismissFailure() } }
            ),
            error: activeFailure
        ) { _ in
             
             
             
            if model.lastFailure?.recoveryActions.contains(.retry) == true {
                Button("Try Again") { model.retryLastFailure() }
            }
            Button("OK", role: .cancel) { model.dismissFailure() }
        } message: { failure in
            Text(verbatim: failure.messageText)
        }
        .onAppear {
            model.load()
            model.selectSoleProfileIfNeeded()
            importRouter.importSharedFiles()
        }
        .onReceive(
            importRouter.$pendingImport.compactMap { $0 }
        ) { _ in
             
             
            if let request = importRouter.take() { consume(request) }
        }
        .onReceive(model.$profiles) { _ in
             
             
             
             
             
             
            Task { @MainActor in
                guard let store = model.configurationLibraryStore else { return }
                if let snapshot = try? await Task.detached(operation: { try store.snapshot() }).value {
                    guard snapshot.generation >= configurationLibrary.generation else { return }
                    let composed = Set(snapshot.recipes.filter { $0.preservesOriginal != true }.map(\.id))
                    if composed != composedProfileIDs { composedProfileIDs = composed }
                    if snapshot != configurationLibrary { configurationLibrary = snapshot }
                }
            }
        }
        .task(id: activeRevisionKey) {
            await loadAdaptationNoticeCount()
        }
    }

     
     
    private func rereadCentreLibrary() async {
        guard let store = model.configurationLibraryStore,
              let updated = try? await Task.detached(operation: { try store.snapshot() }).value,
              updated.generation >= configurationLibrary.generation else { return }
        applyCenterLibrary(updated)
    }

     
     
     
     
     
     
     
    private func librarySubscriptionFacts(for profile: Profile) -> ProfileSubscriptionSettingsAdapter.LibraryFacts? {
        guard let recipe = configurationLibrary.recipes.first(where: { $0.id == profile.id }),
              recipe.sources.count == 1, let reference = recipe.sources.first,
              let record = configurationLibrary.sources.first(where: { $0.id == reference.id }),
              case .subscription = record.origin else { return nil }
        return .init(intervalHours: record.updateIntervalHours ?? 0)
    }

    private func applyCenterLibrary(_ snapshot: ConfigurationLibrarySnapshot) {
        configurationLibrary = snapshot
        composedProfileIDs = Set(snapshot.recipes.filter { $0.preservesOriginal != true }.map(\.id))
    }

    private var usesConfigurationSections: Bool {
#if os(iOS)
        true
#else
        false
#endif
    }

    private var profilesPage: some View {
            HakoClientUI.HakoProfilesView(
                snapshot: sharedSnapshot,
                actions: sharedActions,
                initialProfileID: initialProfileID,
                opensImportInitially: opensImportInitially,
                presentationClass:
                    shellLayout == .regularSidebar
                        ? .regularTouch
                        : .compactTouch,
                showsDismissControl: ownsNavigationContainer,
                isCenterSection: usesConfigurationSections,
                palette: productPalette,
                pagePresentation: { content in
                    AnyView(
            content
                    )
                },
                 
                 
                 
                 
                detailPresentation: { content in
                    AnyView(
                        content.fileExporter(
                            isPresented: Binding(
                                get: { exportDocument != nil },
                                set: { presented in
                                    if !presented {
                                        exportDocument = nil
                                    }
                                }
                            ),
                            document: exportDocument,
                            contentType: .yaml,
                            defaultFilename: exportName
                        ) { _ in
                            exportDocument = nil
                        }
                    )
                },
                listPresentation: listPresentation,
                capabilityInterceptor: capabilityInterceptor,
                icon: { symbol in
                    HakoSymbolImage(symbol: symbol)
                },
                capabilityContent: { destination in
                    capabilityView(destination)
                }
            )
    }

    private var initialProfileID: HakoClientKit.Profile.ID? {
        guard case .profileDetail(let rawID) = initialDestination else {
            return nil
        }
        return try? HakoClientKit.Profile.ID(rawID)
    }

    private var opensImportInitially: Bool {
        initialDestination == .profileImport
    }

    private var productPalette: HakoClientUI.HakoProductPalette {
        palette
    }

    private var catalogProfiles: [Profile] {
        model.profiles.filter { profile in
            profile.id != LocalDefaultProfileProvisioner.profileID || initialProfileID?.rawValue == profile.id
        }
    }

    private var sharedSnapshot: AppleClientSnapshot {
         
         
         
        HakoPerf.measure("profiles.snapshot") { buildSharedSnapshot() }
    }

    private func buildSharedSnapshot() -> AppleClientSnapshot {
        let scripts = catalogProfiles.contains { $0.overwriteMode == .script } ? ScriptLibrary.load() : []
        return AppleClientSnapshot(
            revision: 0,
            connection: AppleClientConnectionSnapshot(
                phase: .unavailable
            ),
            profiles: HakoProfilesSnapshot(
                 
                 
                 
                profiles: catalogProfiles.compactMap { profileSnapshot($0, scripts: scripts) },
                 
                 
                 
                 
                 
                 
                 
                 
                 
                failure: nil,
                statusMessage: model.statusMessage,
                batchReport: model.batchReport.map(batchSnapshot),
                libraryHasFetchableSource: model.libraryHasFetchableSource
            ),
            capabilities: AppleClientCapabilities([
                .profiles: .available,
            ])
        )
    }

    private var sharedActions: AppleClientActions {
        AppleClientActions(
            resultCapability: .profiles
        ) { action in
            guard case .profiles(let command) = action else {
                return .none
            }
            return try await handle(command)
        }
    }

     
     
     
     
     
     
    struct LibraryProfileFacts: Equatable {
        var lastUpdatedAt: Date?
        var usage: ConfigurationSubscriptionUsage?
    }

    static func libraryFacts(for profile: Profile, in library: ConfigurationLibrarySnapshot) -> LibraryProfileFacts? {
        guard let recipe = library.recipes.first(where: { $0.id == profile.id }) else { return nil }
        let links = recipe.sources.compactMap { reference in
            library.sources.first { record in
                guard record.id == reference.id, case .subscription = record.origin else { return false }
                return true
            }
        }
        return LibraryProfileFacts(lastUpdatedAt: links.map(\.updatedAt).max(),
                                   usage: recipe.sources.count == 1 && links.count == 1 ? links[0].subscriptionUsage : nil)
    }

    private static func subscriptionSnapshot(upload: Int64, download: Int64, total: Int64, expire: Int64) -> HakoProfileSubscriptionSnapshot {
        HakoProfileSubscriptionSnapshot(
            uploadBytes: upload, downloadBytes: download, totalBytes: total,
            expiration: expire > 0 ? Date(timeIntervalSince1970: TimeInterval(expire)) : nil)
    }

    private func profileSnapshot(
        _ profile: Profile, scripts: [ConfigScript]
    ) -> HakoProfileSnapshot? {
        guard let id = try? HakoClientKit.Profile.ID(profile.id) else {
            return nil
        }
        let isCurrent = profile.id == model.activeProfileID
        let libraryFacts = Self.libraryFacts(for: profile, in: configurationLibrary)
        let canDelete = ProfileCenterPolicy.canDelete(
            profileID: profile.id,
            activeProfileID: model.activeProfileID
        )

        return HakoProfileSnapshot(
            id: id,
            label: profile.label,
            source: sourceKind(profile.source),
            sourceSummary: sourceSummary(profile),
            subscription: libraryFacts != nil
                ? libraryFacts?.usage.map { Self.subscriptionSnapshot(upload: $0.upload, download: $0.download, total: $0.total, expire: $0.expire) }
                : profile.subscriptionInfo.map { Self.subscriptionSnapshot(upload: $0.upload, download: $0.download, total: $0.total, expire: $0.expire) },
            lastUpdatedAt: libraryFacts != nil ? libraryFacts?.lastUpdatedAt : profile.lastUpdatedAt,
            autoUpdate: profile.autoUpdate,
            updateIntervalHours: profile.updateIntervalHours,
            isCurrent: isCurrent,
            isBusy: profile.id == model.busyProfileID,
            canEditSource: profile.id != LocalDefaultProfileProvisioner.profileID && model.hasEditableSource(for: profile),
            canDelete: canDelete,
            deleteSubtitle: deleteSubtitle(
                profile,
                canDelete: canDelete
            ),
            runtimeSummary: runtimeSummary(profile),
            requiresPlaintextExportConfirmation:
                profile.externalResources?.isEmpty == false,
            featureAvailability: featureAvailability(profile),
            heldBackUpdates: (profile.suppressedUpdates ?? []).map {
                HakoProfileHeldBackUpdate(
                    keyPath: $0.keyPath,
                    change: HakoProfileHeldBackUpdate.Change(rawValue: $0.change.rawValue) ?? .changed,
                    newValue: $0.newValue,
                    appValue: $0.appValue
                )
            },
            isComposed: composedProfileIDs.contains(profile.id),
             
             
             
             
             
            canUseOriginalConfiguration: configurationLibrary.recipes
                .first(where: { $0.id == profile.id })
                .map { $0.sources.count == 1 }
                ?? (profile.id != LocalDefaultProfileProvisioner.profileID),
            configurationSourceNames: configurationLibrary.recipes.first(where: { $0.id == profile.id }).map { recipe in
                recipe.sources.map { pin in configurationLibrary.sources.first(where: { $0.id == pin.id })?.label ?? pin.id }
            },
            configurationRuleName: configurationLibrary.recipes.first(where: { $0.id == profile.id }).flatMap { recipe in
                (configurationLibrary.rules + ConfigurationBuiltins.schemes).first(where: { $0.id == recipe.ruleSchemeID })?.displayLabel
            },
            followsConfigurationSourceUpdates: configurationLibrary.recipes.first(where: { $0.id == profile.id })?.followsUpdates,
            overrideScriptName: profile.overwriteMode == .script
                ? scripts.first { $0.id == profile.selectedScriptID }?.label : nil,
            customRulesCount: profile.override.appendRules.count
        )
    }

     
     
     
     
     
     
     
    private func featureAvailability(
        _ profile: Profile
    ) -> HakoProfileFeatureAvailabilitySnapshot {
        let isRemote: Bool
        if case .url = profile.source {
            isRemote = true
        } else {
            isRemote = false
        }
        return HakoProfileFeatureAvailabilitySnapshot(
            canSync: isRemote,
            canConfigureSubscription: isRemote,
            canCopySubscriptionLink: isRemote,
            canExport: model.hasEditableSource(for: profile),
            canOpenRuntimePreview: true
        )
    }

    private func sourceKind(
        _ source: Profile.Source
    ) -> HakoProfileSourceKind {
        switch source {
        case .url:
            .remote
        case .file:
            .file
        case .clipboard:
            .clipboard
        }
    }

    private func sourceSummary(_ profile: Profile) -> HakoDisplayText {
        switch profile.source {
        case .url(let rawURL):
            let host = SubscriptionURLPresentation.hostDescription(
                rawURL,
                locale: locale
            )
            if let updated = profile.lastUpdatedAt {
                return .verbatim(
                    "\(host) · \(updated.formatted(.relative(presentation: .named)))"
                )
            }
            return .verbatim(host)
        case .file:
            return "Local · Imported file"
        case .clipboard:
            return "Local · Manually managed"
        }
    }

    private func deleteSubtitle(
        _ profile: Profile,
        canDelete: Bool
    ) -> HakoDisplayText {
        if profile.id == LocalDefaultProfileProvisioner.profileID {
            return "Clash keeps Direct as a safe system fallback"
        }
        return canDelete
            ? "Remove this profile from Clash"
            : "Switch to another profile before deleting"
    }

    private func runtimeSummary(_ profile: Profile) -> HakoDisplayText {
        if profile.id == model.activeProfileID,
           let count = adaptationNoticeCounts[profile.id],
           let summary = ProfileAdaptationPresenter.summary(
               noticesCount: count,
               locale: locale
           ) {
             
             
             
            return .verbatim(
                summary + " · " + HakoCopy.string("read-only", locale: locale)
            )
        }
        return "read-only"
    }

    private func batchSnapshot(
        _ report: BatchUpdateReport
    ) -> HakoProfileBatchReportSnapshot {
        HakoProfileBatchReportSnapshot(
            id: report.id,
            title: report.title,
            expectedCount: report.expectedCount,
            items: report.items.compactMap { item in
                guard let id = try? HakoClientKit.Profile.ID(
                    item.id
                ) else {
                    return nil
                }
                return HakoProfileBatchItemSnapshot(
                    id: id,
                    label: item.label,
                    state: batchState(item.state),
                    message:
                        item.failure?.message
                        ?? item.message
                        ?? item.state.title,
                    diagnosticCode:
                        item.failure?.diagnosticCode
                )
            },
            wasCancelled: report.wasCancelled,
            isRunning: model.isBatchSyncing
        )
    }

    private func batchState(
        _ state: BatchUpdateState
    ) -> HakoProfileBatchUpdateState {
        switch state {
        case .updated:
            .updated
        case .unchanged:
            .unchanged
        case .failed:
            .failed
        }
    }

    private func legacyImportView(onSaved: @escaping () -> Void) -> some View {
        AddProfileView(createEmpty: { Task { _ = try? await handle(.createEmpty); onSaved() } }) { label, source, rawYAML, resources in
            model.add(label:label,source:source,rawYAML:rawYAML,resourceFiles:resources)
            model.selectSoleProfileIfNeeded()
            onSaved()
        }
    }

    @ViewBuilder
    private func capabilityView(
        _ destination: HakoProfilesCapabilityDestination
    ) -> some View {
        switch destination {
        case .importProfile:
#if os(iOS)
            ConfigurationCreationAdapter(model: model)
#else
            legacyImportView(onSaved:{})
#endif
        case .backupRestore:
            BackupRestoreView()
        case .subscriptionSettings(let id):
            if let profile = appProfile(id) {
                ProfileSubscriptionSettingsAdapter(
                    profile: profile,
                    model: model,
                    library: librarySubscriptionFacts(for: profile)
                )
            } else {
                EmptyView()
            }
        case .rules(let id):
            if let profile = appProfile(id) {
                 
                 
                 
                 
                 
                 
                ProfileProjectionLoader(profile: profile, model: model) { projected in
                    ProfileRulesAdapter(
                        profile: profile,
                        sourceYAML: projected
                    ) { draft in
                        try model.updateRules(draft)
                    }
                }
            } else {
                EmptyView()
            }
        case .override(let id):
            if let profile = appProfile(id) {
                 
                 
                 
                ProfileOverrideView(profile: profile, rawYAML: model.cachedUIProjectedYAML(for: profile),
                    configurationCenter: true, loadRawYAML: { await model.loadUIProjectedYAML(for: profile) }) { model.update($0) }
            } else {
                EmptyView()
            }
        case .network(let id):
            if let profile = appProfile(id) {
                ProfileNetworkSettingsView(profile: profile, sourceYAML: model.baseYAML(for: profile)) { draft in
                    try model.updateNetwork(draft)
                }
            } else {
                EmptyView()
            }
        case .trust(let id):
            if let profile = appProfile(id) {
                ProfileTrustPage(profile: profile, sourceYAML: model.sourceYAML(for: profile),
                    patchJSON: profile.override.patchJSON) { patchJSON in
                    var draft = ProfileAdvancedOverridesDraft(profile: profile)
                    draft.rawPatchJSON = patchJSON
                    try model.updateAdvancedOverrides(draft)
                }
            } else {
                EmptyView()
            }
        case .configurationSources(let id):
            ConfigurationCreationAdapter(model: model, changed: applyCenterLibrary,
                editingProfileID: id.rawValue, editingStep: .sources)
        case .configurationRules(let id):
            ConfigurationCreationAdapter(model: model, changed: applyCenterLibrary,
                editingProfileID: id.rawValue, editingStep: .rules)
        case .sourceEditor(let id):
            if let profile = appProfile(id) {
                 
                 
                 
                 
                 
                 
                 
                ProfileSourceEditorLoader(profile: profile, model: model,
                    savesIndependentSource: composedProfileIDs.contains(profile.id))
            } else {
                EmptyView()
            }
        case .runtimePreview(let id):
            if let profile = appProfile(id) {
                ProfilePreviewView(title: .verbatim(profile.label), load: {
                     
                     
                     
                     
                    try await model.loadSavedConfigurationPreview(for: profile.id)
                })
            } else {
                EmptyView()
            }
        }
    }

    private func appProfile(
        _ id: HakoClientKit.Profile.ID
    ) -> Profile? {
        model.profiles.first { $0.id == id.rawValue }
    }

    private func handle(
        _ command: HakoProfilesCommand
    ) async throws -> AppleClientActionResult {
        switch command {
        case .createEmpty:
            guard let profile = model.addDirectProfile(),
                  let id = try? HakoClientKit.Profile.ID(
                      profile.id
                  ) else {
                return .none
            }
            model.selectSoleProfileIfNeeded()
            return .profileCreated(id: id)

        case .openImport, .openBackup, .openSourceEditor,
             .openRuntimePreview, .restoreLastKnownGood:
            return .none

        case .syncAll:
            model.syncAll()
            return .none

        case .select(let id):
            guard let profile = appProfile(id) else {
                return .none
            }
             
             
             
             
             
            let succeeded = await model.selectAndWait(profile)
            guard !Task.isCancelled else {
                throw CancellationError()
            }
            if succeeded {
                onActiveRuntimeChanged()
#if canImport(UIKit)
                UINotificationFeedbackGenerator()
                    .notificationOccurred(.success)
#endif
                return .profileSelected(id: id)
            }
            if model.lastFailure != nil {
                 
                 
                 
                return .profileSelectionFailurePresented
            }
            return .none

        case .reorder(let ids):
            applyOrder(ids)
            return .none

        case .sync(let id):
            if let profile = appProfile(id) {
                model.sync(profile)
            }
            return .none
        case let .adoptHeldBackUpdate(id, keyPath):
            if let profile = appProfile(id) {
                try model.adoptHeldBackUpdate(profile, keyPath: keyPath)
                onActiveRuntimeChanged()
            }
            return .none
        case .dismissHeldBackUpdates(let id):
            if let profile = appProfile(id) {
                try model.dismissHeldBackUpdates(profile)
            }
            return .none

        case let .setConfigurationSourceUpdates(id, enabled):
            try await model.setConfigurationSourceUpdates(id.rawValue, enabled: enabled)
            await rereadCentreLibrary()
            return .none

        case let .setUsesOriginalConfiguration(id, enabled):
            try await model.setUsesOriginalConfiguration(id.rawValue, enabled: enabled)
            await rereadCentreLibrary()
            return .none

        case let .rename(id, label):
            guard let profile = appProfile(id) else {
                return .none
            }
            try model.updateMetadata(
                profile,
                label: label,
                subscriptionURL: subscriptionURL(profile),
                autoUpdate: profile.autoUpdate,
                updateIntervalHours: profile.updateIntervalHours
            )
            return .none

        case let .saveSubscription(
            id,
            url,
            autoUpdate,
            intervalHours
        ):
            guard let profile = appProfile(id) else {
                return .none
            }
            try model.updateMetadata(
                profile,
                label: profile.label,
                subscriptionURL: url,
                autoUpdate: autoUpdate,
                updateIntervalHours: intervalHours
            )
            return .none

        case .copySubscriptionLink(let id):
            if let profile = appProfile(id) {
#if os(macOS)
                if let link = model.subscriptionLink(for: profile) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        link,
                        forType: .string
                    )
                }
#else
                UIPasteboard.general.string =
                    model.subscriptionLink(for: profile)
#endif
            }
            return .none

        case .duplicate(let id):
             
             
             
             
            guard let profile = appProfile(id) else { return .none }
            guard let copy = await model.duplicate(profile),
                  let copyID = try? HakoClientKit.Profile.ID(copy.id)
            else {
                 
                 
                 
                return .profileActionRefused(reason: model.statusMessage)
            }
            return .profileCreated(id: copyID)

        case .export(let id):
            guard let profile = appProfile(id) else {
                return .none
            }
            guard let (name, text) =
                await model.loadCachedExportDocument(
                    for: profile.id
                ) else {
#if os(macOS)
                presentMacExportUnavailableAlert()
#endif
                return .none
            }
#if os(macOS)
            presentMacExportPanel(
                defaultFilename: name,
                text: text
            )
#else
            exportName = name
            exportDocument = ConfigTextDocument(text: text)
#endif
            return .none

        case .delete(let id):
            guard let profile = appProfile(id) else {
                return .none
            }
            model.delete(profile)
            return model.profiles.contains {
                $0.id == id.rawValue
            }
                ? .profileActionRefused(reason: model.statusMessage)
                : .profileDeleted(id: id)

        case .retryFailure:
            model.retryLastFailure()
            return .none

        case .cancelBatch:
            model.cancelBatchSync()
            return .none

        case .retryBatchItem(let id):
            model.retryBatchItem(id: id.rawValue)
            return .none

        case .dismissBatch:
            model.dismissBatchReport()
            return .none
        }
    }

#if os(macOS)
     
     
     
    private func presentMacExportUnavailableAlert() {
        let alert = NSAlert()
        alert.messageText = HakoCopy.string(
            "No Local Copy",
            locale: locale
        )
        alert.informativeText = HakoCopy.string(
            "Sync or import this profile to keep a copy on this device.",
            locale: locale
        )
        alert.addButton(
            withTitle: HakoCopy.string("Done", locale: locale)
        )
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

     
     
     
     
    private func presentMacExportPanel(
        defaultFilename: String,
        text: String
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.yaml]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = defaultFilename

        let completion: (NSApplication.ModalResponse) -> Void = {
            response in
            guard response == .OK, let destination = panel.url else {
                return
            }
            try? text.write(
                to: destination,
                atomically: true,
                encoding: .utf8
            )
        }

        if let window = NSApp.keyWindow {
            panel.beginSheetModal(
                for: window,
                completionHandler: completion
            )
        } else {
            panel.begin(completionHandler: completion)
        }
    }
#endif

    private func applyOrder(
        _ desiredIDs: [HakoClientKit.Profile.ID]
    ) {
        let visible = desiredIDs.map(\.rawValue)
        guard visible.count == catalogProfiles.count,
              Set(visible) == Set(catalogProfiles.map(\.id)) else { return }
         
        let desired = visible + model.profiles.filter { !visible.contains($0.id) }.map(\.id)

        for targetIndex in desired.indices {
            guard let currentIndex = model.profiles.firstIndex(
                where: { $0.id == desired[targetIndex] }
            ), currentIndex != targetIndex else {
                continue
            }
            model.move(
                from: IndexSet(integer: currentIndex),
                to:
                    currentIndex < targetIndex
                        ? targetIndex + 1
                        : targetIndex
            )
        }
    }

    private func subscriptionURL(_ profile: Profile) -> String? {
        if case .url(let url) = profile.source {
            return url
        }
        return nil
    }

    private func consume(_ request: ProfileImportRequest) {
        switch request {
        case .subscription(let subscription):
            model.installSubscription(subscription)
        case let .configuration(fileName, yaml):
            let label = URL(fileURLWithPath: fileName)
                .deletingPathExtension()
                .lastPathComponent
            model.add(
                label:
                    label.isEmpty
                        ? "Imported Profile"
                        : label,
                source: .file(fileName),
                rawYAML: yaml
            )
        }
        model.selectSoleProfileIfNeeded()
    }

    private var activeRevisionKey: String {
        guard let activeID = model.activeProfileID,
              let revision = model.profiles.first(
                  where: { $0.id == activeID }
              )?.activeRevision else {
            return ""
        }
        return "\(activeID)|\(revision)"
    }

    private func loadAdaptationNoticeCount() async {
        guard let activeID = model.activeProfileID,
              model.profiles.first(
                  where: { $0.id == activeID }
              )?.activeRevision != nil,
              let container = HakoAppIdentifiers.appGroupContainer else {
            if !adaptationNoticeCounts.isEmpty { adaptationNoticeCounts = [:] }
            return
        }

        let count = await Task.detached(
            priority: .utility
        ) { () -> Int in
            guard let store = try? ConfigResourceStore(
                containerURL: container
            ),
                let activeYAML = try? store.loadCurrent().text
            else {
                return 0
            }
            return (
                try? ConfigTransforms.planResources(
                    mergedYAML: activeYAML
                ).notices.count
            ) ?? 0
        }.value
        if adaptationNoticeCounts != [activeID: count] { adaptationNoticeCounts = [activeID: count] }
    }
}

 
 
typealias ProfileCenterView = ProfileCenterAdapter

 
enum ProfileAdaptationPresenter {
    static func summary(noticesCount: Int, locale: Locale) -> String? {
        guard noticesCount > 0 else {
            return nil
        }
        return HakoCopy.format(
            "%d items adapted automatically",
            locale: locale,
            noticesCount
        )
    }
}

 
 
 
private struct ProfileSubscriptionSettingsAdapter: View {
     
     
     
     
     
    struct LibraryFacts: Equatable {
         
        var intervalHours: Int
    }

    let profile: Profile
    @ObservedObject var model: ProfilesViewModel
     
     
     
     
     
     
    let library: LibraryFacts?

     
     
     
     
     
     
    @State private var dismiss = HakoDismissHandle()
    @Environment(\.hakoProductModalDismiss)
    private var productModalDismiss
    @Environment(\.hakoInsideProductModalPresentation)
    private var insideProductModal
    @State private var subscriptionURL: String
    @State private var autoUpdate: Bool
    @State private var updateIntervalHours: Int
    @State private var errorMessage = ""
    @State private var confirmsCredentialRemoval = false
     
     
     
    @State private var openedWith: (url: String, auto: Bool, hours: Int)?

    init(profile: Profile, model: ProfilesViewModel, library: LibraryFacts? = nil) {
        self.profile = profile
        self.model = model
        self.library = library
        if case .url(let url) = profile.source {
             
             
             
            _subscriptionURL = State(
                initialValue: ProfileImportRouter.confirmationText(for: url)
            )
        } else {
            _subscriptionURL = State(initialValue: "")
        }
        _autoUpdate = State(initialValue: profile.autoUpdate)
        _updateIntervalHours = State(
            initialValue: profile.updateIntervalHours
        )
    }

    var body: some View {
        HakoFeatureNavigationContainer {
            Form {
                if let library {
                     
                     
                     
                     
                     
                     
                     
                    Section {
                        Text(verbatim: subscriptionURL)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("profile-metadata.url")
                        HStack {
                            Text("Update Interval")
                            Spacer()
                            if library.intervalHours > 0 {
                                Text(hako: .format("Every %@ hours", [String(library.intervalHours)]))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Manually").foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("profile-metadata.interval")
                    } header: {
                        Text("Profile URL")
                    }
                } else {
                Section {
                     
                     
                     
                     
                     
                    TextField(
                        "",
                        text: $subscriptionURL,
                        prompt: Text(verbatim: "https://example.com/config.yaml")
                    )
                    .labelsHidden()
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("profile-metadata.url")

                    Toggle(
                        "Automatic Updates",
                        isOn: $autoUpdate
                    )
                    .accessibilityIdentifier(
                        "profile-metadata.auto-update"
                    )

                    if autoUpdate {
                        Stepper(
                            value: $updateIntervalHours,
                            in: 1...168
                        ) {
                            HStack {
                                Text("Interval")
                                Spacer()
                                Text(
                                    "\(updateIntervalHours) hours"
                                )
                                .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier(
                            "profile-metadata.interval"
                        )
                    }
                } header: {
                    Text("Profile URL")
                }
                }

                if ProfileMetadataUpdate.strippingSourceCredentials(
                    from: profile
                ) != nil {
                    Section {
                        Button(role: .destructive) {
                            confirmsCredentialRemoval = true
                        } label: {
                            Text("Remove Stored URL Credentials")
                        }
                        .accessibilityIdentifier("profile-metadata.strip-credentials")
                    } footer: {
                        Text("Removing them may require importing again.")
                    }
                }

                if !errorMessage.isEmpty {
                    Section {
                        HakoStatusMessage(
                            text: .copy(errorMessage),
                            kind: .error
                        )
                    }
                }
            }
            .hakoPageTitle("Profile URL Settings")
            .alert("Remove Stored URL Credentials", isPresented: $confirmsCredentialRemoval) {
                Button("Remove Stored URL Credentials", role: .destructive) { stripStoredCredentials() }
                    .accessibilityIdentifier("profile-metadata.strip-credentials.confirm")
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The saved profile URL carries sign-in details or query values. Removing them keeps the scheme, host and path only, and may require re-importing if the provider needs them.")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !insideProductModal {
                        Button("Cancel") {
                            dismissPresentation()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !insideProductModal, library == nil {
                        Button("Save") {
                            save()
                        }
                        .accessibilityIdentifier(
                            "profile-metadata.save"
                        )
                    }
                }
            }
            .hakoProductModalRoot(title: "Profile URL Settings")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if insideProductModal, library == nil {
                     
                    HakoModalActionBar(
                        primaryTitle: "Save",
                        primaryDisabled: !hasChanges,
                        onPrimary: save
                    )
                }
            }
        }
        .hakoStackNavigationViewStyle()
        .hakoCapturesDismiss(dismiss)
        .onAppear {
            if openedWith == nil {
                openedWith = (subscriptionURL, autoUpdate, updateIntervalHours)
            }
        }
    }

    private func stripStoredCredentials() {
        do {
            try model.stripSourceCredentials(profile)
            dismissPresentation()
        } catch {
            errorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? "Profile settings could not be saved."
        }
    }

     
    private var hasChanges: Bool {
        guard let openedWith else { return false }
        return openedWith.url != subscriptionURL
            || openedWith.auto != autoUpdate
            || openedWith.hours != updateIntervalHours
    }

    private func save() {
        do {
            try model.updateMetadata(
                profile,
                label: profile.label,
                subscriptionURL: subscriptionURL,
                autoUpdate: autoUpdate,
                updateIntervalHours: updateIntervalHours
            )
            dismissPresentation()
        } catch {
            errorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? "Profile settings could not be saved."
        }
    }

    private func dismissPresentation() {
        (productModalDismiss ?? { dismiss() })()
    }
}

 
 
 
 
 
struct HakoOptionalNavigationContainer<Content: View>: View {
    let owns: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        if owns {
             
             
             
             
            if #available(iOS 16.0, *) {
                 
                 
                 
                 
                 
                HakoPushableNavigationStack { content() }
            } else {
                NavigationView { content() }
                    .hakoStackNavigationViewStyle()
            }
        } else {
            content()
        }
    }
}


 
@available(iOS 16.0, *)
private struct HakoPushableNavigationStack<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) { content() }
            .environment(
                \.hakoPushRoute,
                HakoClientUI.HakoRoutePusher { route in
                    path.append(route)
                }
            )
    }
}


 
 
 
 
 
 
 
 
 
private struct ProfileProjectionLoader<Content: View>: View {
    let profile: Profile
    @ObservedObject var model: ProfilesViewModel
    @ViewBuilder let content: (String?) -> Content
    @State private var projected: String?
    @State private var ready = false

    var body: some View {
        Group {
            if ready {
                content(projected)
            } else {
                VStack(spacing: HakoTheme.Spacing.compact) {
                    Spacer()
                    ProgressView()
                    Text(hako: .copy("Opening Editor"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(HakoTheme.canvas.ignoresSafeArea())
                .accessibilityIdentifier("profile.projection.loading")
            }
        }
        .task(id: profile.id) {
            projected = await model.loadUIProjectedYAML(for: profile)
            ready = true
        }
    }
}

private struct ProfileSourceEditorLoader: View {
    let profile: Profile
    @ObservedObject var model: ProfilesViewModel
    var savesIndependentSource = false
    @State private var source: String?
    @State private var read = false

    var body: some View {
        Group {
            if read {
                ProfileEditView(
                    profile: profile,
                    rawYAML: source,
                    savesIndependentSource: savesIndependentSource
                ) { updated, rawYAML, resources, disablingAutoUpdate in
                    try await model.updateEdited(
                        updated,
                        sourceYAML: rawYAML,
                        resourceFiles: resources,
                        disablingAutoUpdate: disablingAutoUpdate
                    )
                }
            } else {
                VStack(spacing: HakoTheme.Spacing.compact) {
                    Spacer()
                    ProgressView()
                    Text(hako: .copy("Opening Editor"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(HakoTheme.canvas.ignoresSafeArea())
                .accessibilityIdentifier("profile.sourceEditor.loading")
            }
        }
        .task(id: profile.id) {
            source = await model.loadSourceYAML(for: profile)
            read = true
        }
    }
}
