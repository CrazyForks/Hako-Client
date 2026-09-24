import AppKit
import Combine
import HakoClientKit
import HakoClientUI
import HakoMacClient
import SwiftUI
import os

@MainActor
private final class HakoMacApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
         
         
         
         
        HakoMacLaunchGate.shared.applicationDidFinishLaunching()
         
         
        HakoMacDockIcon.apply(
            hidesIcon: UserDefaults.standard.bool(forKey: HakoMacDockIcon.key)
        )
         
         
         
        DispatchQueue.main.async {
            guard NSApplication.shared.windows.allSatisfy({
                $0.level != .normal || !$0.canBecomeKey
            }) else { return }
            HakoMacSceneModel.current?.openMainWindow()
        }


    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }

     
     
     
     
     
    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        guard let vpn = HakoMacSceneModel.current?.vpn else { return .terminateNow }
        let quit = HakoMacQuit(
            isTunnelUp: { [weak vpn] in
                guard let vpn else { return false }
                return HakoMacQuit.tunnelIsUp(status: vpn.status)
            },
             
             
             
             
            stop: { [weak vpn] in await vpn?.stop() },
            allowTermination: { sender.reply(toApplicationShouldTerminate: true) }
        )
        pendingQuit = quit
        return quit.reply(for: HakoMacQuit.nextTermination)
    }

     
    private var pendingQuit: HakoMacQuit?

     
     
     
     
     
     
     
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows: Bool
    ) -> Bool {
        guard !hasVisibleWindows else { return true }
        HakoMacSceneModel.current?.openMainWindow()
        return true
    }

     
     
     
     
     
    func applicationDidUpdate(_ notification: Notification) {
        HakoMacDockIcon.apply(
            hidesIcon: UserDefaults.standard.bool(forKey: HakoMacDockIcon.key)
        )
    }

     
     
     
     
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let model = HakoMacSceneModel.current else { return nil }
        let locale = model.preferences.language.locale
        let menu = NSMenu()
        menu.addItem(
            NSMenuItem(
                title: HakoCopy.string(
                    model.latestSnapshot.connection.phase.statusTitle,
                    locale: locale
                ),
                action: nil,
                keyEquivalent: ""
            )
        )
        if let intent = model.latestSnapshot.connection.primaryIntent {
            let action = NSMenuItem(
                title: HakoCopy.string(intent.toolbarTitle, locale: locale),
                action: #selector(performDockPrimaryAction),
                keyEquivalent: ""
            )
            action.target = self
            menu.addItem(action)
        }
        return menu
    }

    @objc private func performDockPrimaryAction() {
        HakoMacSceneModel.current?.performPrimaryAction()
    }
}

private struct HakoMacUIReviewEnvironment: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {

        content

    }
}

@main
struct HakoMacApp: App {
    @NSApplicationDelegateAdaptor(HakoMacApplicationDelegate.self)
    private var applicationDelegate
    @StateObject private var model = HakoMacSceneModel()
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase

    init() {
         
         
        HakoPerfBootstrap.install()
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        DispatchQueue.global(qos: .utility).async {
            _ = ThirdPartyLicenseInventory.shared.modules.count
        }
         
         
         
         
        ProxyNodeEditorMacOverrides.proxyTypeRow = { draft, hidesNonServerTypes in
            AnyView(
                ProxyTypeMacRow(
                    draft: draft,
                    hidesNonServerTypes: hidesNonServerTypes
                )
            )
        }
         
         
         
         
        ProxyNodeEditorMacOverrides.editorContainer = { content in
            AnyView(ProxyNodeMacEditorContainer(content: content))
        }
    }

    var body: some Scene {
         
         
         
         
        Window("Clash", id: "main") {
            HakoMacRootView(
                snapshot: model.snapshot,
                actions: model.actions,
                navigationRequest: $model.navigationRequest,
                secondaryContent: { destination in
                     
                     
                     
                     
                     
                     
                     
                     
                    AnyView(
                        HakoDeferredPageContent {
                            model.secondaryContent(destination)
                        } placeholder: {
                            HakoMacPlatformPresentation.palette.canvas
                                .ignoresSafeArea()
                        }
                        .id(destination)
                    )
                },
                detailOverlay: { root in
                    model.pooledDetailOverlay(for: root)
                },
                moreAttentionAction: { actionID in
                    model.performLegacySettingsAttention(actionID: actionID)
                }
            )
            .environment(\.hakoShellLayout, .regularSidebar)
             
             
            .modifier(HakoMacLiveResizeReporting())
             
             
             
            .environment(\.hakoBackupDataScope, model.backupScope)
            .environment(\.hakoTrafficFeed, model.trafficFeed)
            .modifier(HakoMacUIReviewEnvironment())
            .hakoMacWindowChrome()
             
             
             
             
             
            .onAppear {
                model.rememberWindowOpener(openWindow)
            }
            .task {
                await model.prepare()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                Task { await model.refreshVPNInstallation() }
            }
            .onOpenURL { url in
                model.open(url)
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: ProviderFirstLoadRetry.didRefreshNotification
                )
            ) { _ in
                model.applyFirstLoadRefreshes()
            }
            .alert(
                "Outbound mode unchanged",
                isPresented: Binding(
                    get: { !model.modeRefusalMessage.isEmpty },
                    set: { presented in
                        if !presented {
                            model.dismissModeRefusalMessage()
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    model.dismissModeRefusalMessage()
                }
            } message: {
                Text(hako: .copy(model.modeRefusalMessage))
            }
            .alert(
                Text(hako: .copy(
                    model.profileImports.pendingConfirmation
                        .map { HakoMacInstallLinkPrompt(pending: $0).title }
                        ?? "Add this profile URL?"
                )),
                isPresented: Binding(
                     
                     
                     
                     
                     
                    get: {
                        model.profileImports.pendingConfirmation != nil
                            && scenePhase == .active
                    },
                     
                     
                     
                     
                     
                     
                    set: { presented in
                        if !presented,
                           let pending = model.profileImports.pendingConfirmation {
                            HakoLogStore.shared.append(
                                "install link alert torn down (state kept)  \(pending)",
                                stream: .app, level: .warning)
                        }
                    }
                )
            ) {
                Button("Add") {
                    model.profileImports.acceptPendingConfirmation()
                    model.navigationRequest = .profiles
                }
                Button("Don't Add", role: .cancel) {
                    model.profileImports.declinePendingConfirmation()
                }
            } message: {
                if let pending = model.profileImports.pendingConfirmation {
                    let prompt = HakoMacInstallLinkPrompt(pending: pending)
                     
                     
                     
                    Text(hako: .copy(prompt.lead)) + Text(hako: .verbatim(prompt.link))
                }
            }
            .modifier(
                HakoMacPreferencesEnvironment(
                    preferences: model.preferences,
                    presentsRestartPrompt: true
                )
            )
        }
        .defaultSize(width: 1040, height: 720)
         
         
         
        WindowGroup("Runtime Configuration", id: "runtime-preview", for: HakoMacRuntimePreviewRequest.self) { $request in
            if let request, let profile = model.profiles.profiles.first(where: { $0.id == request.profileID }) {
                 
                ProfilePreviewView(title: .verbatim(profile.label)) { [profiles = model.profiles] in
                    try await profiles.loadAppliedConfigurationPreview(for: profile.id)
                }
                .frame(minWidth: 640, minHeight: 480)
            }
        }
        .defaultSize(width: 920, height: 720)
        .commandsRemoved()
        WindowGroup("Script", id: "script-editor", for: HakoMacScriptEditorRequest.self) { $request in
            if let request, let script = ScriptLibrary.load().first(where: { $0.id == request.scriptID }) {
                 
                ScriptEditorView(script: script) { ScriptLibrary.upsert($0) }
                    .frame(minWidth: 640, minHeight: 480)
            }
        }
        .defaultSize(width: 920, height: 720)
        .commandsRemoved()
        WindowGroup("Edit Source", id: "source-editor", for: HakoMacSourceEditorRequest.self) { $request in
            if let request {
                HakoMacSourceEditorWindow(request: request, profiles: model.profiles)
            }
        }
        .defaultSize(width: 920, height: 720)
         
         
        .commandsRemoved()
        .windowResizability(.contentMinSize)
        .commands {
            HakoMacProductCommands()
        }

    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum HakoMacDockIcon {
     
    static let key = "hako.mac.hide-dock-icon"

     
     
     
     
     
    static func policy(
        hidesIcon: Bool,
        hasVisibleWindow: Bool
    ) -> NSApplication.ActivationPolicy {
        hidesIcon && !hasVisibleWindow ? .accessory : .regular
    }

    @MainActor
    static func apply(hidesIcon: Bool, application: NSApplication = .shared) {
        let visible = application.windows.contains {
            $0.isVisible && $0.level == .normal && $0.canBecomeKey
        }
        let wanted = policy(hidesIcon: hidesIcon, hasVisibleWindow: visible)
        guard application.activationPolicy() != wanted else { return }
        application.setActivationPolicy(wanted)
         
         
        if wanted == .regular {
            application.activate(ignoringOtherApps: true)
        }
    }
}

enum HakoMacMenuBarSpeed {
     
     
    static let key = "hako.mac.menu-bar-speed"

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func rate(_ bytesPerSecond: Int64) -> String {
        let bitsPerSecond = Double(max(bytesPerSecond, 0)) * 8
        if bitsPerSecond < 1_000_000 {
            return String(format: "%.1f Kbps", bitsPerSecond / 1_000)
        }
        if bitsPerSecond < 1_000_000_000 {
            return String(format: "%.1f Mbps", bitsPerSecond / 1_000_000)
        }
        return String(format: "%.1f Gbps", bitsPerSecond / 1_000_000_000)
    }

     
     
     
     
    static let widestLine = "999.9 Mbps ↑"

    static func up(_ bytesPerSecond: Int64) -> String { rate(bytesPerSecond) + " ↑" }

    static func down(_ bytesPerSecond: Int64) -> String { rate(bytesPerSecond) + " ↓" }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    @MainActor
     
     
     
     
     
     
    static func menuBarImage(upLine: String, downLine: String, catAlpha: CGFloat) -> NSImage? {
        guard !upLine.isEmpty, !downLine.isEmpty,
              let cat = NSImage(named: HakoMacAsset.menuBarTemplate.rawValue)
        else { return nil }

        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
             
             
            .foregroundColor: NSColor.black,
        ]
        let upLine = upLine as NSString
        let downLine = downLine as NSString
        let upSize = upLine.size(withAttributes: attributes)
        let downSize = downLine.size(withAttributes: attributes)

         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        let reserve = (widestLine as NSString).size(withAttributes: attributes)
        let column = ceil(max(reserve.width, max(upSize.width, downSize.width)))
        let line = ceil(max(upSize.height, downSize.height))
         
         
         
        let height = line * 2 - 2
         
         
        let cat18: CGFloat = 18
        let gap: CGFloat = 3
        let size = CGSize(width: cat18 + gap + column, height: height)

        let image = NSImage(size: size, flipped: false) { _ in
            cat.draw(
                in: CGRect(
                    x: 0,
                    y: (height - cat18) / 2,
                    width: cat18,
                    height: cat18
                ),
                from: .zero,
                operation: .sourceOver,
                fraction: catAlpha
            )
             
             
             
             
             
            upLine.draw(
                at: CGPoint(
                    x: cat18 + gap + column - upSize.width,
                    y: height - line
                ),
                withAttributes: attributes
            )
            downLine.draw(
                at: CGPoint(x: cat18 + gap + column - downSize.width, y: 0),
                withAttributes: attributes
            )
            return true
        }
        image.isTemplate = true
        return image
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
private final class HakoMacMenuBarTrafficFeed: ObservableObject {
    @Published private(set) var upLine = ""
    @Published private(set) var downLine = ""

     
     
     
     
     
     
     
     
     
     
    private var trackingDepth = 0
    private var menuIsTracking: Bool { trackingDepth > 0 }
     
    private var thaw: DispatchWorkItem?
    private var pending: (up: String, down: String)?
    private var subscriptions: Set<AnyCancellable> = []

    init(command: ClashCommandClient) {
        upLine = HakoMacMenuBarSpeed.up(command.traffic.upload)
        downLine = HakoMacMenuBarSpeed.down(command.traffic.download)
        command.$traffic
            .sink { [weak self] traffic in
                self?.offer(
                    up: HakoMacMenuBarSpeed.up(traffic.upload),
                    down: HakoMacMenuBarSpeed.down(traffic.download)
                )
            }
            .store(in: &subscriptions)
        let center = NotificationCenter.default
        center.publisher(for: NSMenu.didBeginTrackingNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                 
                 
                self.thaw?.cancel()
                self.thaw = nil
                self.trackingDepth += 1
            }
            .store(in: &subscriptions)
        center.publisher(for: NSMenu.didEndTrackingNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                self.trackingDepth = max(0, self.trackingDepth - 1)
                guard self.trackingDepth == 0 else { return }
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.trackingDepth == 0 else { return }
                    self.thaw = nil
                    if let pending = self.pending {
                        self.pending = nil
                        self.upLine = pending.up
                        self.downLine = pending.down
                    }
                }
                self.thaw = work
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + 0.25, execute: work
                )
                return
            }
            .store(in: &subscriptions)
    }

    private func offer(up: String, down: String) {
        guard up != upLine || down != downLine else { return }
        if menuIsTracking {
            pending = (up, down)
        } else {
            upLine = up
            downLine = down
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
private struct HakoMacProxiesGhostChrome: View, Equatable {
    let model: HakoMacSceneModel
    @ObservedObject var channels: HakoRegularRootChannels

    init(model: HakoMacSceneModel) {
        self.model = model
        self.channels = model.proxiesChannels
    }

    static func == (
        lhs: HakoMacProxiesGhostChrome,
        rhs: HakoMacProxiesGhostChrome
    ) -> Bool {
        lhs.model === rhs.model
    }

    var body: some View {
        Color.clear
            .searchable(
                text: $channels.searchText,
                prompt: Text("Search proxies")
            )
            .hakoToolbarUnlessInPanel {
                HakoProxiesToolbar(
                    showsDismissControl: false,
                    hasExpandedGroups: model.proxiesHasExpandedGroupsNow,
                     
                     
                     
                     
                     
                     
                    canRefreshCatalog: true,
                    refreshDisabled: model.isTestingLatencyNow,
                    preferences: Binding(
                        get: {
                            HakoProxiesDisplayPreferences.uiTestOverride()
                                ?? HakoProxiesDisplayPreferences.load()
                        },
                        set: { [weak model] value in
                             
                             
                             
                             
                             
                            model?.applyProxiesDisplayPreferences(value)
                        }
                    ),
                    onDismiss: {},
                    onToggleFold: { [weak model] in
                        model?.proxiesChannels.foldCommand += 1
                    },
                    onRefresh: { [weak model] in
                        guard let model else { return }
                        Task { await model.refreshNodes() }
                    },
                    onShowDisplayOptions: {},
                    icon: { HakoSymbolImage(symbol: $0) }
                )
            }
    }
}

@MainActor
private final class HakoMacSceneModel: ObservableObject {
     
     
     
     
     
     
     
     
    private var automaticRefreshDriver: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    @Published private(set) var snapshot: AppleClientSnapshot = .empty
     
     
     
     
     
    let trafficFeed = HakoTrafficFeed(traffic: .zero)

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private var menuTrackingDepth = 0
    private var snapshotThaw: DispatchWorkItem?
     
     
     
    private lazy var snapshotGate = HakoMacSnapshotGate<AppleClientSnapshot> {
        [weak self] value in self?.snapshot = value
    }
     
     
     
    private(set) var productIsVisible = true
    private var visibilityObserver: HakoMacProductVisibilityObserver?
    private var menuGate: Set<AnyCancellable> = []

     
     
     
     
     
     
     
     
     
     
     
     
     
    private var refreshScheduled = false

    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.refreshScheduled = false
            self.refreshSnapshot()
        }
    }

    private func publish(_ value: AppleClientSnapshot) {
         
         
         
        snapshotGate.send(value)
    }

     
     
    fileprivate var latestSnapshot: AppleClientSnapshot {
        snapshotGate.latest ?? snapshot
    }

     
     
     
     
     
    func productVisibilityDidChange(_ visible: Bool) {
        productIsVisible = visible
        if visible {
            connections.sync(command.isConnected)
            trafficFeed.traffic = trafficSnapshot(command.traffic)
        } else {
            connections.sync(false)
        }
        snapshotGate.setVisible(visible)
    }

    private func observeMenuTracking() {
        let center = NotificationCenter.default
        center.publisher(for: NSMenu.didBeginTrackingNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                self.snapshotThaw?.cancel()
                self.snapshotThaw = nil
                self.menuTrackingDepth += 1
                self.snapshotGate.setMenuTracking(true)
            }
            .store(in: &menuGate)
        center.publisher(for: NSMenu.didEndTrackingNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                self.menuTrackingDepth = max(0, self.menuTrackingDepth - 1)
                guard self.menuTrackingDepth == 0 else { return }
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.menuTrackingDepth == 0 else { return }
                    self.snapshotThaw = nil
                    self.snapshotGate.setMenuTracking(false)
                }
                self.snapshotThaw = work
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + 0.25, execute: work
                )
            }
            .store(in: &menuGate)
    }
     

     
    @Published var configurationCenterSegment: HakoMacConfigurationCenterSegment = .configurations
     
     
     
     
     
    var configurationCenterDeleteHandler: ((HakoMacConfigurationCenterItem) -> Void)?
    private var configurationCenterDeleteAsks: AnyCancellable?

     
     
     
     
     
    func armDeleteConfirmation() {
        guard configurationCenterDeleteAsks == nil else { return }
        configurationCenterDeleteAsks = $configurationCenterPendingDelete
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] item in self?.presentDeleteConfirmation(item) }
    }

    private func presentDeleteConfirmation(_ item: HakoMacConfigurationCenterItem) {
        let locale = preferences.language.locale
        let isChain: Bool = {
            guard case .source(let id) = item else { return false }
            return configurationLibrary.snapshot.sources.first { $0.id == id }?.nodeChain != nil
        }()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = HakoMacDeleteCopy.title(item, isChain: isChain, locale: locale)
        alert.informativeText = HakoMacDeleteCopy.message(item, isChain: isChain, locale: locale)
        let delete = alert.addButton(withTitle: HakoCopy.string("Delete", locale: locale))
        delete.hasDestructiveAction = true
        delete.setAccessibilityIdentifier("configuration-center.delete.confirm")
        let cancel = alert.addButton(withTitle: HakoCopy.string("Cancel", locale: locale))
        cancel.keyEquivalent = "\u{1b}"
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            self?.configurationCenterPendingDelete = nil
            if response == .alertFirstButtonReturn { self?.configurationCenterDeleteHandler?(item) }
        }
        if let window = NSApplication.shared.windows.first(where: { $0.level == .normal && $0.canBecomeKey && $0.isVisible }) {
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(alert.runModal())
        }
    }

    lazy var configurationLibrary: HakoMacConfigurationLibraryModel = {
        let model = HakoMacConfigurationLibraryModel(actions: configurationLibraryActions())
         
         
         
         
         
         
        configurationLibraryFollowsProfiles = profiles.$profiles
            .dropFirst()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak model] _ in Task { @MainActor in await model?.reload() } }
        return model
    }()
    private var configurationLibraryFollowsProfiles: AnyCancellable?

    var configurationCenterSegmentBinding: Binding<HakoMacConfigurationCenterSegment> {
        Binding(get: { self.configurationCenterSegment }, set: { self.configurationCenterSegment = $0 })
    }

     
    @Published var showsConfigurationWizard = false

     
     
    @Published var configurationCenterPendingDelete: HakoMacConfigurationCenterItem?
    @Published var configurationCenterImport: HakoMacImportRequest?
     
     
     
     
     
     
    var configurationCenterLatestList: HakoProfilesListPresentation?
    @Published var configurationCenterEditingScheme: HakoMacLibrarySelection?
     
     
    let configurationWrites = HakoMacSerialWrites()
     
     
    @Published var configurationWriteError: String?
     
    @Published var configurationCenterChain: HakoMacChainRequest?
     
    @Published var configurationCenterInspectedNode: HakoMacInspectedNode?
     
    @Published var configurationCenterEditingNode: HakoMacEditingNode?
     
     
    @Published var configurationCenterShownItem: HakoMacConfigurationCenterItem?

     
     
     
    func requestDeleteShownItem() {
        guard let item = configurationCenterShownItem else { return }
        if case .collection = item { return }
        configurationCenterPendingDelete = item
    }

    var configurationCenterPendingDeleteBinding: Binding<HakoMacConfigurationCenterItem?> {
        Binding(get: { self.configurationCenterPendingDelete }, set: { self.configurationCenterPendingDelete = $0 })
    }
    var configurationCenterImportBinding: Binding<HakoMacImportRequest?> {
        Binding(get: { self.configurationCenterImport }, set: { self.configurationCenterImport = $0 })
    }
    var configurationCenterChainBinding: Binding<HakoMacChainRequest?> {
        Binding(get: { self.configurationCenterChain }, set: { self.configurationCenterChain = $0 })
    }
    var configurationCenterInspectedNodeBinding: Binding<HakoMacInspectedNode?> {
        Binding(get: { self.configurationCenterInspectedNode }, set: { self.configurationCenterInspectedNode = $0 })
    }
    var configurationCenterEditingNodeBinding: Binding<HakoMacEditingNode?> {
        Binding(get: { self.configurationCenterEditingNode }, set: { self.configurationCenterEditingNode = $0 })
    }
    var configurationCenterEditingSchemeBinding: Binding<HakoMacLibrarySelection?> {
        Binding(get: { self.configurationCenterEditingScheme }, set: { self.configurationCenterEditingScheme = $0 })
    }

    var showsConfigurationWizardBinding: Binding<Bool> {
        Binding(get: { self.showsConfigurationWizard }, set: { self.showsConfigurationWizard = $0 })
    }

     
     
     
     
    private func configurationImportActions() -> HakoMacSourceImportActions {
        let profiles = self.profiles
        var actions = HakoMacSourceImportActions(
            fetch: { url, label in
                try await profiles.fetchConfigurationSource(url: url, label: label)
            },
            readFile: { name, text, companions in
                 
                 
                let resources = companions.map { ExternalResourceImportFile(fileName: $0.fileName, data: $0.data) }
                return try await Task.detached {
                    try ConfigurationCenterSourceBridge.payload(
                        label: name, origin: .file(name), original: Data(text.utf8), yaml: text, resources: resources
                    )
                }.value
            },
            importOriginal: { [weak self] payload in
                let source: Profile.Source
                switch payload.record.origin {
                case .subscription(let link):
                    source = .url(link)
                case .file(let name):
                    source = .file(name)
                case .customNodes, .bundled:
                    source = .clipboard
                }
                profiles.add(
                    label: payload.record.label,
                    source: source,
                    rawYAML: String(decoding: payload.original, as: UTF8.self)
                )
                 
                 
                self?.configurationCenterImport = nil
            },
             
             
             
            readNodes: { definition in
                try await Task.detached {
                    let nodes = try CustomNodePayload.payload(inDefinition: definition)
                    guard !nodes.isEmpty else { throw CustomNodeAppendError.missingName }
                    let document = try JSONSerialization.data(withJSONObject: ["proxies": nodes])
                    let yaml = try ConfigTransforms.jsonToYAML(String(decoding: document, as: UTF8.self))
                    return try ConfigurationCenterSourceBridge.payload(
                        label: nodes.count == 1 ? (nodes[0]["name"] as? String ?? "Custom Nodes") : "Custom Nodes",
                        origin: .customNodes, original: Data(yaml.utf8), yaml: yaml
                    )
                }.value
            },
             
             
             
             
            createQuickRule: { [weak self] raw, enabled, comment in
                guard let self, let store = profiles.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
                var snapshot = try await Task.detached { try store.snapshot() }.value
                let myRules = HakoCopy.string("My Rules", locale: self.preferences.language.locale)
                let active = profiles.activeProfileID
                let activeSchemeID = active.flatMap { id in snapshot.recipes.first { $0.id == id }?.ruleSchemeID }
                let schemeID: String
                switch QuickRulePlan.make(activeSchemeID: activeSchemeID, schemes: snapshot.rules, myRulesLabel: myRules) {
                case .reuse(let id):
                    schemeID = id
                case .copy(let base):
                    let before = Set(snapshot.rules.map(\.id))
                    snapshot = try await profiles.copyConfigurationRuleScheme(base, label: myRules, generation: snapshot.generation)
                    guard let made = snapshot.rules.first(where: { !before.contains($0.id) }) else {
                        throw ConfigurationLibraryError.invalidIdentifier
                    }
                    schemeID = made.id
                }
                guard let scheme = snapshot.rules.first(where: { $0.id == schemeID }) else {
                    throw ConfigurationLibraryError.missingDependency(schemeID)
                }
                var draft = try await Task.detached(priority: .userInitiated) {
                    try ConfigurationRuleDraft(scheme: scheme, payload: try store.ruleSchemePayload(schemeID))
                }.value
                draft.insertRuleFirst(raw)
                if let first = draft.rows.first { draft.setRule(raw, enabled: enabled, note: comment, rowID: first.id) }
                snapshot = try await profiles.saveConfigurationRuleDraft(draft, generation: snapshot.generation)
                if let active,
                   let recipe = snapshot.recipes.first(where: { $0.id == active }),
                   recipe.ruleSchemeID != schemeID {
                    var edit = ConfigurationCreationAdapter.editingDraft(
                        recipe: recipe, label: profiles.profiles.first(where: { $0.id == active })?.label ?? recipe.label
                    )
                    edit.selectedRuleID = schemeID
                    try await profiles.editConfiguration(edit, id: active, generation: snapshot.generation)
                }
                await self.configurationLibrary.reload()
            }
        )
         
         
         
        actions.quickRuleTargets = { [weak self] in
            guard let self, let store = profiles.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            let snapshot = try await Task.detached { try store.snapshot() }.value
            let myRules = HakoCopy.string("My Rules", locale: self.preferences.language.locale)
            let activeSchemeID = profiles.activeProfileID.flatMap { id in snapshot.recipes.first { $0.id == id }?.ruleSchemeID }
            let targetID: String
            switch QuickRulePlan.make(activeSchemeID: activeSchemeID, schemes: snapshot.rules, myRulesLabel: myRules) {
            case .reuse(let id): targetID = id
            case .copy(let base): targetID = base
            }
            let groups: [String] = try await Task.detached {
                if let scheme = snapshot.rules.first(where: { $0.id == targetID }) {
                    return try ConfigurationRuleDraft(scheme: scheme, payload: try store.ruleSchemePayload(targetID)).groups.map(\.name)
                }
                if ConfigurationBuiltins.isNative(targetID), let source = try ConfigurationBuiltins.source(for: targetID) {
                    return try ConfigurationRuleGroupSnapshot.read(OrderedJSON.parse(source.documentJSON)).map(\.name)
                }
                return []
            }.value
            var seen = Set<String>()
            return (["DIRECT", "REJECT"] + groups).filter { seen.insert($0).inserted }
        }
         
         
        actions.addRuleSet = { [weak self] draft in
            guard let self else { throw ConfigurationLibraryError.unreadable }
            let document = try draft.document()
            try await Task.detached { try ConfigTransforms.validateSource(document.serialized()) }.value
            let payload = ConfigurationSourcePayload(
                record: draft.record(), original: Data(document.serialized().utf8),
                documentJSON: document.serialized(), resourceFiles: draft.resourceFiles
            )
            try await self.configurationLibrary.addSource(payload)
        }
         
         
         
        actions.customNodesEditor = { accept, close in
            AnyView(
                ConfigurationNodeSourceAdapter(accept: accept)
                    .environment(\.hakoProductModalDismiss, close)
            )
        }
        return actions
    }

    lazy var configurationImportActionsValue = configurationImportActions()

    lazy var configurationWizardActions: HakoMacConfigurationWizardActions = {
        var actions = HakoMacConfigurationWizardActions(
            create: { [profiles] draft, generation, id in
                _ = try await profiles.createConfiguration(draft, generation: generation, id: id)
            },
            sourceImport: configurationImportActionsValue
        )
        actions.loadScopeChoices = { [profiles] source, staged in
            try await Self.scopeChoices(source, staged: staged, store: profiles.configurationLibraryStore)
        }
         
         
        actions.preview = { [profiles] draft in
            guard let store = profiles.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            return try await Task.detached {
                let generation = try store.snapshot().generation
                let nodes = try ConfigurationCompletionPreview.sections(draft: draft, library: store, generation: generation, nodes: true)
                let rules = try ConfigurationCompletionPreview.sections(draft: draft, library: store, generation: generation, nodes: false)
                return HakoMacWizardPreview(
                    nodes: nodes.reduce(0) { $0 + $1.rows.count },
                    rules: rules.first { $0.title == "Rules" }?.rows.count ?? rules.reduce(0) { $0 + $1.rows.count }
                )
            }.value
        }
        return actions
    }()

     
     
    static func scopeChoices(
        _ source: ConfigurationSourceRecord, staged: ConfigurationSourcePayload?, store: ConfigurationLibraryStore?
    ) async throws -> HakoMacNodeScopeChoices {
        try await Task.detached {
            let payload: ConfigurationSourcePayload
            if let staged {
                payload = staged
            } else {
                guard let store else { throw ConfigurationLibraryError.unreadable }
                payload = try store.payload(.init(source))
            }
            let document = try OrderedJSON.parse(payload.documentJSON)
            var nodes: [HakoConfigurationSelectableNode] = []
            if case .array(let entries) = document.topLevelValue("proxies") {
                nodes = entries.compactMap { node in
                    guard let name = node.topLevelValue("name")?.foundationValue as? String else { return nil }
                    return HakoConfigurationSelectableNode(name: name, type: node.topLevelValue("type")?.foundationValue as? String ?? "")
                }
            }
            return HakoMacNodeScopeChoices(
                collections: ConfigurationCollection.read(sourceID: source.id, document: document, kind: .nodes), nodes: nodes
            )
        }.value
    }

     
     
    private func configurationLibraryActions() -> HakoMacConfigurationLibraryActions {
        let profiles = self.profiles
        var actions = HakoMacConfigurationLibraryActions(
            load: {
                 
                 
                 
                 
                try? await profiles.recoverConfigurationPublications()
                do { try await profiles.registerLegacyConfigurationSources() } catch {
                     
                    NSLog("configuration-centre.legacy-registration-failed:%@", error.localizedDescription)
                }
                guard let store = await MainActor.run(body: { profiles.configurationLibraryStore }) else {
                    throw ConfigurationLibraryError.unreadable
                }
                return try await Task.detached { try store.snapshot() }.value
            },
            renameSource: { id, label, generation in
                try await profiles.renameConfigurationSource(id, label: label, generation: generation)
            },
            deleteSource: { id, generation in
                try await profiles.deleteConfigurationSource(id, generation: generation)
            },
            updateSource: { id in
                try await profiles.refreshConfigurationSource(id)
            },
            deleteRuleScheme: { id, generation in
                try await profiles.deleteConfigurationRuleScheme(id, generation: generation)
            },
            addSource: { payload, generation in
                try await profiles.addConfigurationSource(payload, generation: generation)
            },
            addRuleScheme: { payload, generation in
                try await profiles.addConfigurationRuleScheme(payload, generation: generation)
            },
            copyScheme: { id, label, generation in
                try await profiles.copyConfigurationRuleScheme(id, label: label, generation: generation)
            }
        )
        actions.loadCollections = { snapshot in
            guard let store = await MainActor.run(body: { profiles.configurationLibraryStore }) else { return [] }
            return try await Task.detached { try store.collectionCatalog(snapshot) }.value
        }
        actions.saveSourceSettings = { id, draft, generation in
            try await profiles.saveConfigurationSourceSettings(id, draft: draft, generation: generation)
        }
         
         
        actions.saveSourceDetails = { id, label, settings, generation in
            if let settings {
                return try await profiles.saveConfigurationSourceSettings(id, draft: settings, label: label, generation: generation)
            }
            return try await profiles.renameConfigurationSource(id, label: label, generation: generation)
        }
         
         
         
         
         
         
         
         
        actions.syncLegacyProfiles = { progress in
            let remote = profiles.profiles.filter { if case .url = $0.source { return true }; return false }
            guard !remote.isEmpty else { return HakoMacBatchOutcome() }
            var outcome = HakoMacBatchOutcome()
            for (index, profile) in remote.enumerated() {
                progress(HakoCopy.string("Updating Sources…", locale: Locale.current) + " \(index + 1) / \(remote.count) · " + profile.label)
                do {
                    if try await profiles.refreshLegacyProfileAwaiting(profile) == .updated { outcome.updated += 1 }
                } catch {
                    outcome.failures.append(profile.label + ": " + error.localizedDescription)
                }
            }
            return outcome
        }
        actions.updateSourceReplacingRules = { id, version in
            try await profiles.refreshConfigurationSource(id, replaceEditedRules: true, expectedVersion: version)
        }
         
         
        actions.updateAllSources = { progress in
            guard let store = profiles.configurationLibraryStore else {
                return HakoMacBatchOutcome(failures: [ConfigurationLibraryError.unreadable.localizedDescription])
            }
            let snapshot: ConfigurationLibrarySnapshot
            do { snapshot = try await Task.detached { try store.snapshot() }.value } catch {
                return HakoMacBatchOutcome(failures: [error.localizedDescription])
            }
            let locale = Locale.current
            let result = await ConfigurationCollectionContentBridge.updateNodeLibrary(
                snapshot.availableSources,
                updateSource: { source in try await profiles.refreshConfigurationSource(source.id) },
                collections: {
                    try await Task.detached { try ConfigurationCollectionContentBridge.catalog(store, snapshot: store.snapshot()) }.value
                },
                updateCollection: { entry in
                    let source = try await Task.detached { try store.payload(.init(entry.source)) }.value
                    try await ConfigurationCollectionContentBridge.refresh(entry, source: source)
                },
                progress: { phase, index, total, name in
                    let key = phase == .sources ? "Updating Sources…" : "Updating Node Collections…"
                    progress(HakoCopy.string(key, locale: locale) + " \(index) / \(total) · " + name)
                }
            )
            return HakoMacBatchOutcome(updated: result.updated, failures: result.failures)
        }
         
         
        actions.updateAllRuleSets = { progress in
            guard let store = profiles.configurationLibraryStore else {
                return HakoMacBatchOutcome(failures: [ConfigurationLibraryError.unreadable.localizedDescription])
            }
            let entries: [ConfigurationCollectionEntry]
            do {
                entries = try await Task.detached { try ConfigurationCollectionContentBridge.catalog(store, snapshot: store.snapshot()) }.value
            } catch {
                return HakoMacBatchOutcome(failures: [error.localizedDescription])
            }
            let result = await ConfigurationCollectionContentBridge.updateRuleCollections(
                entries,
                update: { entry in
                    let source = try await Task.detached { try store.payload(.init(entry.source)) }.value
                    try await ConfigurationCollectionContentBridge.refresh(entry, source: source)
                },
                progress: { index, total, name in progress("\(index) / \(total) · " + name) }
            )
            return HakoMacBatchOutcome(updated: result.updated, failures: result.failures)
        }
        return actions
    }

     
     
    private func sourcePage(_ source: ConfigurationSourceRecord, list: HakoProfilesListPresentation) -> some View {
        let sourceID = source.id
        let readers = configurationLibrary.configurations(usingSource: sourceID)
        var page = HakoMacSourceContentPage(
            source: source,
            usedBy: list.profiles.filter { readers.contains($0.id.rawValue) },
            isUpdating: configurationLibrary.updatingSourceIDs.contains(sourceID),
            collections: configurationLibrary.collections(for: sourceID),
            collectionPage: { [weak self] entry in
                AnyView(
                    HakoMacCollectionPane(
                        collection: entry.collection, sourceLabel: entry.source.label,
                        actions: self?.collectionPageActions(entry) ?? .unavailable
                    )
                    .navigationTitle(Text(verbatim: entry.collection.name))
                )
            },
            actions: sourceContentActions(source)
        )
        page.updateError = configurationLibrary.updateFailures[sourceID]
        page.updateIssue = Self.updateIssueMessage(configurationLibrary.snapshot, sourceID: sourceID, locale: preferences.language.locale)
        return page
    }

    private func sourceContentActions(_ source: ConfigurationSourceRecord) -> HakoMacSourceContentActions {
        let sourceID = source.id
        let isCustom = source.origin == .customNodes && source.nodeChain == nil && source.isRetainedSnapshot != true
        var actions = HakoMacSourceContentActions(
            loadNodes: { [weak self] in try await self?.sourceNodes(sourceID) ?? [] },
            openNode: { [weak self] node in self?.configurationCenterInspectedNode = HakoMacInspectedNode(node: node) },
            update: { [weak self] in Task { _ = await self?.configurationLibrary.updateSource(sourceID) } },
            delete: { [weak self] in self?.configurationCenterPendingDelete = .source(sourceID) },
            editSource: { [weak self] in
                self?.openWindowAction?(id: "source-editor", value: HakoMacSourceEditorRequest(profileID: "", nodeSourceID: sourceID))
            },
            details: HakoMacSourcePaneActions(
                save: { [weak self] label, settings in
                    Task { _ = await self?.configurationLibrary.saveSourceDetails(sourceID, label: label, settings: settings) }
                },
                update: {}, delete: {}
            )
        )
        if isCustom {
             
            actions.openNode = { [weak self] node in
                guard let record = CustomNodesView.record(fromNodeJSON: node.json) else {
                    self?.configurationCenterInspectedNode = HakoMacInspectedNode(node: node)
                    return
                }
                self?.configurationCenterEditingNode = HakoMacEditingNode(source: source, node: node, record: record)
            }
            actions.deleteNode = { [weak self] node in
                guard let self else { return }
                Task { @MainActor in
                    do {
                        let next = try await self.profiles.deleteConfigurationCustomNode(.init(source), index: node.index)
                        self.configurationLibrary.apply(next)
                    } catch {
                        self.configurationLibrary.report(error.localizedDescription)
                    }
                }
            }
            actions.addNode = { [weak self] in
                self?.configurationCenterImport = HakoMacImportRequest(purpose: .nodes, tab: .nodes, mergeIntoSourceID: sourceID)
            }
        }
        if source.nodeChain != nil {
            actions.editChain = { [weak self] in self?.configurationCenterChain = HakoMacChainRequest(existingID: sourceID) }
        }
        return actions
    }

     
     
    static func updateIssueMessage(_ library: ConfigurationLibrarySnapshot, sourceID: String, locale: Locale) -> String? {
        let issues = (library.updateIssues ?? []).filter { $0.sourceID == sourceID }
        guard !issues.isEmpty else { return nil }
        let names = issues.map { issue in
            library.recipes.first { $0.id == issue.itemID }?.label
                ?? library.sources.first { $0.id == issue.itemID }?.label ?? issue.itemID
        }
        return HakoCopy.string("Some references are unavailable. Previous versions were kept:", locale: locale) + " " + names.joined(separator: ", ")
    }

     
     
     
     
     
    private func collectionPageActions(_ entry: ConfigurationCollectionEntry) -> HakoMacCollectionPageActions {
        let profiles = self.profiles
        var actions = HakoMacCollectionPageActions(load: { query, offset in
            guard let store = profiles.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            return try await Task.detached {
                let source = try store.payload(.init(entry.source))
                let page = try ConfigurationCollectionContentBridge.page(entry, source: source, query: query, offset: offset)
                let rows: [HakoMacCollectionPage.Row]
                if entry.id.kind == .nodes {
                    rows = page.nodes.enumerated().map { index, json in
                        let node = try? OrderedJSON.parse(json)
                        return HakoMacCollectionPage.Row(
                            id: offset + index,
                            title: node?.topLevelValue("name")?.foundationValue as? String ?? String(offset + index + 1),
                            subtitle: node?.topLevelValue("type")?.foundationValue as? String ?? ""
                        )
                    }
                } else {
                    rows = page.lines.enumerated().map { index, line in HakoMacCollectionPage.Row(id: offset + index, title: line, subtitle: nil) }
                }
                return HakoMacCollectionPage(
                    rows: rows, count: page.count, updatedAt: page.updatedAt, nextOffset: page.nextOffset, message: page.message
                )
            }.value
        })
        if entry.collection.type == "http" {
            actions.update = {
                guard let store = profiles.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
                let source = try await Task.detached { try store.payload(.init(entry.source)) }.value
                try await ConfigurationCollectionContentBridge.refresh(entry, source: source)
            }
        }
        if entry.id.kind == .rules {
            actions.createScheme = { [weak self] in
                guard let self, let store = profiles.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
                let next = try await Task.detached {
                    try store.addRuleScheme(collection: entry, expectedGeneration: store.snapshot().generation)
                }.value
                self.configurationLibrary.apply(next)
            }
        }
        actions.editSource = { [weak self] in
            self?.openWindowAction?(
                id: "source-editor",
                value: HakoMacSourceEditorRequest(profileID: "", collection: HakoMacCollectionReference(entry))
            )
        }
        actions.delete = { [weak self] in
            guard let self else { throw ConfigurationLibraryError.unreadable }
            let next = try await profiles.saveConfigurationCollection(entry, definitionJSON: nil)
            self.configurationLibrary.apply(next)
        }
        return actions
    }

     
     
    private func sourceNodes(_ sourceID: String) async throws -> [HakoMacSourceNode] {
        guard let store = profiles.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        return try await Task.detached {
            guard let source = try store.snapshot().sources.first(where: { $0.id == sourceID }) else {
                throw ConfigurationLibraryError.missingDependency(sourceID)
            }
            let payload = try store.payload(.init(source))
            guard case .array(let values) = try OrderedJSON.parse(payload.documentJSON).topLevelValue("proxies") else { return [] }
            return values.enumerated().map { index, node in
                HakoMacSourceNode(
                    index: index,
                    name: node.topLevelValue("name")?.foundationValue as? String ?? String(index + 1),
                    type: node.topLevelValue("type")?.foundationValue as? String ?? "",
                    server: node.topLevelValue("server")?.foundationValue as? String,
                    json: node.serialized()
                )
            }
        }.value
    }

     
     
     
    private func chainSheetActions(existing: ConfigurationSourceRecord?) -> HakoMacChainSheetActions {
        let profiles = self.profiles
        let library = configurationLibrary
        return HakoMacChainSheetActions(
            loadChoices: {
                guard let store = profiles.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
                return try await Task.detached {
                    let snapshot = try store.snapshot()
                    var choices: [HakoMacChainChoice] = []
                    for record in snapshot.availableSources where record.suppliesNodes && record.nodeChain == nil {
                        let payload = try store.payload(.init(record))
                        guard case .array(let nodes) = try OrderedJSON.parse(payload.documentJSON).topLevelValue("proxies") else { continue }
                        for node in nodes {
                            guard let name = node.topLevelValue("name")?.foundationValue as? String, !name.isEmpty else { continue }
                             
                            if let dialer = node.topLevelValue("dialer-proxy")?.foundationValue as? String,
                               !dialer.isEmpty, dialer != "DIRECT" { continue }
                            choices.append(.init(hop: .init(source: .init(record), nodeName: name), sourceLabel: record.label))
                        }
                    }
                    return choices
                }.value
            },
            commit: { name, entry, exit in
                guard let store = profiles.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
                let payload = try await Task.detached {
                    var record = existing ?? ConfigurationSourceRecord(
                        id: "chain-" + UUID().uuidString.lowercased(), label: name, origin: .customNodes, nodeCount: 1
                    )
                    record.label = name.isEmpty ? entry.nodeName + " → " + exit.nodeName : name
                    return try ConfigurationNodeChain.materialize(record: record, chain: .init(entry: entry, exit: exit), load: store.payload)
                }.value
                if let existing {
                    library.apply(try await profiles.saveConfigurationChain(.init(existing), replacement: payload))
                } else {
                    try await library.addSource(payload)
                }
            }
        )
    }

     
     
     
    @ViewBuilder
    private func configurationDoor(
        _ door: HakoMacConfigurationDoor,
        profileID: HakoClientKit.Profile.ID,
        list: HakoProfilesListPresentation
    ) -> some View {
        if case .scheme(let schemeID) = door {
             
             
            if let scheme = configurationLibrary.ruleShelves.flatMap(\.schemes).first(where: { $0.id == schemeID }) {
                schemePane(scheme, schemeID: schemeID, snapshot: configurationLibrary.snapshot, list: list)
                    .id(schemeID)
                    .navigationTitle(Text(verbatim: scheme.displayLabel))
            } else {
                EmptyView()
            }
        } else if let profile = profiles.profiles.first(where: { $0.id == profileID.rawValue }) {
            switch door {
            case .scheme:
                EmptyView()
            case .network:
                ProfileNetworkSettingsView(
                    profile: profile, sourceYAML: profiles.baseYAML(for: profile), ownsNavigationContainer: false
                ) { [profiles] draft in
                    try profiles.updateNetwork(draft)
                }
            case .trust:
                 
                 
                ProfileRuntimeTrustEditor(
                    profile: profile, sourceYAML: profiles.sourceYAML(for: profile), patchJSON: profile.override.patchJSON
                ) { [profiles, library = configurationLibrary] patchJSON in
                    var draft = ProfileAdvancedOverridesDraft(profile: profile)
                    draft.rawPatchJSON = patchJSON
                    do { try profiles.updateAdvancedOverrides(draft) } catch { library.report(error.localizedDescription) }
                }
            }
        } else {
            EmptyView()
        }
    }

     

     
     
     
     
    func configurationCenter(_ list: HakoProfilesListPresentation) -> some View {
        configurationCenterLatestList = list
        let actions = configurationCenterListActions(list)
        configurationCenterDeleteHandler = { item in actions.delete(item) }
        armDeleteConfirmation()
        return HakoMacConfigurationCenterView(segment: configurationCenterSegmentBinding) {
            self.configurationCenterListPage(.configurations, list: list, actions: actions)
        } nodes: {
            self.configurationCenterListPage(.nodes, list: list, actions: actions)
        } rules: {
            self.configurationCenterListPage(.rules, list: list, actions: actions)
        }
        .task { [weak self] in
            guard let self, self.configurationLibrary.phase == .idle else { return }
            await self.configurationLibrary.reload()
        }
        .modifier(HakoMacCentrePresentations(model: self, actions: actions))
        .sheet(item: configurationCenterImportBinding) { [weak self] request in
            HakoMacSourceImportSheet(
                purpose: request.purpose,
                actions: self?.configurationImportActionsValue ?? .unavailable,
                initialTab: request.tab,
                accept: { [weak self] payload in
                    guard let self else { return }
                    if let target = request.mergeIntoSourceID,
                       let source = self.configurationLibrary.snapshot.sources.first(where: { $0.id == target }) {
                         
                        guard case .array(let nodes) = try OrderedJSON.parse(payload.documentJSON).topLevelValue("proxies"), !nodes.isEmpty else {
                            throw ConfigurationLibraryError.unreadable
                        }
                        var version = ConfigurationSourceVersion(source)
                        for node in nodes {
                            let next = try await self.profiles.saveConfigurationCustomNode(version, nodeJSON: node.serialized(), index: nil)
                            self.configurationLibrary.apply(next)
                            if let updated = next.sources.first(where: { $0.id == target }) { version = ConfigurationSourceVersion(updated) }
                        }
                    } else {
                        switch request.purpose {
                        case .rules:
                             
                             
                             
                            if payload.record.ruleCount > 0 {
                                try await self.configurationLibrary.addRuleScheme(payload)
                            } else {
                                let collections = try ConfigurationCollection.read(
                                    sourceID: payload.record.id, document: try OrderedJSON.parse(payload.documentJSON), kind: .rules
                                )
                                guard !collections.isEmpty else { throw ConfigurationLibraryError.missingRules }
                                var source = payload
                                source.record.suppliesNodes = false
                                source.record.registersSuppliedRules = false
                                try await self.configurationLibrary.addSource(source)
                            }
                        case .nodes:
                             
                             
                            guard payload.record.suppliesNodes, payload.record.nodeCount > 0 || payload.record.providerCount > 0 else {
                                throw ConfigurationLibraryError.missingNodes
                            }
                            var source = payload
                            source.record.registersSuppliedRules = false
                            try await self.configurationLibrary.addSource(source)
                        }
                    }
                    self.configurationCenterImport = nil
                },
                close: { [weak self] in self?.configurationCenterImport = nil }
            )
            .hakoModalPresentation(.fitted)
        }
         
         
         
         
         
        .hakoProductModal(item: configurationCenterInspectedNodeBinding, role: .form) { inspected in
            ProxyNodeDetailSheet(
                nodeName: inspected.node.name, yaml: nil, providersDir: nil,
                suppliedDetails: CustomNodesView.record(fromNodeJSON: inspected.node.json)?.protocolDetails
            )
            .hakoModalPresentation(.form)
        }
         
         
         
        .hakoProductModal(item: configurationCenterEditingNodeBinding, role: .form) { [weak self] editing in
            HakoFeatureNavigationContainer {
                ProxyNodeDetailsView(
                    record: editing.record,
                    retest: {},
                    saveNode: { [weak self] _, json in
                        guard let self else { throw ConfigurationLibraryError.unreadable }
                        let next = try await self.profiles.saveConfigurationCustomNode(
                            .init(editing.source), nodeJSON: json, index: editing.node.index
                        )
                        self.configurationLibrary.apply(next)
                    },
                    showsTesting: false,
                    onDone: { [weak self] in self?.configurationCenterEditingNode = nil },
                    commitTitle: "Save"
                )
            }
            .hakoPageSizedSheet()
        }
        .sheet(isPresented: showsConfigurationWizardBinding) { [weak self] in
            if let self {
                HakoMacConfigurationWizardSheet(
                    model: self.configurationLibrary,
                    actions: self.configurationWizardActions,
                    created: {}
                )
                .hakoModalPresentation(.fitted)
            }
        }
    }

    private func configurationCenterListPage(
        _ segment: HakoMacConfigurationCenterSegment,
        list: HakoProfilesListPresentation,
        actions: HakoMacConfigurationCenterListActions
    ) -> some View {
        HakoMacConfigurationCenterListPage(
            segment: segment,
            model: configurationLibrary,
            profiles: list.profiles,
            pendingDelete: configurationCenterPendingDeleteBinding,
            actions: actions
        ) { [weak self] item in
            if let self {
                 
                 
                let hadRecipe: Bool = {
                    guard case .configuration(let id) = item else { return false }
                    return self.configurationLibrary.snapshot.recipes.contains { $0.id == id.rawValue }
                }()
                AnyView(
                    HakoMacObservedLibraryPage(model: self.configurationLibrary) { [weak self] _ in
                        if let self {
                             
                             
                             
                             
                            HakoMacFollowsProfilesPage(profiles: self.profiles) { [weak self] in
                                if let self {
                                    self.configurationCenterDetail(item, list: self.configurationCenterLatestList ?? list, hadRecipe: hadRecipe)
                                }
                            }
                        }
                    }
                    .onAppear { [weak self] in self?.configurationCenterShownItem = item }
                    .onDisappear { [weak self] in
                        if self?.configurationCenterShownItem == item { self?.configurationCenterShownItem = nil }
                    }
                     
                     
                     
                     
                     
                    .modifier(HakoMacCentrePresentations(model: self, actions: actions))
                )
            } else {
                AnyView(EmptyView())
            }
        }
    }

     
     
     
    fileprivate func chainSheet(_ request: HakoMacChainRequest) -> some View {
        let existing = request.existingID.flatMap { id in configurationLibrary.snapshot.sources.first { $0.id == id } }
        return HakoMacChainSheet(
            existing: existing,
            actions: chainSheetActions(existing: existing),
            close: { [weak self] in self?.configurationCenterChain = nil }
        )
    }

     
    fileprivate func ruleEditorSheet(_ selection: HakoMacLibrarySelection) -> some View {
        HakoMacRuleEditorSheet(
            actions: ruleEditorActions(schemeID: selection.id),
            saved: { [weak self] in Task { await self?.configurationLibrary.reload() } }
        )
    }

     
    func requestNewConfiguration() {
        navigationRequest = .profiles
        configurationCenterSegment = .configurations
        showsConfigurationWizard = true
    }

     
     
    func requestAddSource(purpose: HakoMacSourceImportPurpose) {
        navigationRequest = .profiles
        configurationCenterSegment = purpose == .rules ? .rules : .nodes
        configurationCenterImport = HakoMacImportRequest(purpose: purpose)
    }

     
    func requestConfigurationCenter(_ segment: HakoMacConfigurationCenterSegment) {
        navigationRequest = .profiles
        configurationCenterSegment = segment
    }

    private func configurationCenterListActions(_ list: HakoProfilesListPresentation) -> HakoMacConfigurationCenterListActions {
        var actions = HakoMacConfigurationCenterListActions(
             
            addConfiguration: { [weak self] in self?.showsConfigurationWizard = true },
            addSource: { [weak self] tab in self?.configurationCenterImport = HakoMacImportRequest(purpose: .nodes, tab: tab) },
            addScheme: { [weak self] tab in self?.configurationCenterImport = HakoMacImportRequest(purpose: .rules, tab: tab) },
            activate: { id in list.select(id) },
            delete: { [weak self] item in
                guard let self else { return }
                switch item {
                case .configuration(let id): list.perform(.delete(id: id))
                case .source(let id): Task { await self.configurationLibrary.deleteSource(id) }
                case .scheme(let id): Task { await self.configurationLibrary.deleteRuleScheme(id) }
                case .collection: break
                }
            }
        )
        actions.addChain = { [weak self] in self?.configurationCenterChain = HakoMacChainRequest(existingID: nil) }
         
        actions.reorder = { ids in list.reorder(ids) }
        actions.hasLegacyProfileURLs = profiles.profiles.contains { profile in if case .url = profile.source { return true }; return false }
         
        actions.statusMessage = profiles.statusMessage
        actions.failure = profiles.lastFailure.map { (message: .verbatim($0.message), canRetry: true) }
        actions.retryFailure = { list.perform(.retryFailure) }
         
        actions.backupPage = { AnyView(BackupRestoreView().navigationTitle(Text(hako: .copy("Backup & Restore")))) }
        return actions
    }

    @ViewBuilder
    private func configurationCenterDetail(
        _ item: HakoMacConfigurationCenterItem, list: HakoProfilesListPresentation, hadRecipe: Bool = false
    ) -> some View {
        let snapshot = configurationLibrary.snapshot
        switch item {
        case .configuration(let id):
            if let profile = list.profiles.first(where: { $0.id == id }) {
                let appProfile = profiles.profiles.first { $0.id == id.rawValue }
                HakoMacConfigurationInspector(
                    profile: profile,
                    sources: snapshot.sources.filter(\.suppliesNodes),
                    schemes: configurationLibrary.ruleShelves.flatMap(\.schemes),
                    recipe: snapshot.recipes.first { $0.id == id.rawValue },
                    scriptsActions: scriptsActions(profileID: id),
                    profileURL: appProfile.flatMap { if case .url(let url) = $0.source { url } else { nil } },
                    actions: configurationInspectorActions(list, profile: profile, id: id),
                    door: { [weak self] door in AnyView(self?.configurationDoor(door, profileID: id, list: list)) }
                )
                .id(id)
                .navigationTitle(Text(verbatim: profile.label))
                 
                 
                 
                 
                 
                 
                .hakoMacPopsWhenGone(!profiles.profiles.contains { $0.id == id.rawValue }
                    || (hadRecipe && !snapshot.recipes.contains { $0.id == id.rawValue }))
            }
        case .source(let sourceID):
            if let source = snapshot.sources.first(where: { $0.id == sourceID }) {
                sourcePage(source, list: list)
                    .id(sourceID)
                    .navigationTitle(Text(verbatim: source.label))
                    .hakoMacPopsWhenGone(!snapshot.sources.contains { $0.id == sourceID })
            }
        case .scheme(let schemeID):
            if let scheme = configurationLibrary.ruleShelves.flatMap(\.schemes).first(where: { $0.id == schemeID }) {
                schemePane(scheme, schemeID: schemeID, snapshot: snapshot, list: list)
                .id(schemeID)
                .navigationTitle(Text(verbatim: scheme.displayLabel))
                .hakoMacPopsWhenGone(!configurationLibrary.ruleShelves.flatMap(\.schemes).contains { $0.id == schemeID })
            }
        case .collection(let collectionID):
            if let entry = configurationLibrary.collections.first(where: { $0.id == collectionID }) {
                 
                HakoMacCollectionPane(collection: entry.collection, sourceLabel: entry.source.label, actions: collectionPageActions(entry))
                    .navigationTitle(Text(verbatim: entry.collection.name))
                    .hakoMacPopsWhenGone(!configurationLibrary.collections.contains { $0.id == collectionID })
            }
        }
    }

     
     
    private func schemePane(
        _ scheme: ConfigurationRuleScheme, schemeID: String, snapshot: ConfigurationLibrarySnapshot, list: HakoProfilesListPresentation
    ) -> HakoMacSchemePane {
        let readers = configurationLibrary.configurations(usingScheme: schemeID)
        var pane = HakoMacSchemePane(
            scheme: scheme,
             
             
             
            source: snapshot.sources.first { $0.id == scheme.sourceID }
                ?? (ConfigurationBuiltins.isNative(scheme.id) ? (try? ConfigurationBuiltins.source(for: scheme.id))?.record : nil),
            usedBy: list.profiles.filter { readers.contains($0.id.rawValue) },
            actions: HakoMacSchemePaneActions(
                edit: { [weak self] in self?.configurationCenterEditingScheme = HakoMacLibrarySelection(id: schemeID) },
                duplicate: { [weak self] in
                    Task { @MainActor in
                        guard let self else { return }
                        let label = HakoCopy.string("My Rules", locale: self.preferences.language.locale)
                        do { _ = try await self.configurationLibrary.copyScheme(schemeID, label: label) } catch {
                            self.configurationLibrary.report(error.localizedDescription)
                        }
                    }
                },
                update: { [weak self] in Task { _ = await self?.configurationLibrary.updateSource(scheme.sourceID) } },
                delete: { [weak self] in self?.configurationCenterPendingDelete = .scheme(schemeID) },
                load: { [weak self] in
                    guard let self else { throw ConfigurationLibraryError.unreadable }
                    return try await self.ruleEditorActions(schemeID: schemeID).load()
                }
            )
        )
        pane.updateError = configurationLibrary.updateFailures[scheme.sourceID]
        return pane
    }

    private func configurationInspectorActions(
        _ list: HakoProfilesListPresentation, profile: HakoProfileSnapshot, id: HakoClientKit.Profile.ID
    ) -> HakoMacConfigurationInspectorActions {
        let profiles = self.profiles
        let library = configurationLibrary
        let writes = configurationWrites
         
         
         
         
         
         
        func editNow(_ change: (inout ConfigurationCreationDraft) -> Void) async throws {
             
             
             
            let cached = library.snapshot.generation
            await library.reload()
            let snapshot = library.snapshot
            guard let recipe = snapshot.recipes.first(where: { $0.id == id.rawValue }) else {
                HakoMacDebugLog.note("edit \(id.rawValue): no recipe at generation \(snapshot.generation) — nothing written")
                return
            }
            var draft = ConfigurationCreationAdapter.editingDraft(recipe: recipe, label: profile.label)
            change(&draft)
            HakoMacDebugLog.note("edit \(id.rawValue): generation cached \(cached) fresh \(snapshot.generation) recipe \(recipe.sources.map(\.id)) → sources \(draft.selectedSourceIDs) rule \(draft.selectedRuleID)")
            try await profiles.editConfiguration(draft, id: id.rawValue, generation: snapshot.generation)
            await library.reload()
            let after = library.snapshot
            HakoMacDebugLog.note("edit \(id.rawValue): written, generation \(after.generation) recipe \(after.recipes.first { $0.id == id.rawValue }?.sources.map(\.id) ?? [])")
        }
         
         
         
         
        let failed: @MainActor (Error) -> Void = { [weak self] error in
            NSLog("configuration-centre.edit-failed:%@", error.localizedDescription)
            HakoMacDebugLog.note("edit \(id.rawValue): REFUSED \(error) — \(error.localizedDescription)")
            library.report(error.localizedDescription)
            self?.configurationWriteError = error.localizedDescription
            Task { @MainActor in await library.reload() }
        }
         
         
         
        func edit(_ change: @escaping (inout ConfigurationCreationDraft) -> Void) {
            writes.enqueue({
                if library.snapshot.recipes.contains(where: { $0.id == id.rawValue }) {
                    try await editNow(change)
                } else {
                    try await convertLegacyNow(sources: nil, scheme: nil, change: change)
                }
            }, failure: failed)
        }
        func saveProfileURL(_ change: @escaping (inout HakoMacSubscriptionSettingsState) -> Void) {
            guard let appProfile = profiles.profiles.first(where: { $0.id == id.rawValue }) else { return }
            var state = Self.subscriptionState(appProfile)
            change(&state)
            let actions = subscriptionActions(profileID: id)
            HakoMacDebugLog.note("profile-url \(id.rawValue): save autoUpdate \(state.autoUpdate) interval \(state.updateIntervalHours)")
            Task { @MainActor in
                do {
                    let saved = try await actions.save(state)
                    HakoMacDebugLog.note("profile-url \(id.rawValue): saved autoUpdate \(saved.autoUpdate) interval \(saved.updateIntervalHours)")
                } catch {
                    HakoMacDebugLog.note("profile-url \(id.rawValue): save failed \(error.localizedDescription)")
                    library.report(error.localizedDescription)
                }
            }
        }
         
         
         
         
         
         
         
        func convertLegacyNow(
            sources: [String]?, scheme: String?, change: (inout ConfigurationCreationDraft) -> Void = { _ in }
        ) async throws {
            await library.reload()
            let generation = library.snapshot.generation
            HakoMacDebugLog.note("convert \(id.rawValue): generation \(generation) sources \(sources ?? []) scheme \(scheme ?? "nil")")
            let source = try await profiles.configurationSourceFromLegacy(id.rawValue)
            var draft = ConfigurationCreationDraft()
            let ownRules = "rules-" + source.record.id
             
             
             
             
             
             
            let registeredRules = library.snapshot.rules.contains { $0.id == ownRules }
            let hasRules = registeredRules || (source.record.hasRules && source.record.registersSuppliedRules != false)
            let rule: ConfigurationRuleScheme? = hasRules && !registeredRules
                ? ConfigurationRuleScheme(id: ownRules, label: source.record.label, kind: .supplied, sourceID: source.record.id)
                : nil
            draft.add(source, rule: rule)
             
             
             
             
             
             
             
            if let sources { draft.selectedSourceIDs = sources }
            draft.selectedRuleID = scheme ?? (hasRules ? ownRules : ConfigurationBuiltins.basicRuleID)
            draft.label = profile.label
            draft.dnsMode = .source
            draft.connectAfterCreation = false
            change(&draft)
            try await profiles.editConfiguration(draft, id: id.rawValue, generation: generation)
            await library.reload()
            HakoMacDebugLog.note("convert \(id.rawValue): written, generation \(library.snapshot.generation) recipe \(library.snapshot.recipes.first { $0.id == id.rawValue }?.sources.map(\.id) ?? [])")
        }
         
         
        func setComposition(sources: [String]?, scheme: String?) {
            writes.enqueue({
                if library.snapshot.recipes.contains(where: { $0.id == id.rawValue }) {
                    try await editNow { draft in
                        if let sources { draft.selectedSourceIDs = sources }
                        if let scheme { draft.selectedRuleID = scheme }
                    }
                } else {
                    try await convertLegacyNow(sources: sources, scheme: scheme)
                }
            }, failure: failed)
        }
        var actions = HakoMacConfigurationInspectorActions(
            rename: { label in list.perform(.rename(id: id, label: label)) },
            setSources: { ids in setComposition(sources: ids, scheme: nil) },
            setScheme: { scheme in setComposition(sources: nil, scheme: scheme) },
            activate: { list.select(id) },
            duplicate: { list.perform(.duplicate(id: id)) },
            export: { list.perform(.export(id: id)) },
            editSource: { [weak self] in self?.openSourceEditor(profileID: id.rawValue) },
            delete: { [weak self] in self?.configurationCenterPendingDelete = .configuration(id) },
             
             
             
             
            setSourceUpdates: { on in
                writes.enqueue({
                    try await profiles.setConfigurationSourceUpdates(id.rawValue, enabled: on)
                    await library.reload()
                    HakoMacDebugLog.note("edit \(id.rawValue): followsUpdates \(on) written, generation \(library.snapshot.generation)")
                }, failure: failed)
            },
            openRuntimePreview: { [weak self] in
                self?.openWindowAction?(id: "runtime-preview", value: HakoMacRuntimePreviewRequest(profileID: id.rawValue))
            },
            restoreLastKnownGood: { list.perform(.restoreLastKnownGood(id: id)) },
            setAutoUpdate: { on in saveProfileURL { $0.autoUpdate = on } },
            setInterval: { hours in saveProfileURL { $0.updateIntervalHours = hours } },
            updateSource: { list.perform(.sync(id: id)) },
            stripCredentials: { [weak self] in
                guard let self else { return }
                let actions = self.subscriptionActions(profileID: id)
                Task { @MainActor in
                    do { _ = try await actions.stripCredentials() } catch { library.report(error.localizedDescription) }
                }
            },
            adoptHeldBack: { keyPath in list.perform(.adoptHeldBackUpdate(id: id, keyPath: keyPath)) },
            dismissHeldBack: { list.perform(.dismissHeldBackUpdates(id: id)) }
        )
         
         
        actions.setScope = { sourceID, scope in
            edit { draft in
                var scopes = draft.nodeScopes ?? [:]
                scopes[sourceID] = scope?.isEmpty == true ? nil : scope
                draft.nodeScopes = scopes.isEmpty ? nil : scopes
                if scope?.isEmpty == true { draft.selectedSourceIDs.removeAll { $0 == sourceID } }
                 
                 
                 
                else if !draft.selectedSourceIDs.contains(sourceID) { draft.selectedSourceIDs.append(sourceID) }
            }
        }
        actions.loadScopeChoices = { source in
            try await Self.scopeChoices(source, staged: nil, store: profiles.configurationLibraryStore)
        }
         
        actions.copyProfileURL = {
            guard let appProfile = profiles.profiles.first(where: { $0.id == id.rawValue }),
                  let link = profiles.subscriptionLink(for: appProfile) else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(link, forType: .string)
        }
        return actions
    }

     

     
     
     
    func ruleEditorActions(schemeID: String) -> HakoMacRuleEditorActions {
        let profiles = self.profiles
        let library = configurationLibrary
        func store() throws -> ConfigurationLibraryStore {
            guard let store = profiles.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            return store
        }
        @MainActor func load(previous: ConfigurationRuleDraft?) async throws -> HakoMacRuleEditorState {
            let store = try store()
            let snapshot = try await Task.detached { try store.snapshot() }.value
            library.apply(snapshot)
            let wanted = previous?.schemeID ?? schemeID
            guard let scheme = snapshot.effectiveRuleScheme(wanted) else {
                throw ConfigurationLibraryError.missingDependency(wanted)
            }
            let sets = snapshot.localRuleSets ?? []
            return try await Task.detached {
                _ = ConfigurationRuleCatalog.builtIn
                let draft = try ConfigurationRuleDraft(scheme: scheme, payload: store.ruleSchemePayload(scheme.id))
                let base = try scheme.baseSchemeID.flatMap { id in
                    ConfigurationBuiltins.isNative(id) ? try ConfigurationBuiltins.source(for: id)?.documentJSON : nil
                }
                return HakoMacRuleEditorState(
                    draft: previous.map { draft.preservingIdentity(from: $0) } ?? draft,
                    localSets: sets,
                    resetDocument: base ?? scheme.initialDocumentJSON ?? draft.originalDocument.serialized()
                )
            }.value
        }
        @MainActor func save(_ draft: ConfigurationRuleDraft) async throws -> ConfigurationRuleDraft {
            let snapshot = try await profiles.saveConfigurationRuleCustomization(draft, generation: library.snapshot.generation)
            library.apply(snapshot)
            guard let current = snapshot.ruleSchemeAfterSavingCustomization(draft.schemeID) else {
                throw ConfigurationLibraryError.unreadable
            }
            let store = try store()
            return try await Task.detached {
                try ConfigurationRuleDraft(scheme: current, payload: store.ruleSchemePayload(current.id))
                    .preservingIdentity(from: draft)
            }.value
        }
        var editor = HakoMacRuleEditorActions(
            load: { try await load(previous: nil) },
            save: { draft in try await save(draft) },
            saveLocal: { value in
                library.apply(try await profiles.saveConfigurationLocalRuleSet(value))
                return try await load(previous: nil)
            },
            deleteLocal: { id in
                library.apply(try await profiles.saveConfigurationLocalRuleSet(nil, deleting: id))
                return try await load(previous: nil)
            },
            copy: { draft, name in
                let saved = try await save(draft)
                library.apply(try await profiles.copyConfigurationRuleScheme(
                    saved.schemeID, label: name, generation: library.snapshot.generation
                ))
            },
            download: { input in try await ConfigurationTowerRuleReader.rules(input) }
        )
         
         
        editor.documentText = { try ConfigTransforms.jsonToYAML($0) }
        editor.documentFromText = { try ConfigTransforms.yamlToJSON($0) }
        return editor
    }

     

    private static func subscriptionState(_ profile: Profile) -> HakoMacSubscriptionSettingsState {
        var url = ""
        if case .url(let link) = profile.source { url = link }
        return HakoMacSubscriptionSettingsState(
            url: url,
            autoUpdate: profile.autoUpdate,
            updateIntervalHours: profile.updateIntervalHours,
            canStripCredentials: ProfileMetadataUpdate.strippingSourceCredentials(from: profile) != nil
        )
    }

    private func appProfile(_ id: HakoClientKit.Profile.ID) throws -> Profile {
        guard let profile = profiles.profiles.first(where: { $0.id == id.rawValue }) else {
            throw ConfigurationLibraryError.unreadable
        }
        return profile
    }

     
     
     
    private func subscriptionActions(profileID: HakoClientKit.Profile.ID) -> HakoMacSubscriptionSettingsActions {
        HakoMacSubscriptionSettingsActions(
            save: { [weak self] draft in
                guard let self else { throw ConfigurationLibraryError.unreadable }
                let current = try self.appProfile(profileID)
                try self.profiles.updateMetadata(
                    current, label: current.label, subscriptionURL: draft.url,
                    autoUpdate: draft.autoUpdate, updateIntervalHours: draft.updateIntervalHours
                )
                return Self.subscriptionState(try self.appProfile(profileID))
            },
            stripCredentials: { [weak self] in
                guard let self else { throw ConfigurationLibraryError.unreadable }
                try self.profiles.stripSourceCredentials(try self.appProfile(profileID))
                return Self.subscriptionState(try self.appProfile(profileID))
            }
        )
    }

     

     
     
     
     
    private func scriptsActions(profileID: HakoClientKit.Profile.ID) -> HakoMacScriptsActions {
        func state() throws -> HakoMacScriptsState {
            let profile = try appProfile(profileID)
            let scripts = ScriptLibrary.load().map { HakoMacScriptEntry(id: $0.id, label: $0.label) }
            var fields = 0
            if let data = profile.override.patchJSON.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                fields = object.count
            }
            return HakoMacScriptsState(
                scripts: scripts,
                selectedID: profile.selectedScriptID,
                patchFieldCount: fields,
                exceptions: profile.override.appendRules
            )
        }
        func write(_ change: (inout Profile) -> Void) throws -> HakoMacScriptsState {
            var profile = try appProfile(profileID)
            change(&profile)
            profiles.update(profile)
            return try state()
        }
        func select(_ id: String?) throws -> HakoMacScriptsState {
            try write { profile in
                profile.selectedScriptID = id
                profile.overwriteMode = ProfileOverrideModePolicy.mode(
                    stored: profile.overwriteMode ?? .standard, selectedScriptID: id
                )
            }
        }
         
         
        func store(label: String, body: String) throws -> ConfigScript {
            let existing = ScriptLibrary.load()
            let id = UUID().uuidString
            var candidate = label.trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.isEmpty { candidate = ScriptLibrary.defaultLabel }
            var attempt = 2
            var script = ScriptLibrary.editedScript(id: id, label: candidate, body: body, existing: existing)
            while script == nil, attempt < 100 {
                script = ScriptLibrary.editedScript(id: id, label: "\(candidate) \(attempt)", body: body, existing: existing)
                attempt += 1
            }
            guard let script else { throw ScriptImportError.empty }
            ScriptLibrary.upsert(script)
            return script
        }
        var actions = HakoMacScriptsActions(
            load: { (try? state()) ?? .empty },
            select: { id in try select(id) },
            addLink: { link in
                let body = try await ScriptImport.body(at: link)
                let label = (try? ScriptImport.address(link)).flatMap(ScriptImport.suggestedName(for:))
                    ?? ScriptLibrary.defaultLabel
                let script = try store(label: label, body: body)
                return try select(script.id)
            },
            addManual: { name, body in
                let script = try store(label: name, body: body)
                return try select(script.id)
            },
            remove: { id in
                ScriptLibrary.remove(id: id)
                return try state()
            },
            clearPatch: {
                try write { $0.override.patchJSON = "" }
            },
            removeException: { index in
                try write { profile in
                    if profile.override.appendRules.indices.contains(index) {
                        profile.override.appendRules.remove(at: index)
                    }
                }
            }
        )
        actions.edit = { [weak self] id in self?.openWindowAction?(id: "script-editor", value: HakoMacScriptEditorRequest(scriptID: id)) }
        return actions
    }

    @Published var navigationRequest: HakoMacSecondaryDestination?
     
     
     
     
    let providersRefreshRequests = ProvidersRefreshRequests()

    func requestUpdateAllSources() {
        navigationRequest = .utility(.providers)
        providersRefreshRequests.request()
    }
     
     
     
     
     
     
     
    @Published var activityLens: HakoActivityLens = .connections
    @Published private var stagedProxyGroup: String?
    @Published private var profileRefreshToken = 0
     
     
    @Published private var lanAddress: String?
     
     
     
     
     
     
    @Published private(set) var modeRefusalMessage = ""
     
     
     
     
    let proxiesChannels = HakoRegularRootChannels()
     
     
     
    private var poolContentEpoch = 0
    func nextPoolEpoch() -> Int {
        poolContentEpoch &+= 1
        return poolContentEpoch
    }
     
     
    let rulesChannels = HakoRegularRootChannels()
    @Published private var proxiesHasExpandedGroups = false
     
     
     
    private lazy var proxiesFoldStateSink = HakoBoolSink { [weak self] value in
        guard let self, self.proxiesHasExpandedGroups != value else {
            return
        }
        self.proxiesHasExpandedGroups = value
    }
     
     
    private lazy var rulesFoldStateSink = HakoBoolSink { _ in }

    let vpn: VPNController
    let profiles: ProfilesViewModel
     
     
     
     
    let reviewContainer: URL?
     
     
     
     
    let backupScope: HakoBackupDataScope
    let command: ClashCommandClient
    let stats: StatsModel
    let nodes: NodesModel
     
     
    var proxiesHasExpandedGroupsNow: Bool { proxiesHasExpandedGroups }
    var isTestingLatencyNow: Bool { nodes.isTestingLatency }
    func refreshNodes() async { await nodes.refresh() }
     
     
     
     
     
     
     
    func applyProxiesDisplayPreferences(
        _ value: HakoProxiesDisplayPreferences
    ) {
        value.save()
        proxiesChannels.requestDisplayPreferences(value)
    }
    let networkQuality: NetworkQualityModel
    let stun: STUNTestModel
    let connections: ConnectionsModel
    let proxyShare: ProxyShareModel
    let profileImports: ProfileImportRouter
    let preferences: AppPreferencesModel

    private var revision: UInt64 = 0
    private var cancellables: Set<AnyCancellable> = []
     
     
     
     
     
    lazy var menuBarTraffic = HakoMacMenuBarTrafficFeed(command: command)

    private lazy var connectionRequests = ConnectionRequestCoalescer(
        gestureWindow: { NSEvent.doubleClickInterval },
         
         
         
         
         
         
         
         
        isSettling: { [weak self] in
            guard let status = self?.vpn.status.lowercased() else { return false }
            return self?.vpn.isStarting == true || status == "connecting" || status == "disconnecting"
        }
    )

    init() {
         
         
         
         
         
         
         
        defer {
            Self.current = self
             
             
             
             
            let sink: () -> Void = { [weak nodes = self.nodes] in
                nodes?.latencyPublishQuietUntil = Date(
                    timeIntervalSinceNow: 0.6
                )
            }
            proxiesChannels.uiTransitionSink = sink
            rulesChannels.uiTransitionSink = sink
        }
        let vpn = VPNController()
        self.vpn = vpn
        let reviewContainer = (nil as URL?)
        self.reviewContainer = reviewContainer
         
         
         
         
        if let working = (reviewContainer ?? HakoAppIdentifiers.appGroupContainer)?
            .appendingPathComponent("working", isDirectory: true) {
            HakoMacDebugLog.sink = HakoMacDebugLog.fileSink(working.appendingPathComponent("configuration-centre.debug.log"))
            HakoMacDebugLog.note("app.launch review=\(reviewContainer != nil)")
        }

            backupScope = .ordinary
            profiles = ProfilesViewModel(vpn: vpn)

        command = ClashCommandClient()
        stats = StatsModel()

            nodes = NodesModel()

        networkQuality = NetworkQualityModel()
        stun = STUNTestModel()

            connections = ConnectionsModel()

        proxyShare = ProxyShareModel()
        profileImports = ProfileImportRouter()
        preferences = AppPreferencesModel()

        observeRuntimeChanges()

        observeMenuTracking()
        refreshSnapshot()


        Self.current = self
         
         
         
         
         
         
        HakoMacLaunchGate.shared.onceLaunched { [weak self] in
            self?.installStatusItem()
        }
        visibilityObserver = HakoMacProductVisibilityObserver { [weak self] visible in
            self?.productVisibilityDidChange(visible)
        }
    }

     
     
     
     
    static weak var current: HakoMacSceneModel?

     
    private(set) var statusItem: NSStatusItem?
    private var statusMenuController: HakoMacStatusMenuController?
    private var statusItemSubscriptions: Set<AnyCancellable> = []

     
     
    func focusMainWindow(_ openWindow: OpenWindowAction) {
        if raiseExistingMainWindow() { return }
        openWindow(id: "main")
    }

     
     
     
    private var openWindowAction: OpenWindowAction?

    func rememberWindowOpener(_ openWindow: OpenWindowAction) {
        openWindowAction = openWindow
    }

     
     
    func openSourceEditor(profileID: String) {
        openWindowAction?(
            id: "source-editor",
            value: HakoMacSourceEditorRequest(profileID: profileID)
        )
    }

     
     
    func openMainWindow() {
        if raiseExistingMainWindow() { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindowAction?(id: "main")
    }

    @discardableResult
    private func raiseExistingMainWindow() -> Bool {
        guard let window = NSApplication.shared.windows.first(where: {
            $0.level == .normal && $0.canBecomeKey
        }) else { return false }
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        return true
    }

     
     
     
     
     
    var currentOutboundMode: AppleClientOutboundMode {
        AppleClientOutboundMode(rawValue: outboundMode.rawValue) ?? .rule
    }

    var actions: AppleClientActions {
        let home = AppleClientActions(capability: .home) {
            [weak self] action in
            guard case .home(let command) = action else { return }
            await self?.perform(command)
        }
        let connection = AppleClientActions(capability: .connection) {
            [weak self] action in
            guard case .connection(let intent) = action else { return }
            await self?.performConnection(intent)
        }
        let profiles = AppleClientActions(capability: .profiles) {
            [weak self] action in
            guard let self, case .profiles(let command) = action else { return }
            switch command {
            case .select(let id):
                await self.selectProfile(id)
            case let .adoptHeldBackUpdate(id, keyPath):
                self.adoptHeldBackUpdate(id, keyPath: keyPath)
            case .dismissHeldBackUpdates(let id):
                self.dismissHeldBackUpdates(id)
            default:
                 
                 
                 
                break
            }
        }
        let selection = AppleClientActions(capability: .profileSelection) {
            [weak self] action in
            guard case .selectProfile(let id) = action else { return }
            await self?.selectProfile(id)
        }
        let routing = AppleClientActions(capability: .outboundMode) {
            [weak self] action in
            guard case .setOutboundMode(let mode) = action else { return }
            await self?.setOutboundMode(mode)
        }
        let utilities = AppleClientActions(capability: .utilities) {
            action in
            guard case .openUtility = action else { return }
        }
        let more = AppleClientActions(capability: .more) { action in
            guard case .openMore = action else { return }
        }
        return (try? AppleClientActions.composing([
            home,
            connection,
            profiles,
            selection,
            routing,
            utilities,
            more,
        ])) ?? .unavailable
    }

    func refreshVPNInstallation() async {
        await vpn.refreshSystemVPNInstallation()
        rebind()
        refreshSnapshot()
    }

    func prepare() async {

             
             
             
            vpn.legacySettingsMigration = vpn.migrateLegacyGlobalSettingsIfNeeded()

        profiles.load()
         
        recomputeHomeRuleTally()
        profiles.selectSoleProfileIfNeeded()
        profileImports.importSharedFiles()
        rebind()
        prewarmEditorPreparations()
        await vpn.refresh()
        rebind()
        connections.sync(productIsVisible && command.isConnected)
        proxyShare.updateAPIAvailability(command.isConnected)
        if command.isConnected {
            await command.refreshMetadata()
            await nodes.refresh()
            await proxyShare.refresh()
        }
        startAutomaticResourceRefresh()
         
         
         
         
         
        ICloudAutoBackup.shared.start()
        refreshSnapshot()
    }

     
     
    private func startAutomaticResourceRefresh() {
        guard !false,
              automaticRefreshDriver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { await BackgroundRefresh.scanOnForegroundIfDue() }
        }
        automaticRefreshDriver = Task {
            await BackgroundRefresh.scanOnForegroundIfDue()
            while !Task.isCancelled {
                try? await Task.sleep(
                    nanoseconds: UInt64(
                        BackgroundRefresh.foregroundScanInterval
                    ) * 1_000_000_000
                )
                guard !Task.isCancelled else { break }
                await BackgroundRefresh.scanOnForegroundIfDue()
            }
        }
    }

    deinit {
        automaticRefreshDriver?.cancel()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

     
     
     
     
    private var legacySettingsAttention: LegacySettingsAttention? {
        guard let result = vpn.legacySettingsMigration else { return nil }
        return LegacySettingsAttention.make(from: result, profiles: profiles.profiles)
    }

     
     
     
    func performLegacySettingsAttention(actionID: String) {
        guard let attention = legacySettingsAttention,
              let action = attention.actions.first(where: { $0.id == actionID })
        else { return }
        switch action.resolution {
        case .openProfile, .openScripts:
             
             
             
            navigationRequest = .profiles
        default:
            guard let workingDirectory = HakoAppIdentifiers.appGroupContainer?
                .appendingPathComponent("working", isDirectory: true)
            else { return }
            if let fresh = LegacySettingsResolver.perform(
                action.resolution,
                attentionID: attention.id,
                workingDirectory: workingDirectory
            ) {
                vpn.legacySettingsMigration = fresh
            }
             
             
             
            profiles.load()
            refreshSnapshot()
        }
    }

    func dismissModeRefusalMessage() {
        modeRefusalMessage = ""
    }

     
     
     
    func cancelStart() {
        Task { await performPrimaryAction(.cancel) }
    }

    func performPrimaryAction() {
         
         
        guard let intent = latestSnapshot.connection.primaryIntent else { return }
        Task { await performConnection(intent) }
    }

    func selectProfile(_ id: HakoClientKit.Profile.ID) async {
        guard let profile = profiles.profiles.first(
            where: { $0.id == id.rawValue }
        ) else { return }
        guard await profiles.selectAndWait(profile) else {
            refreshSnapshot()
            return
        }
        activeRuntimeDidChange()
        refreshSnapshot()
    }

     
     
    func adoptHeldBackUpdate(_ id: HakoClientKit.Profile.ID, keyPath: String) {
        guard let profile = profiles.profiles.first(where: { $0.id == id.rawValue }) else { return }
        do {
            try profiles.adoptHeldBackUpdate(profile, keyPath: keyPath)
            activeRuntimeDidChange()
        } catch {
            Logger(subsystem: HakoPerf.subsystem, category: "profiles")
                .error("adopt held-back update failed: \(String(describing: error), privacy: .public)")
        }
        refreshSnapshot()
    }

     
    func dismissHeldBackUpdates(_ id: HakoClientKit.Profile.ID) {
        guard let profile = profiles.profiles.first(where: { $0.id == id.rawValue }) else { return }
        do {
            try profiles.dismissHeldBackUpdates(profile)
        } catch {
            Logger(subsystem: HakoPerf.subsystem, category: "profiles")
                .error("dismiss held-back updates failed: \(String(describing: error), privacy: .public)")
        }
        refreshSnapshot()
    }

    func setOutboundMode(_ mode: AppleClientOutboundMode) async {
        guard let profile = currentProfile,
              let storedMode = Profile.OutboundMode(
                  rawValue: mode.rawValue
              )
        else { return }

         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        if OutboundModeSelection.changesNothing(
            requested: storedMode,
            stored: profiles.outboundMode(for: profile),
            running: command.isConnected ? command.mode : nil
        ) {
            return
        }

        if storedMode == .global, command.isConnected {
             
             
             
             
             
            var verdict = GlobalModeConfirmation.verdict(
                groupCount: nodes.groups.count,
                selectionConfirmed: await nodes.ensureGlobalProxySelection()
            )
            if verdict == .notYetKnown {
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                try? await Task.sleep(nanoseconds: 400_000_000)
                verdict = GlobalModeConfirmation.verdict(
                    groupCount: nodes.groups.count,
                    selectionConfirmed: await nodes.ensureGlobalProxySelection()
                )
            }
            switch verdict {
            case .confirmed:
                break
            case .notYetKnown:
                 
                 
                 
                 
                modeRefusalMessage = """
                    The core has not reported its proxy groups yet, so \
                    Global mode was not applied. Try again in a moment.
                    """
                return
            case .refused:
                 
                 
                 
                 
                modeRefusalMessage =
                    GlobalProxySelectionPolicy.refusal(groups: nodes.groups)
                    ?? """
                        The GLOBAL group resolves to a direct connection, not \
                        a proxy. Global mode sends every flow through GLOBAL, \
                        so select a proxy in that group first.
                        """
                return
            }
        }

        do {
             
             
             
             
             
             
             
            try profiles.updateOutboundMode(
                profileID: profile.id,
                mode: storedMode,
                kernelCarriesTheChange: command.isConnected
            )
            if command.isConnected {
                await command.setMode(storedMode.rawValue)
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                if command.isConnected, command.mode != storedMode.rawValue {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    await command.setMode(storedMode.rawValue)
                }
                if command.isConnected, command.mode != storedMode.rawValue {
                    modeRefusalMessage = """
                        The running tunnel did not accept the mode change. \
                        The profile was saved; the mode applies on the next \
                        connect.
                        """
                }
            }
        } catch {
             
             
            modeRefusalMessage = """
                The outbound mode could not be saved to this profile. \
                \(error.localizedDescription)
                """
            return
        }
        refreshSnapshot()
    }

     
     
     
     
     
     
     
     
     
     
     
     
    private func performConnection(
        _ intent: AppleClientConnectionIntent,
        beforeRun: (@MainActor @Sendable () -> Void)? = nil
    ) async {
        await connectionRequests.run(interruptInFlight: intent == .disconnect && vpn.isStarting) { [weak self] in
            await beforeRun?()
            await self?.performConnectionUncoalesced(intent)
            return true
        }
    }

    private func performConnectionUncoalesced(
        _ intent: AppleClientConnectionIntent
    ) async {
        switch intent {
        case .disconnect:
            await vpn.stop()
        case .connect, .activateSystemExtension,
             .updateSystemExtension, .installConfiguration:
            if let currentProfile {
                _ = await profiles.connectFromHome(
                    currentProfile, forceReactivation: false
                )
            } else {
                _ = await vpn.start()
            }
        }
        rebind()
        refreshSnapshot()
    }

     
     
     
    func applyFirstLoadRefreshes() {
        let updates = ProviderFirstLoadRetry.takeRuntimeUpdates()
        guard !updates.isEmpty else { return }
        Task { [command] in
            for update in updates {
                _ = await command.sideUpdateProvider(update)
            }
        }
    }

    func open(_ url: URL) {
        if let route = HakoSystemRoute(url: url) {
            handleSystemRoute(route)
            return
        }
        profileImports.open(url)
        if url.isFileURL {
            navigationRequest = .profiles
        }
    }

     
     
     
     
     
     
    private func handleSystemRoute(_ route: HakoSystemRoute) {
        Task { [weak self] in
            guard let self else { return }
             
             
             
            await self.vpn.refresh()
            let plan = HakoMacSystemRoutePlan.plan(
                for: route,
                isActive: HakoSystemVPNPolicy.isActive(self.vpn.status)
            )
            if let destination = plan.destination {
                self.navigationRequest = destination
            }
            if let mode = plan.mode {
                await self.setOutboundMode(mode)
            }
            switch plan.command {
            case .start?:
                await self.performConnection(.connect)
            case .stop?:
                await self.performConnection(.disconnect)
            case .unchanged?, nil:
                break
            }
        }
    }

    func secondaryContent(
        _ destination: HakoMacSecondaryDestination
    ) -> AnyView {
        switch destination {
        case .profiles:
             
             
             
            AnyView(
                ProfileCenterAdapter(
                    profiles: self.profiles,
                    importRouter: self.profileImports,
                    ownsNavigationContainer: false,
                    palette: HakoMacPlatformPresentation.palette,
                    onActiveRuntimeChanged: {
                        [weak self] in
                        self?.activeRuntimeDidChange()
                    },
                    capabilityInterceptor: { [weak self] destination in
                        guard let self,
                              case .sourceEditor(let id) = destination
                        else { return false }
                        self.openSourceEditor(profileID: id.rawValue)
                        return true
                    },
                    listPresentation: { list in
                        AnyView(self.configurationCenter(list))
                    }
                )
                .hakoToolbarUnlessInPanel {
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                    ToolbarItemGroup(placement: .primaryAction) {
                        if self.profiles.hasSubscriptionProfile {
                             
                             
                             
                             
                            Button {
                                Task { await self.configurationLibrary.updateEverything() }
                            } label: {
                                Label {
                                    Text(hako: .copy("Update All"))
                                } icon: {
                                    Image(systemName: HakoSymbol.arrowTriangle2Circlepath.name)
                                }
                            }
                            .disabled(self.configurationLibrary.isUpdatingAll || self.configurationLibrary.isBusy)
                            .help(Text(hako: .copy("Update All")))
                            .accessibilityIdentifier("profile-center.sync-all")
                        }
                    }
                }
            )
        case .proxies:
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
            AnyView(
                HakoMacProxiesGhostChrome(model: self).equatable()
            )
        case .rules:
             
             
             
            AnyView(
                Color.clear
                    .searchable(
                        text: Binding(
                            get: { [weak self] in
                                self?.rulesChannels.searchText ?? ""
                            },
                            set: { [weak self] in
                                self?.rulesChannels.searchText = $0
                            }
                        ),
                        prompt: Text("Search rules")
                    )
            )
        case .activeRules:
            AnyView(ActiveRulesView(command: command))
        case .dnsQuery:
            AnyView(DNSQueryView(command: command))
        case .runtimeConfiguration:
            runtimeConfigurationContent()
        case .configuration:
            AnyView(
                GoldenFlowMoreDestinationAdapter(
                    vpn: vpn,
                    command: command,
                    preferences: preferences,
                    destination: .coreBehavior,
                    usesRegularDetailLayout: true
                )
            )
        case .utility(let destination):
            AnyView(
                GoldenFlowUtilitiesDestinationAdapter(
                    vpn: vpn,
                    command: command,
                    connections: connections,
                    networkQuality: networkQuality,
                    stun: stun,
                    proxyShare: proxyShare,
                    destination: destination,
                    activityLens: Binding(
                        get: { self.activityLens },
                        set: { self.activityLens = $0 }
                    ),
                    usesRegularDetailLayout: true,
                    loadsPersistedLogs:
                        !false
                )
                 
                 
                 
                .environment(\.hakoProvidersRefreshRequests, providersRefreshRequests)
            )
        case .more(let destination):
            AnyView(
                GoldenFlowMoreDestinationAdapter(
                    vpn: vpn,
                    command: command,
                    preferences: preferences,
                    destination: destination,
                    usesRegularDetailLayout: true
                )
            )
        }
    }

    private func runtimeConfigurationContent() -> AnyView {
        guard let profile = currentProfile else {
            return AnyView(
                HakoMacSecondaryUnavailableView(
                    destination: .runtimeConfiguration
                )
            )
        }
         
         
         
        let isActive = profiles.activeProfileID == profile.id
        let verdictsHome: URL? = reviewContainer
            ?? HakoAppIdentifiers.appGroupContainer
        return AnyView(
            HakoMacRuntimeConfigurationPage(
                profile: profile,
                isActive: isActive,
                fetchTexts: { [weak self] in
                    guard let self else { return (nil, nil, nil) }
                    return (
                        self.profiles.capturedSourceText(for: profile),
                        self.profiles.previewText(for: profile),
                        self.profiles.sourceYAML(for: profile)
                    )
                },
                blockedRuleSets: isActive
                    ? { [verdictsHome] in
                        guard let verdictsHome else { return [] }
                        return ProviderCompileVerdicts
                            .load(
                                coreHome: verdictsHome
                                    .appendingPathComponent("working")
                            )
                            .blockedRuleProviders
                    }
                    : nil
            )
            .equatable()
        )
    }

    private func savePayloadDialerEdits(
        _ edits: [ProxyPayloadDialerEdit],
        profileID: String
    ) throws {
        guard !edits.isEmpty else {
            return
        }
        guard let latest = profiles.profiles.first(
            where: { $0.id == profileID }
        ) else {
            throw PipelineError.sourceUnavailable(
                "the profile is no longer available"
            )
        }
        var working = try profiles.providerDefinitionsDraft(for: latest)
        for edit in edits {
            try working.setPayloadDialer(
                provider: edit.provider,
                node: edit.node,
                dialerProxy: edit.dialerProxy
            )
        }
        try profiles.updateProviderDefinitions(working)
    }

    private var currentProfile: Profile? {
        return HomeProfileResolution.workingProfile(in: profiles)
    }

    private var outboundMode: Profile.OutboundMode {
        HakoMacOutboundModeResolution.resolve(
            vpnStatus: vpn.status,
            liveMode: command.mode,
            saved: currentProfile.map(profiles.outboundMode) ?? .rule
        )
    }

     
     
     
     
    var menuBarProxyCatalog: HakoMacMenuProxyCatalog {
        HakoMacMenuProxyCatalog.make(
            groups: nodes.groups,
            mode: ProxyBrowsingVisibility.Mode(coreValue: outboundMode.rawValue),
            delays: nodes.delays,
            testing: nodes.testingNames
        )
    }

     
     
     
     
    fileprivate func menuBarLatency(delays: [String: Int], testing: Set<String>) -> [String: HakoProxyLatencyState] {
        HakoMacMenuProxyCatalog.make(
            groups: nodes.groups,
            mode: ProxyBrowsingVisibility.Mode(coreValue: outboundMode.rawValue),
            delays: delays,
            testing: testing
        ).groups.reduce(into: [:]) { all, group in
            all.merge(group.latency) { _, new in new }
        }
    }

    private var selectedRoute: (name: String?, delay: Int?) {
         
         
         
         
         
         
         
        guard outboundMode == .global,
              let group = nodes.groups.first(
                  where: { $0.name == "GLOBAL" }
              )
        else { return (nil, nil) }
        let route =
            group.resolvedNow.isEmpty ? group.now : group.resolvedNow
        guard !route.isEmpty else { return (nil, nil) }
        return (route, nodes.delays[route])
    }

    private var connectionPhase: AppleClientConnectionPhase {
        switch vpn.status.lowercased() {
        case "connected", "reasserting":
            .connected
        case "connecting":
            .preparing
        case "disconnecting":
            .disconnecting
        case "invalid", "unknown", "unavailable":
            .unavailable
        default:
            .disconnected
        }
    }

    private func trafficSnapshot(_ traffic: ClashTrafficSnapshot) -> AppleClientTrafficSnapshot {
        AppleClientTrafficSnapshot(
            uploadBytesPerSecond: traffic.upload,
            downloadBytesPerSecond: traffic.download,
            uploadTotalBytes: traffic.uploadTotal,
            downloadTotalBytes: traffic.downloadTotal,
            uploadRatesBytesPerSecond: traffic.uploadHistory,
            downloadRatesBytesPerSecond: traffic.downloadHistory,
            coreStartedAtUnixSeconds: command.runtimeDiagnostics?.startTimeUnix ?? 0
        )
    }

    private func refreshSnapshot() {
        revision &+= 1
        let profile = currentProfile
        let selected = profile.flatMap { stored in
            try? HakoClientKit.Profile.ID(stored.id)
        }.map {
            AppleClientProfileSnapshot(
                id: $0,
                label: profile?.label ?? ""
            )
        }
        let mode = outboundMode
        let route = selectedRoute
        let info = AppBuildInfo.current()

        publish(AppleClientSnapshot(
            revision: revision,
            selectedProfile: selected,
            connection: AppleClientConnectionSnapshot(
                phase: connectionPhase,
                selectedRouteName: route.name,
                selectedRouteDelayMilliseconds: route.delay,
                issue: vpn.reportableLastError.isEmpty
                    ? nil
                    : AppleClientFailure(
                        code: .connection,
                        title: "Connection",
                        message: vpn.reportableLastError
                    )
            ),
            home: AppleClientHomeSnapshot(
                routing: AppleClientRoutingSnapshot(
                    mode:
                        AppleClientOutboundMode(
                            rawValue: mode.rawValue
                        ) ?? .rule
                ),
                traffic: trafficSnapshot(command.traffic),
                proxyGroupCount: nodes.groups.count,
                proxyCount: nodes.nodeCatalog.count,
                ruleCount: homeRuleTally?.count ?? command.rules.count,
                connection:
                    HakoHomeConnectionPresenter.presentation(
                        for: HakoHomeConnectionFacts(
                            activeProfileName: profile?.label,
                            vpnStatus: vpn.status,
                            errorMessage: vpn.reportableLastError,
                            vpnAuthorization: vpn.systemVPNAuthorization,
                            allowsSystemVPNProfileReset:
                                vpn.systemVPNProfileResetAvailable,
                            isSwitchingProxy:
                                nodes.isSwitchingProxy,
                            mode: mode.rawValue,
                            selectedProxyName: route.name,
                            selectedProxyDelayMilliseconds:
                                route.delay
                        )
                    ),
                favoriteCards: HomeFavoriteCardPreferences().load(),
                trafficScope: TrafficStatisticsSettings.onlyProxy()
                    ? .proxiedOnly
                    : .allTraffic,
                proxies: HakoHomeDomainSnapshot(
                    count: nodes.nodeCatalog.count,
                    countUnit: "proxies",
                    names: nodes.groups.map(\.name)
                ),
                rules: HakoHomeDomainSnapshot(
                    count: homeRuleTally?.count,
                    countUnit: "rules",
                    names: homeRuleTally?.targets ?? []
                ),
                 
                 
                 
                 
                 
                egress: egressSnapshot,
                lanAddress: lanAddress,
                isProfileActionInFlight:
                    profiles.isActivationInFlight
            ),
            profiles: HakoProfilesSnapshot(
                profiles: profiles.profiles.compactMap(
                    profileSnapshot
                ),
                statusMessage: profiles.statusMessage,
                featureAvailability: .full
            ),
            utilities: HakoUtilitiesSnapshot(
                nativeAPIConnected: command.isConnected,
                activeConnectionCount:
                    connections.activeConnectionCount,
                requestCount: connections.requestLog.count,
                logCount: command.logs.count,
                isRecordingLogs: HakoLogSettings.isRecording(
                    from: GlobalConfig.appGroupDefaults
                ),
                logRetentionTitle: HakoLogSettings.retention(
                    from: GlobalConfig.appGroupDefaults
                ).title,
                networkQualitySummary: networkQuality.summary,
                stunSummary: stun.summary,
                proxyShareStatus: proxyShare.phase.title,
                proxyShareEnabled: proxyShare.status.enabled
            ),
            more: HakoMoreSnapshot(
                dnsOnlyActive:
                    NetworkOperatingModeStore().current == .dnsOnly,
                about: HakoAboutSnapshot(
                    appVersion: info.appVersion,
                    buildNumber: info.buildNumber,
                    sourceRevision: info.sourceRevision,
                    coreVersion: info.coreVersion
                ),
                 
                 
                 
                 
                 
                overrideCounts: OverrideEntryCount.moreCounts(
                    in: currentProfile.map { profiles.settingsProfile(for: $0) }?
                        .override.patchJSON ?? ""
                ),
                attention: legacySettingsAttention?.snapshot
            ),
            capabilities: AppleClientCapabilities([
                .home: .available,
                .profiles: .available,
                .proxies:
                    profile == nil
                        ? .unavailable(.requiresProfile)
                        : .available,
                .activity:
                    command.isConnected
                        ? .available
                        : .unavailable(.requiresConnection),
                .rules:
                    profile == nil
                        ? .unavailable(.requiresProfile)
                        : .available,
                .dns:
                    profile == nil
                        ? .unavailable(.requiresProfile)
                        : .available,
                .utilities: .available,
                .more: .available,
                .configuration:
                    profile == nil
                        ? .unavailable(.requiresProfile)
                        : .available,
                .connection:
                    profile == nil
                        ? .unavailable(.requiresProfile)
                        : .available,
                .profileSelection:
                    profiles.profiles.isEmpty
                        ? .unavailable(.requiresProfile)
                        : .available,
                .outboundMode:
                    profile == nil
                        ? .unavailable(.requiresProfile)
                        : .available,
            ])
        ))
    }

    private func profileSnapshot(
        _ profile: Profile
    ) -> HakoProfileSnapshot? {
        guard let id = try? HakoClientKit.Profile.ID(profile.id)
        else { return nil }
        let source: HakoProfileSourceKind
        let sourceSummary: HakoDisplayText
        switch profile.source {
        case .url:
            source = .remote
            sourceSummary = "Profile URL"
        case .file(let name):
            source = .file
            sourceSummary = .copy(name)
        case .clipboard:
            source = .clipboard
            sourceSummary = "Local profile"
        }
        let isCurrent = profile.id == profiles.activeProfileID
        return HakoProfileSnapshot(
            id: id,
            label: profile.label,
            source: source,
            sourceSummary: sourceSummary,
            lastUpdatedAt: profile.lastUpdatedAt,
            autoUpdate: profile.autoUpdate,
            updateIntervalHours: profile.updateIntervalHours,
            isCurrent: isCurrent,
            isBusy: profile.id == profiles.busyProfileID,
            canEditSource: true,
            canDelete: !isCurrent,
            deleteSubtitle:
                isCurrent
                    ? "Switch profiles before removing this one"
                    : "Remove this profile from Clash",
            runtimeSummary:
                isCurrent ? "Active runtime" : "Saved profile",
             
             
             
            heldBackUpdates: (profile.suppressedUpdates ?? []).map {
                HakoProfileHeldBackUpdate(
                    keyPath: $0.keyPath,
                    change: HakoProfileHeldBackUpdate.Change(rawValue: $0.change.rawValue) ?? .changed,
                    newValue: $0.newValue,
                    appValue: $0.appValue
                )
            }
        )
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private var egressSnapshot: HakoHomeEgressSnapshot {
        let connected = vpn.status == "connected"
        let address = stats.egressIP
        let hasResult =
            connected
            && !address.isEmpty
            && address != "—"
            && address != "checking…"
            && address != "VPN not connected"
            && !address.hasPrefix("error")
        let detail = [stats.egressCountryName, stats.egressISP]
            .filter { !$0.isEmpty && $0 != "—" }
            .joined(separator: " · ")
        return HakoHomeEgressSnapshot(
            address: hasResult ? address : nil,
            flag: hasResult
                ? EgressLookupResult.flagEmoji(
                    countryCode: stats.egressCountryCode
                )
                : "",
            detail: hasResult ? detail : "",
            canRefresh: connected,
            isChecking: connected && address == "checking…"
        )
    }

     
     
     
    private var locale: Locale { preferences.language.locale }

     
     
     
     
     
     
     
     
     
    private func perform(_ command: HakoHomeCommand) async {
        switch command {
        case .performPrimaryAction(let action):
            await performPrimaryAction(action)
        case .openProfiles:
             
             
             
             
             
             
            break
        case .openProxies:
            navigationRequest = .proxies
        case .openRules:
            navigationRequest = .rules
        case .openRuntimeConfiguration:
            navigationRequest = .runtimeConfiguration
        case .setCards(let cards):
            HomeFavoriteCardPreferences().save(
                HakoHomeCatalog.normalized(cards)
            )
            refreshSnapshot()
        case .setTrafficScope(let scope):
            let onlyProxy = scope == .proxiedOnly
            guard onlyProxy != TrafficStatisticsSettings.onlyProxy() else {
                return
            }
            TrafficStatisticsSettings.setOnlyProxy(onlyProxy)
             
            self.command.applyTrafficStatisticsPreference()
            refreshSnapshot()
        case .refreshExternalIP:
            await stats.checkEgressIP()
            refreshSnapshot()
        case .refreshLANIP:
            lanAddress = LANAddressInventory.current().first
        case .showConnectionIssue:
             
             
             
            break
        }
    }

    private func performPrimaryAction(_ action: HakoHomePrimaryAction) async {
        switch action {
        case .openProfiles:
            navigationRequest = .profiles
        case .connect, .retry:
            await performConnection(.connect)
        case .cancel:
            await performConnection(.disconnect) { [weak self] in
                self?.profiles.cancelActivation()
            }
        case .disconnect:
            await performConnection(.disconnect)
        case .retryProxy:
            await vpn.forceRestart()
            rebind()
        case .none:
            break
        }
    }

    private func rebind() {
        command.bind(session: vpn.session)
        command.sync(vpnStatus: vpn.status)
        stats.bind(session: vpn.session, command: command)
        nodes.bind(command: command)
        stun.bind(command: command)
        proxyShare.bind(command: command)
         
         
         
        proxyShare.bind(profileYAML: { [weak self] in
            guard let self,
                  let active = self.profiles.profiles.first(where: { $0.id == self.profiles.activeProfileID })
            else { return nil }
            return self.profiles.effectiveYAML(for: active)
        }, lanListenerPermitted: {
            LocalNetworkPermission.isPermitted(UserDefaults(suiteName: HakoAppIdentifiers.appGroup))
        })
         
         
        proxyShare.bind(kernelShare: profiles.kernelLANShareBinding())
    }

     
     
     
    func pooledDetailOverlay(
        for root: HakoRootDestination?
    ) -> AnyView {
        AnyView(
            ZStack {
                HakoMacPooledRootSlot(
                    destination: .proxies,
                    visible: root == .proxies,
                    channels: proxiesChannels,
                    foldStateSink: proxiesFoldStateSink,
                    background: HakoMacPlatformPresentation.palette.canvas,
                    content: { [weak self] in
                        guard let self else { return AnyView(EmptyView()) }
                        return AnyView(
                            HakoMacFrozenPoolContent(
                                freeze: HakoMacPoolFreeze(
                                     
                                     
                                     
                                     
                                    frozen: root != .proxies
                                        || self.nodes.isTestingLatency,
                                    epoch: self.nextPoolEpoch()
                                )
                            ) {
                                 
                                 
                                 
                                 
                                 
                                 
                                HakoDeferredPageContent {
                                SessionProxiesRailRoot(
                                    vpn: self.vpn,
                                    command: self.command,
                                    nodes: self.nodes,
                                    profiles: self.profiles,
                                    profileRefreshToken:
                                        self.profileRefreshToken,
                                    avoidsLiveProviderStore:
                                        false,
                                    stagedGroup: Binding(
                                        get: { [weak self] in
                                            self?.stagedProxyGroup
                                        },
                                        set: { [weak self] in
                                            self?.stagedProxyGroup = $0
                                        }
                                    )
                                )
                                } placeholder: {
                                    HakoMacPlatformPresentation.palette
                                        .canvas.ignoresSafeArea()
                                }
                            }
                            .equatable()
                        )
                    }
                )
                .allowsHitTesting(root == .proxies)

                HakoMacPooledRootSlot(
                    destination: .rules,
                    visible: root == .rules,
                    channels: rulesChannels,
                    foldStateSink: rulesFoldStateSink,
                    background: HakoMacPlatformPresentation.palette.canvas,
                    content: { [weak self] in
                        guard let self else { return AnyView(EmptyView()) }
                        return AnyView(
                            HakoMacFrozenPoolContent(
                                freeze: HakoMacPoolFreeze(
                                    frozen: root != .rules,
                                    epoch: self.nextPoolEpoch()
                                )
                            ) {
                                HakoMacConnectionStateContent(
                                    initialValue: self.command.isConnected,
                                    updates: self.command.$isConnected.eraseToAnyPublisher()
                                ) { connected in
                                    SessionRulesRailRoot(
                                        command: self.command,
                                        canInspectActiveRules: connected,
                                        profiles: self.profiles,
                                        openProxiesGroup: { [weak self] group in
                                            guard let self else { return }
                                             
                                             
                                             
                                             
                                            self.stagedProxyGroup = group
                                            self.proxiesChannels
                                                .requestOpenGroup(group)
                                            self.navigationRequest = .proxies
                                        }
                                    )
                                }
                            }
                            .equatable()
                        )
                    }
                )
                .allowsHitTesting(root == .rules)
            }
        )
    }

     
     

     
     
     
     
     
     
    private func prewarmEditorPreparations() {
        guard let profile = currentProfile else { return }
        let raw = profiles.runtimeSourceYAML(for: profile)
        Task { @MainActor in
            await ProfileProxyChainsView.prewarm(
                profile: profile, rawYAML: raw
            )
            if let raw {
                await ProfilesViewModel.prewarmProviderDraft(
                    profile: profile, raw: raw
                )
            }
             
             
             
             
             
            await ProfileDNSSettingsAdapter.prewarm(
                profile: profile,
                sourceYAML: self.profiles.uiProjectedYAML(for: profile),
                sidecar: ProfileDNSSettingsAdapter.sidecarYAML(
                    profileID: profile.id
                )
            )
        }
    }

     
     
     
     
     
    private let editorPrewarm = HakoMacQuietPeriod(seconds: 2)

    private func activeRuntimeDidChange() {
        profileRefreshToken &+= 1
         
         
         
        proxiesChannels.contentGeneration &+= 1
        nodes.noteRouteChanged()
        Task {
            await nodes.refresh()
        }
        editorPrewarm.request { [weak self] in
            self?.prewarmEditorPreparations()
        }
        recomputeHomeRuleTally()
        refreshSnapshot()
    }

     
     
     
     
     
     
     
     
     
     
    private var homeRuleTally: (count: Int, targets: [String])?

    private func recomputeHomeRuleTally() {
        let profile = currentProfile
         
         
         
         
         
        let projected = profile.flatMap {
            profiles.effectiveYAML(for: $0)
        }
        Task.detached(priority: .userInitiated) { [weak self] in
            let tally = ProfileConfigTally.make(sourceYAML: projected)
            let overview = RulesOverviewModel.make(sourceYAML: projected)
            let targets = overview.buckets.prefix(3).map {
                "\($0.target) \($0.rules.count)"
            }
            await MainActor.run {
                guard let self else { return }
                self.homeRuleTally = tally.map { ($0.rules, Array(targets)) }
                self.refreshSnapshot()
            }
        }
    }

    private func observeRuntimeChanges() {
         
         
         
         
         
         
         
        for publisher in [
            vpn.objectWillChange,
            profiles.objectWillChange,
            nodes.objectWillChange,
            connections.objectWillChange,
            networkQuality.objectWillChange,
            stun.objectWillChange,
            proxyShare.objectWillChange,
            preferences.objectWillChange,
             
             
             
             
             
             
             
            profileImports.objectWillChange,
        ] {
            publisher.sink { [weak self] _ in
                self?.scheduleRefresh()
            }
            .store(in: &cancellables)
        }

        command.$traffic
            .sink { [weak self] traffic in
                 
                 
                guard let self, productIsVisible else { return }
                trafficFeed.traffic = trafficSnapshot(traffic)
            }
            .store(in: &cancellables)
        for publisher in [
            command.$isConnected.map { _ in () }.eraseToAnyPublisher(),
            command.$mode.map { _ in () }.eraseToAnyPublisher(),
            command.$lastError.map { _ in () }.eraseToAnyPublisher(),
            command.$rules.map { _ in () }.eraseToAnyPublisher(),
            command.$runtimeDiagnostics.map { _ in () }.eraseToAnyPublisher(),
            command.$proxiesData.map { _ in () }.eraseToAnyPublisher(),
            command.$peerCoreVersion.map { _ in () }.eraseToAnyPublisher(),
            command.$peerCapabilities.map { _ in () }.eraseToAnyPublisher(),
            command.$previousGoCrashReport.map { _ in () }.eraseToAnyPublisher(),
            command.$previousOOMEvidence.map { _ in () }.eraseToAnyPublisher(),
            command.$isCollectingMemory.map { _ in () }.eraseToAnyPublisher(),
            command.$memoryActionMessage.map { _ in () }.eraseToAnyPublisher(),
             
             
            command.$logs.map(\.count).removeDuplicates()
                .throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)
                .map { _ in () }.eraseToAnyPublisher(),
        ] {
            publisher.sink { [weak self] in
                self?.scheduleRefresh()
            }
            .store(in: &cancellables)
        }

        vpn.$status
            .removeDuplicates()
            .sink { [weak self] status in
                guard let self else { return }
                command.sync(vpnStatus: status)
            }
            .store(in: &cancellables)

        command.$isConnected
            .removeDuplicates()
            .sink { [weak self] connected in
                guard let self else { return }
                connections.sync(productIsVisible && connected)
                proxyShare.updateAPIAvailability(connected)
                if connected {
                    Task {
                        await self.nodes.refresh()
                        await self.proxyShare.refresh()
                    }
                }
            }
            .store(in: &cancellables)
    }
}

 
 
 
 
 
 
 
 
 
 
 
enum HakoMacOutboundModeResolution {
    static func resolve(vpnStatus: String, liveMode: String, saved: Profile.OutboundMode) -> Profile.OutboundMode {
        let tunnelUp = ["connected", "reasserting"].contains(vpnStatus.lowercased())
        if tunnelUp, liveMode != "—", let live = Profile.OutboundMode(rawValue: liveMode.lowercased()) {
            return live
        }
        return saved
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
private struct HakoMacPreferencesEnvironment: ViewModifier {
    @ObservedObject var preferences: AppPreferencesModel
     
     
    var presentsRestartPrompt = false


    @State private var offersLanguageRestart = false

    func body(content: Content) -> some View {
        content
            .tint(preferences.accent.color)
            .onAppear {
                applyAppearance(preferences.themeMode)
                installDetailCanvasFallback()
            }
            .onChange(of: preferences.themeMode) { mode in
                applyAppearance(mode)
            }
             
             
             
             
             
             
             
             
            .onChange(of: preferences.language) { _ in
                if presentsRestartPrompt {
                    offersLanguageRestart = true
                }
            }
            .alert(
                "Reopen Clash to change language?",
                isPresented: $offersLanguageRestart
            ) {
                Button("Reopen Now") {
                    relaunchForLanguageChange()
                }
                Button("Later", role: .cancel) {}
            } message: {
                Text(
                    "The tunnel stays connected. The new language takes effect when Clash reopens."
                )
            }
    }

     
     
     
    @MainActor
    private func installDetailCanvasFallback() {
        HakoRegularDetailCanvasFallback.color =
            HakoMacPlatformPresentation.palette.canvas
    }

    private func applyAppearance(_ mode: AppThemeMode) {
        NSApplication.shared.appearance = switch mode {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    @MainActor
    private func relaunchForLanguageChange() {
         
         
         
         
        guard HakoMacQuit.nextTermination != .relaunchForLanguageChange
        else { return }
        HakoMacQuit.nextTermination = .relaunchForLanguageChange
         
         
        let relauncher = Process()
        relauncher.executableURL = URL(fileURLWithPath: "/bin/sh")
        relauncher.arguments = [
            "-c",
            "sleep 0.6; /usr/bin/open \"\(Bundle.main.bundlePath)\"",
        ]
        try? relauncher.run()
        NSApplication.shared.terminate(nil)
    }
}

 
 
 
 
private struct HakoMacProductCommands: Commands {
     
     
     
     
     
     
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        SidebarCommands()

        CommandGroup(replacing: .appInfo) {
            Button {
                open(.more(.about))
            } label: {
                Text(hako: .copy("About Clash"))
            }
        }

        CommandGroup(replacing: .appSettings) {
            Button {
                open(.more(.root))
            } label: {
                Text(hako: .copy("Settings…"))
            }
            .keyboardShortcut(",", modifiers: .command)
        }

         
         
         
         
        CommandGroup(replacing: .newItem) {
            Button {
                Task { @MainActor in
                    guard let model = HakoMacSceneModel.current else { return }
                    model.focusMainWindow(openWindow)
                    model.requestNewConfiguration()
                }
            } label: {
                Text(hako: .copy("Add Profile"))
            }
            .keyboardShortcut("n", modifiers: [.command])
            sceneCommand(.copy("Create Nodes")) { $0.requestAddSource(purpose: .nodes) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            sceneCommand(.copy("Create Rules")) { $0.requestAddSource(purpose: .rules) }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Divider()
            Button {
                Task { @MainActor in
                    guard let model = HakoMacSceneModel.current else { return }
                    model.focusMainWindow(openWindow)
                    model.requestUpdateAllSources()
                }
            } label: {
                Text(hako: .copy("Update All Sources"))
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }
         
         
        CommandGroup(after: .toolbar) {
            ForEach(HakoMacConfigurationCenterSegment.allCases) { segment in
                sceneCommand(.copy(segment.title)) { $0.requestConfigurationCenter(segment) }
                    .keyboardShortcut(KeyEquivalent(Character(String(segment.rawValue + 1))), modifiers: [.command])
            }
        }
         
         
         
         
        CommandGroup(after: .pasteboard) {
            Divider()
            sceneCommand(.copy("Delete")) { $0.requestDeleteShownItem() }
                .keyboardShortcut(.delete, modifiers: [.command])
        }

        CommandGroup(replacing: .help) {}
    }

     
     
    private func sceneCommand(_ title: HakoDisplayText, _ request: @escaping @MainActor (HakoMacSceneModel) -> Void) -> some View {
        Button {
            Task { @MainActor in
                guard let model = HakoMacSceneModel.current else { return }
                model.focusMainWindow(openWindow)
                request(model)
            }
        } label: {
            Text(hako: title)
        }
    }

    private func open(_ destination: HakoMacSecondaryDestination) {
        Task { @MainActor in
            guard let model = HakoMacSceneModel.current else { return }
            model.focusMainWindow(openWindow)
            model.navigationRequest = destination
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
private struct HakoMacRuntimeConfigurationPage: View, Equatable {
    struct Inputs {
        var source: String?
        var snapshot: ProfileFinalConfigurationSnapshot
        var base: String?
        var comparison: String?
    }

    let profile: Profile
    let isActive: Bool
     
     
    let fetchTexts: () -> (source: String?, effective: String?, raw: String?)
    let blockedRuleSets:
        (@Sendable () async -> [ProviderCompileVerdicts.Blocked])?

    @State private var inputs: Inputs?

    static func == (
        lhs: HakoMacRuntimeConfigurationPage,
        rhs: HakoMacRuntimeConfigurationPage
    ) -> Bool {
         
         
        lhs.profile == rhs.profile && lhs.isActive == rhs.isActive
    }

    var body: some View {
        Group {
            if let inputs {
                ProfileFinalConfigurationView(
                    title: "Final Configuration",
                    snapshot: inputs.snapshot,
                    sourceYAML: inputs.source,
                     
                     
                     
                    comparisonYAML: inputs.comparison,
                     
                     
                     
                     
                    baseYAML: inputs.base,
                    ownsNavigationContainer: false,
                    blockedRuleSets: blockedRuleSets
                )
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: profile) {
            let texts = fetchTexts()
             
             
             
            let captured = profile
            async let baseTask: String? = Task.detached(
                priority: .userInitiated
            ) {
                texts.raw.flatMap {
                    RunningCoreDeviations.handedToCore(
                        profile: captured, sidecarYAML: $0
                    )
                }
            }.value
            async let snapshotTask = Task.detached(
                priority: .userInitiated
            ) {
                ProfileFinalConfigurationSnapshot.make(
                    sourceYAML: texts.source,
                    effectiveYAML: texts.effective
                )
            }.value
            inputs = await Inputs(
                source: texts.source,
                snapshot: snapshotTask,
                base: baseTask,
                comparison: texts.raw
            )
        }
    }
}

 
 
 
 
 
 
 
private struct HakoMacDeferredSourcePage: View, Equatable {
    let profile: Profile
     
    let fetch: () -> String?
    let content: (String?) -> AnyView

     
    @State private var text: String??

    static func == (
        lhs: HakoMacDeferredSourcePage,
        rhs: HakoMacDeferredSourcePage
    ) -> Bool {
        lhs.profile == rhs.profile
    }

    var body: some View {
        Group {
            if let text {
                content(text)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: profile) {
            text = .some(fetch())
        }
    }
}

 

 
 
 
 
 
 
 
 
 
 
 
 
 
 
extension HakoMacSceneModel {
    fileprivate func installStatusItem() {
        let controller = HakoMacStatusMenuController(
            snapshot: { [weak self] in
                self?.makeStatusMenuSnapshot() ?? .empty
            },
            actions: makeStatusMenuActions(),
            tunnelIsUp: { [weak self] in
                guard let self else { return false }
                return HakoMacQuit.tunnelIsUp(status: self.vpn.status)
            },
             
             
            latency: nodes.$delays
                .combineLatest(nodes.$testingNames)
                .map { [weak self] delays, testing in
                    self?.menuBarLatency(delays: delays, testing: testing) ?? [:]
                }
                .eraseToAnyPublisher(),
            testing: nodes.$isTestingLatency.eraseToAnyPublisher(),
            listenerUpdates: proxyShare.terminalListenerDidChange.eraseToAnyPublisher()
        )
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.menu = controller.menu
        statusMenuController = controller
        statusItem = item
        refreshStatusButton()
        menuBarTraffic.$upLine
            .combineLatest(menuBarTraffic.$downLine)
            .dropFirst()
            .sink { [weak self] _ in self?.refreshStatusButton() }
            .store(in: &statusItemSubscriptions)
         
         
         
        vpn.$status
            .removeDuplicates()
            .dropFirst()
             
             
             
            .sink { [weak self] status in self?.refreshStatusButton(status: status) }
            .store(in: &statusItemSubscriptions)
    }

    private func refreshStatusButton(status: String? = nil) {
        guard let button = statusItem?.button else { return }
        let showsSpeed = UserDefaults.standard.bool(forKey: HakoMacMenuBarSpeed.key)
         
         
        button.image = HakoMacStatusItemLabel.image(
            showsSpeed: showsSpeed,
            upLine: menuBarTraffic.upLine,
            downLine: menuBarTraffic.downLine,
            tunnelIsUp: HakoMacQuit.tunnelIsUp(status: status ?? vpn.status)
        )
        button.setAccessibilityLabel(HakoMacStatusItemLabel.accessibilityLabel(
            showsSpeed: showsSpeed,
            upLine: menuBarTraffic.upLine,
            downLine: menuBarTraffic.downLine
        ))
    }

    private func makeStatusMenuSnapshot() -> HakoMacStatusMenuSnapshot {
         
         
        let snapshot = latestSnapshot
        let listener = proxyShare.terminalListener
        return HakoMacStatusMenuSnapshot(
            phase: snapshot.connection.phase,
            primaryIntent: snapshot.connection.primaryIntent,
            outboundMode: currentOutboundMode,
            selectedRouteName: snapshot.connection.selectedRouteName,
            proxies: menuBarProxyCatalog,
            showsSpeedInMenuBar: UserDefaults.standard.bool(forKey: HakoMacMenuBarSpeed.key),
            hidesDockIcon: UserDefaults.standard.bool(forKey: HakoMacDockIcon.key),
            upLine: menuBarTraffic.upLine,
            downLine: menuBarTraffic.downLine,
            offersQuitLeavingTunnel: false,
            offersShellCommand: listener != nil,
            offersExternalShellCommand: listener?.host(forExternalMachine: true, addresses: proxyShare.reachableAddresses) != nil,
             
            prefersLoopbackShellCommand: false
        )
    }

     
     
     
     
    private func copyShellCommand(externalIP: Bool) {
        guard let listener = proxyShare.terminalListener else { return }
        guard let host = listener.host(forExternalMachine: externalIP, addresses: proxyShare.reachableAddresses) else { return }
        let text = ProxyEnvironmentCommand.text(
            shell: ProxyEnvironmentShell.remembered(in: .standard),
            endpoint: ProxyEnvironmentEndpoint(
                host: host,
                httpPort: listener.httpPort,
                socksPort: listener.socksPort,
                username: listener.username,
                password: proxyShare.terminalPassword(for: listener)
            )
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

     
     
     
    fileprivate func makeStatusMenuActions() -> HakoMacStatusMenuActions {
        var actions = HakoMacStatusMenuActions.none
        actions.primary = { [weak self] in self?.performPrimaryAction() }
        actions.cancelStart = { [weak self] in self?.cancelStart() }
        actions.setOutboundMode = { [weak self] mode in
            Task { await self?.setOutboundMode(mode) }
        }
        actions.select = { [weak self] group, member in
            Task { await self?.nodes.select(group: group, name: member) }
        }
         
        actions.testGroup = { [weak self] name in
            guard let self, let group = self.nodes.groups.first(where: { $0.name == name }) else { return }
            Task { await self.nodes.test(group: group) }
        }
        actions.setShowsSpeedInMenuBar = { [weak self] shows in
            UserDefaults.standard.set(shows, forKey: HakoMacMenuBarSpeed.key)
            self?.refreshStatusButton()
        }
        actions.setHidesDockIcon = { hides in
            UserDefaults.standard.set(hides, forKey: HakoMacDockIcon.key)
            HakoMacDockIcon.apply(hidesIcon: hides)
        }
         
        actions.openSettings = { [weak self] in
            self?.openMainWindow()
            self?.navigationRequest = .more(.root)
        }
        actions.openApp = { [weak self] in self?.openMainWindow() }
        actions.quitLeavingTunnel = {
            HakoMacQuit.nextTermination = .readerQuitLeavingTunnelRunning
            NSApplication.shared.terminate(nil)
        }
        actions.quit = { NSApplication.shared.terminate(nil) }
        actions.copyShellCommand = { [weak self] externalIP in
            self?.copyShellCommand(externalIP: externalIP)
        }
        return actions
    }
}

 
 
 
enum HakoMacLibraryBridge {
    @MainActor static func apply(_ snapshot: ConfigurationLibrarySnapshot) {
        HakoMacSceneModel.current?.configurationLibrary.apply(snapshot)
    }
}

 
struct HakoMacImportRequest: Identifiable {
    let purpose: HakoMacSourceImportPurpose
    var tab: HakoMacSourceImportSheet.Tab = .link
     
    var mergeIntoSourceID: String? = nil
    var id: String { (purpose == .rules ? "rules" : "nodes") + "-\(tab.rawValue)" + (mergeIntoSourceID.map { "-into-" + $0 } ?? "") }
}

 
struct HakoMacChainRequest: Identifiable {
    let existingID: String?
    var id: String { existingID ?? "new" }
}

 
struct HakoMacInspectedNode: Identifiable {
    let node: HakoMacSourceNode
    var id: String { "\(node.index)-" + node.name }
}

 
 
struct HakoMacEditingNode: Identifiable {
    let source: ConfigurationSourceRecord
    let node: HakoMacSourceNode
    let record: ProxyNodeRecord
    var id: String { source.id + "#\(node.index)" }
}

 
struct HakoMacRuntimePreviewRequest: Hashable, Codable {
    let profileID: String
}

 
struct HakoMacScriptEditorRequest: Hashable, Codable {
    let scriptID: String
}

 
 
 
 
 
 
 
 
 
private struct HakoMacFollowsProfilesPage<Content: View>: View {
    let profiles: ProfilesViewModel
    @ViewBuilder let content: () -> Content
    @State private var generation = 0

    var body: some View {
        let _ = generation
        content()
            .onReceive(profiles.$profiles.dropFirst()) { _ in generation &+= 1 }
    }
}

private struct HakoMacCentrePresentations: ViewModifier {
    @ObservedObject var model: HakoMacSceneModel
    let actions: HakoMacConfigurationCenterListActions

    func body(content: Content) -> some View {
        content
            .alert(
                Text(hako: .copy("Could Not Save")),
                isPresented: Binding(get: { model.configurationWriteError != nil }, set: { shown in if !shown { model.configurationWriteError = nil } }),
                presenting: model.configurationWriteError
            ) { _ in
                Button { model.configurationWriteError = nil } label: { Text(hako: .copy("OK")) }
                    .accessibilityIdentifier("configuration-center.configuration.write-error.dismiss")
            } message: { message in
                Text(verbatim: message)
            }
            .sheet(item: model.configurationCenterEditingSchemeBinding) { selection in
                model.ruleEditorSheet(selection)
                    .hakoModalPresentation(.fitted)
            }
            .sheet(item: model.configurationCenterChainBinding) { request in
                model.chainSheet(request)
                    .hakoModalPresentation(.fitted)
            }
    }
}
