import SwiftUI

 
 
 
 
 
 
 
struct HakoTVShell: View {
     
     
     
    enum Tab: Hashable { case home, utilities, more }

    var stage: HakoTVTestStage?
     
     
    let matrix: HakoTVLaunchOverrides?
     
     
     
    var connectsOnLaunch = false
     
     
    var updatesOnLaunch = false

    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: Tab = .home
     
     
    @State private var fixture: HakoTVProductState
     
     
    @StateObject private var tunnel: HakoTVTunnelController
     
     
     
    @State private var store: HakoTVSubscriptionStore
     
     
     
     
     
     
     
     
     
     
    enum HomeDoor: Hashable {
         
        case outboundMode
         
         
        case nodes
         
        case subscriptions
         
         
        case iCloudRestore
         
         
        case addSubscription
         
        case subscription(HakoTVSubscription.ID)
         
        case edit(HakoTVSubscription.ID)
         
        case rules(HakoTVSubscription.ID)
         
        case autoUpdate(HakoTVSubscription.ID)
         
        case script(HakoTVSubscription.ID)
    }
    @State private var homePath: [HomeDoor] = []

    private func homeDoorOpen(_ door: HomeDoor) -> Bool { homePath.contains(door) }

     
     
    private func setHomeDoor(_ door: HomeDoor, open: Bool) {
        if open {
            if !homePath.contains(door) { homePath.append(door) }
        } else if let index = homePath.firstIndex(of: door) {
            homePath.removeSubrange(index...)
        }
    }

    private func homeDoorBinding(_ door: HomeDoor) -> Binding<Bool> {
        Binding(get: { homeDoorOpen(door) }, set: { setHomeDoor(door, open: $0) })
    }

     
     
    private func homeDoorID(_ kind: (HakoTVSubscription.ID) -> HomeDoor, _ matches: (HomeDoor) -> HakoTVSubscription.ID?) -> HakoTVSubscription.ID? {
        for door in homePath { if let id = matches(door) { return id } }
        return nil
    }

    private func setHomeDoorID(_ id: HakoTVSubscription.ID?, kind: (HakoTVSubscription.ID) -> HomeDoor, matches: (HomeDoor) -> HakoTVSubscription.ID?) {
        if let index = homePath.firstIndex(where: { matches($0) != nil }) {
            homePath.removeSubrange(index...)
        }
        if let id { homePath.append(kind(id)) }
    }

    private var showsAddSubscription: Bool {
        get { homeDoorOpen(.addSubscription) }
        nonmutating set { setHomeDoor(.addSubscription, open: newValue) }
    }
    private var showsOutboundMode: Bool {
        get { homeDoorOpen(.outboundMode) }
        nonmutating set { setHomeDoor(.outboundMode, open: newValue) }
    }
    private var showsSubscriptions: Bool {
        get { homeDoorOpen(.subscriptions) }
        nonmutating set { setHomeDoor(.subscriptions, open: newValue) }
    }
    private var showsNodes: Bool {
        get { homeDoorOpen(.nodes) }
        nonmutating set { setHomeDoor(.nodes, open: newValue) }
    }
    private var showsICloudRestore: Bool {
        get { homeDoorOpen(.iCloudRestore) }
        nonmutating set { setHomeDoor(.iCloudRestore, open: newValue) }
    }
    private var subscriptionDoor: HakoTVSubscription.ID? {
        get { homeDoorID(HomeDoor.subscription) { if case .subscription(let id) = $0 { return id }; return nil } }
        nonmutating set { setHomeDoorID(newValue, kind: HomeDoor.subscription) { if case .subscription(let id) = $0 { return id }; return nil } }
    }
    private var editDoor: HakoTVSubscription.ID? {
        get { homeDoorID(HomeDoor.edit) { if case .edit(let id) = $0 { return id }; return nil } }
        nonmutating set { setHomeDoorID(newValue, kind: HomeDoor.edit) { if case .edit(let id) = $0 { return id }; return nil } }
    }
    private var rulesDoor: HakoTVSubscription.ID? {
        get { homeDoorID(HomeDoor.rules) { if case .rules(let id) = $0 { return id }; return nil } }
        nonmutating set { setHomeDoorID(newValue, kind: HomeDoor.rules) { if case .rules(let id) = $0 { return id }; return nil } }
    }
    private var autoUpdateDoor: HakoTVSubscription.ID? {
        get { homeDoorID(HomeDoor.autoUpdate) { if case .autoUpdate(let id) = $0 { return id }; return nil } }
        nonmutating set { setHomeDoorID(newValue, kind: HomeDoor.autoUpdate) { if case .autoUpdate(let id) = $0 { return id }; return nil } }
    }
    private var scriptDoor: HakoTVSubscription.ID? {
        get { homeDoorID(HomeDoor.script) { if case .script(let id) = $0 { return id }; return nil } }
        nonmutating set { setHomeDoorID(newValue, kind: HomeDoor.script) { if case .script(let id) = $0 { return id }; return nil } }
    }
     
     
    @State private var utilitiesDoor: HakoTVUtilitiesHub.Door?
     
    @State private var moreDoor: HakoTVMoreHub.Door?
     
     
    @State private var iCloudRestoreFromList = false
     
     
     
     
    @State private var connectionDoor: HakoTVConnectionsScreen.Door?
     
     
     
     
     
     
     
    @State private var showsProviders = false

    init(stage: HakoTVTestStage?, connectsOnLaunch: Bool = false, updatesOnLaunch: Bool = false, matrix: HakoTVLaunchOverrides? = nil, store: HakoTVSubscriptionStore = HakoTVSubscriptionStore()) {
        self.stage = stage
        self.connectsOnLaunch = connectsOnLaunch
        self.updatesOnLaunch = updatesOnLaunch
        self.matrix = matrix
        let fixture: HakoTVProductState.Fixture = switch stage {
        case .nodesMany: .manyGroups
        case .nodesManyTen: .manyGroupsTenNodes
        case .nodesLongNames: .longNames
        default: .prototype
        }
        var fixtureState = HakoTVProductState(fixture: fixture)
         
         
        if stage == .welcome { fixtureState.iCloudRestoreLine = String(localized: "Restore from iCloud") }


        _fixture = State(initialValue: fixtureState)

        _tunnel = StateObject(wrappedValue: HakoTVTunnelController())

         
         
         
        var store = stage == .subscriptions || stage == .subscriptionDetail || stage == .editSubscription || stage == .addSubscription || stage == .profileRules
            ? HakoTVSubscriptionStore.stageFixture()
            : store


        _store = State(initialValue: store)
    }

     
     
    private var iCloudRestoreScreen: some View {
        HakoTVICloudRestoreScreen(
            state: state,
            service: live ? tunnel.iCloudRestore : nil,
            store: $store,
            onDone: closeICloudRestore
        )
    }

    private func closeICloudRestore() {
        var restoreOpen = showsICloudRestore
        var subscriptionsOpen = showsSubscriptions
        Self.finishICloudRestore(fromList: iCloudRestoreFromList,
                                 restoreOpen: &restoreOpen,
                                 subscriptionsOpen: &subscriptionsOpen)
        showsICloudRestore = restoreOpen
        showsSubscriptions = subscriptionsOpen
    }

     
     
    static func finishICloudRestore(fromList: Bool, restoreOpen: inout Bool,
                                   subscriptionsOpen: inout Bool) {
        restoreOpen = false
        if fromList { subscriptionsOpen = true }
    }

     
    @ViewBuilder
    private func homeScreen(for door: HomeDoor) -> some View {
        switch door {
        case .iCloudRestore:
            iCloudRestoreScreen
        case .outboundMode:
            HakoTVOutboundModeScreen(
                state: state,
                onSelect: live ? { mode in Task { await tunnel.setMode(mode) } } : nil
            )
        case .nodes:
            HakoTVNodesScreen(
                state: state,
                onPin: live ? { member, group in Task { await tunnel.pin(member: member, group: group) } } : nil,
                onTestAll: live ? { group in Task { await tunnel.testAll(group: group) } } : nil,
                onTest: live ? { member in Task { await tunnel.testOne(member: member) } } : nil
            )
        case .subscriptions:
            HakoTVSubscriptionsScreen(
                store: $store,
                onOpen: { subscriptionDoor = $0 },
                onAdd: { showsAddSubscription = true },
                onRestore: {
                    iCloudRestoreFromList = true
                    showsICloudRestore = true
                }
            )
        case .subscription(let id):
            HakoTVSubscriptionDetailScreen(
                store: $store,
                id: id,
                refresh: live ? tunnel.state.refresh : nil,
                onDone: {
                     
                     
                     
                     
                     
                    subscriptionDoor = nil
                },
                onUpdate: live ? {
                    if let subscription = store.subscriptions.first(where: { $0.id == id }) {
                        Task { await tunnel.refresh(subscription: subscription) }
                    }
                } : nil,
                onEdit: { editDoor = id },
                onRules: { rulesDoor = id },
                onAutoUpdate: { autoUpdateDoor = id },
                onScript: { scriptDoor = id }
            )
        case .script(let id):
            HakoTVProfileScriptScreen(
                store: $store,
                id: id,
                onUpdateScript: live ? {
                    if let subscription = store.subscriptions.first(where: { $0.id == id }) {
                        Task { await tunnel.updateScript(subscription: subscription, isCurrent: store.current?.id == id) }
                    }
                } : nil
            ) { changedID in
                 
                 
                 
                 
                scriptDoor = nil
                guard live, let subscription = Self.refreshAfterDoor(changed: changedID != nil, id: id, in: store) else { return }
                Task { await tunnel.refresh(subscription: subscription) }
            }
        case .autoUpdate(let id):
            HakoTVAutoUpdateScreen(store: $store, id: id) { _ in
                autoUpdateDoor = nil
                scheduleBackgroundRefresh()
            }
        case .rules(let id):
            HakoTVProfileRulesScreen(store: $store, id: id) { row, changed in
                 
                rulesDoor = nil
                 
                 
                 
                 
                guard live, let subscription = Self.refreshAfterDoor(changed: changed, id: row.id, in: store) else { return }
                Task { await tunnel.refresh(subscription: subscription) }
            }
        case .edit(let id):
            HakoTVEditSubscriptionScreen(store: $store, id: id) { newAddress in
                 
                 
                editDoor = nil
                 
                 
                 
                 
                 
                 
                guard live,
                      let subscription = HakoTVEditSubscriptionScreen.refreshTarget(
                          newAddress: newAddress, in: store
                      )
                else { return }
                Task { await tunnel.refresh(subscription: subscription) }
            }
        case .addSubscription:
            HakoTVAddSubscriptionScreen(store: $store) {
                 
                 
                showsAddSubscription = false
            }
        }
    }

     
     
     
     
    static func refreshAfterDoor(changed: Bool, id: HakoTVSubscription.ID, in store: HakoTVSubscriptionStore) -> HakoTVSubscription? {
        guard changed, store.current?.id == id else { return nil }
        return store.subscriptions.first { $0.id == id }
    }

    private var hasConfiguration: Bool {
        !store.subscriptions.isEmpty
    }

     
     
     
    private var live: Bool { stage == nil }

    private var state: Binding<HakoTVProductState> {
        live ? $tunnel.state : $fixture
    }

     
     
     
    private func primaryAction() {
        let presentation = HakoTVHomePresentation.make(state: tunnel.state)
        Task {
            if tunnel.state.isConnected || presentation.cancels {
                await tunnel.disconnect()
                return
            }
             
             
            if let refreshed = await tunnel.refreshRestoredProfilesIfNewer(store: store) { store = refreshed }
            guard let current = store.current else { return }


            await tunnel.connect(subscription: current)
        }
    }

    var body: some View {
        TabView(selection: $tab) {
             
             
             
             
             
            NavigationStack(path: $homePath) {
                Group {
                    if hasConfiguration || stage == .home || stage == .connected || stage == .outboundMode {
                        HakoTVHomeView(
                            state: state,
                            showsOutboundMode: homeDoorBinding(.outboundMode),
                            showsSubscriptions: homeDoorBinding(.subscriptions),
                            showsNodes: homeDoorBinding(.nodes),
                            onPrimaryAction: live ? primaryAction : nil
                        )
                    } else {
                        HakoTVWelcomeView(
                            onAddSubscription: { showsAddSubscription = true },
                            restoreLine: state.wrappedValue.iCloudRestoreLine,
                            onRestore: {
                                iCloudRestoreFromList = false
                                showsICloudRestore = true
                            }
                        )
                    }
                }
                .navigationDestination(for: HomeDoor.self) { door in
                    homeScreen(for: door)
                }
            }
             
             
             
             
            .hakoTVTitleSafe()
            .tabItem { Text("Home") }
            .tag(Tab.home)

            utilitiesTab
                .hakoTVTitleSafe()
                .tabItem { Text("Utilities") }
                .tag(Tab.utilities)

             
             
            NavigationStack {
                HakoTVMoreHub(state: state, opened: $moreDoor, onAutoConnect: { wanted in
                     
                     
                     
                     
                     
                    Task { await tunnel.setAutoConnect(wanted) }
                })
                    .navigationDestination(item: $moreDoor) { door in
                        switch door {
                        case .ipStack:
                            HakoTVIPStackScreen(tunnel: tunnel)
                        case .dns:
                            HakoTVDNSScreen(state: state)
                        case .userAgent:
                            HakoTVUserAgentScreen()
                        case .proxyShare:
                            HakoTVProxyShareScreen(state: state, tunnel: tunnel)
                        case .diagnostics:
                            HakoTVDiagnosticsScreen(
                                state: state,
                                openDNS: { moreDoor = .dns },
                                openProviders: { showsProviders = true }
                            )
                        }
                    }
                    .navigationDestination(isPresented: $showsProviders) {
                        HakoTVProvidersScreen(state: state)
                    }
            }
            .hakoTVTitleSafe()
            .tabItem { Text("More") }
            .tag(Tab.more)
        }


        .onChange(of: tunnel.lastActivation) { _, activation in
             
             
             
            guard let activation else { return }
            store.markUpdated(activation.subscriptionID, at: activation.at)
             
             
            store.adoptPanelName(activation.subscriptionID, activation.panelName)
        }
        .onChange(of: store.current, initial: true) { previous, current in
             
             
             
             
             
             
            let row = Self.homeProfileRow(for: current, fixture: HakoTVProductState())
            state.wrappedValue.profileName = row.name
            state.wrappedValue.profileAge = row.age
             
             
             
             
             
             
            guard live, previous?.id != current?.id else { return }
            if let current {
                Task { await tunnel.subscriptionChanged(to: current) }
            } else {
                Task { await tunnel.disconnect() }
            }
        }
        .task(id: stage) {
            if live {


                await tunnel.probeICloudForWelcome()
                if let refreshed = await tunnel.refreshRestoredProfilesIfNewer(store: store) { store = refreshed }
            }
             
             
             
             
             
             
             
             
             
             
             
             
             
             
            guard stage == .connectionsLive || stage == .connectionDetail else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                HakoTVConnectionsScreen.liveTick(&fixture, at: Date())
            }
        }
        .environment(\.hakoTVPollingPresentation, pollingPresentation)
        .onChange(of: pollingPresentation, initial: true) { _, value in
            if live { tunnel.updatePresentation(value) }
        }
        .onDisappear {
            if live { tunnel.updatePresentation(.init(page: .configuration, active: false)) }
        }
        .onExitCommand(perform: currentTabDoor == nil ? nil : closeTopmostDoor)
        .task {
             
             
            if live {
                await runMatrixPreparation()
                if connectsOnLaunch { primaryAction() }
                await scanForDueUpdate()
                await runMatrixProbes()
                if updatesOnLaunch, let current = store.current {
                    showsSubscriptions = true
                    try? await Task.sleep(for: .milliseconds(400))
                    subscriptionDoor = current.id
                    Task { await tunnel.refresh(subscription: current) }
                }


            }
             
             
            if stage == .connected { fixture.stage = .connected }
            if stage == .outboundMode { showsOutboundMode = true }
            if let mode = stage?.outboundModeOverride { fixture.outboundMode = mode }
            if stage?.opensNodes == true {
                tab = .utilities
                utilitiesDoor = .nodes
            }
            if stage == .rules {
                tab = .utilities
                utilitiesDoor = .rules
            }
            if stage == .connections || stage == .connectionsLive || stage == .connectionDetail {
                tab = .utilities
                utilitiesDoor = .connections
            }
            if stage == .connectionDetail, let first = HakoTVConnectionsScreen.rows(fixture.connections, kind: .all).first {
                 
                 
                 
                try? await Task.sleep(for: .milliseconds(400))
                connectionDoor = HakoTVConnectionsScreen.Door(connection: first)
            }
            if stage == .subscriptions { showsSubscriptions = true }
            if stage == .subscriptionDetail {
                 
                 
                 
                showsSubscriptions = true
                try? await Task.sleep(for: .milliseconds(400))
                subscriptionDoor = store.subscriptions.first { $0.id != store.current?.id }?.id
            }
            if stage == .editSubscription, let current = store.current {
                 
                showsSubscriptions = true
                try? await Task.sleep(for: .milliseconds(400))
                subscriptionDoor = current.id
                try? await Task.sleep(for: .milliseconds(400))
                editDoor = current.id
            }
            if stage == .profileRules, let current = store.current {
                 
                showsSubscriptions = true
                try? await Task.sleep(for: .milliseconds(400))
                subscriptionDoor = current.id
                try? await Task.sleep(for: .milliseconds(400))
                rulesDoor = current.id
            }
            if stage == .addSubscription { showsAddSubscription = true }
            if stage == .more { tab = .more }
            if stage == .diagnostics { tab = .more; moreDoor = .diagnostics }
            if stage == .dns { tab = .more; moreDoor = .dns }
            if stage == .userAgent { tab = .more; moreDoor = .userAgent }
            if stage == .proxyShare { tab = .more; moreDoor = .proxyShare }
            if stage == .providers {
                 
                 
                 
                tab = .more
                moreDoor = .diagnostics
                try? await Task.sleep(for: .milliseconds(400))
                showsProviders = true
            }
        }
    }

     
     
     
     
     
     
     
     
    @ViewBuilder
    private var utilitiesTab: some View {
        NavigationStack {
            HakoTVUtilitiesHub(opened: $utilitiesDoor)
                .navigationDestination(item: $utilitiesDoor) { door in
                    switch door {
                    case .nodes:
                        HakoTVNodesScreen(
                            state: state,
                            onPin: live ? { member, group in Task { await tunnel.pin(member: member, group: group) } } : nil,
                            onTestAll: live ? { group in Task { await tunnel.testAll(group: group) } } : nil,
                        onTest: live ? { member in Task { await tunnel.testOne(member: member) } } : nil
                        )
                    case .rules:
                        HakoTVRulesScreen(state: state)
                    case .connections:
                        HakoTVConnectionsScreen(state: state, opened: $connectionDoor)
                    }
                }
                 
                 
                 
                .navigationDestination(item: $connectionDoor) { door in
                    HakoTVConnectionDetailScreen(state: state, seed: door.connection,
                                                 observedAt: door.observedAt, generation: door.generation)
                }
        }
    }

     
    enum DoorPop: Equatable {
        case edit, subscriptionDetail, addSubscription, iCloudRestore, subscriptions, nodes, outboundMode
        case utilities, connectionDetail, more, providers
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func doorToClose(
        tab: Tab,
        editOpen: Bool, detailOpen: Bool, addOpen: Bool,
        subscriptionsOpen: Bool, nodesOpen: Bool, outboundOpen: Bool,
        utilitiesOpen: Bool, connectionOpen: Bool, moreOpen: Bool, providersOpen: Bool,
        restoreOpen: Bool = false
    ) -> DoorPop? {
        switch tab {
        case .home:
             
             
            if editOpen { return .edit }
            if detailOpen { return .subscriptionDetail }
            if addOpen { return .addSubscription }
            if restoreOpen { return .iCloudRestore }
            if subscriptionsOpen { return .subscriptions }
            if nodesOpen { return .nodes }
            if outboundOpen { return .outboundMode }
            return nil
        case .utilities:
             
             
            if connectionOpen { return .connectionDetail }
            return utilitiesOpen ? .utilities : nil
        case .more:
             
             
            if providersOpen { return .providers }
            return moreOpen ? .more : nil
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    enum DoorUnder: Equatable {
        case more(HakoTVMoreHub.Door)
        case utilities(HakoTVUtilitiesHub.Door)
    }

    static func doorUnder(_ door: DoorPop) -> DoorUnder? {
        switch door {
        case .providers: .more(.diagnostics)
        case .connectionDetail: .utilities(.connections)
        default: nil
        }
    }

     
     
    private func scanForDueUpdate() async {
        await HakoTVAutoUpdate.scanOnForegroundIfDue(store: store) { row in
            await tunnel.refresh(subscription: row)
        }
        scheduleBackgroundRefresh()
    }

    private func scheduleBackgroundRefresh() {
        HakoTVAutoUpdate.schedule(earliest: HakoTVAutoUpdate.nextEligibility(rows: store.subscriptions, now: Date()))
    }

    private var pollingPresentation: HakoTVPollingPresentation {
        .init(page: Self.pollingPage(tab: tab, top: currentTabDoor,
                                    utilities: utilitiesDoor, more: moreDoor),
              active: scenePhase == .active)
    }

    static func pollingPage(tab: Tab, top: DoorPop?, utilities: HakoTVUtilitiesHub.Door?,
                            more: HakoTVMoreHub.Door?) -> HakoTVPollingPage {
        switch top {
        case .nodes: return .nodes
        case .outboundMode: return .outboundMode
        case .providers: return .providers
        case .connectionDetail: return .connectionDetail
        case .utilities:
            switch utilities {
            case .nodes: return .nodes
            case .connections: return .connections
            default: return .configuration
            }
        case .more: return more == .diagnostics ? .diagnostics : .configuration
        case nil: return tab == .home ? .home : .configuration
        default: return .configuration
        }
    }

    private var currentTabDoor: DoorPop? {
        Self.doorToClose(tab: tab,
                         editOpen: editDoor != nil, detailOpen: subscriptionDoor != nil,
                         addOpen: showsAddSubscription, subscriptionsOpen: showsSubscriptions,
                         nodesOpen: showsNodes, outboundOpen: showsOutboundMode,
                         utilitiesOpen: utilitiesDoor != nil, connectionOpen: connectionDoor != nil,
                         moreOpen: moreDoor != nil, providersOpen: showsProviders,
                         restoreOpen: showsICloudRestore)
    }

    private func closeTopmostDoor() {


        let closing = currentTabDoor
        switch closing {
        case .edit: editDoor = nil
        case .subscriptionDetail: subscriptionDoor = nil
        case .addSubscription: showsAddSubscription = false
        case .iCloudRestore: closeICloudRestore()
        case .subscriptions: showsSubscriptions = false
        case .nodes: showsNodes = false
        case .outboundMode: showsOutboundMode = false
        case .utilities: utilitiesDoor = nil
        case .connectionDetail: connectionDoor = nil
        case .providers: showsProviders = false
        case .more: moreDoor = nil
        case nil: break
        }
         
         
         
        if let top = closing, let under = Self.doorUnder(top) {
            switch under {
            case .more(let door): moreDoor = door
            case .utilities(let door): utilitiesDoor = door
            }
        }


    }

     
     
     
     
     
    private func runMatrixPreparation() async {


        await tunnel.prepare(subscription: store.current)


    }

     
     
    private func runMatrixProbes() async {


    }

}

extension HakoTVShell {
     

     
     
     
    static func homeProfileRow(
        for current: HakoTVSubscription?,
        fixture: HakoTVProductState
    ) -> (name: String, age: String) {
        guard let current else { return (fixture.profileName, fixture.profileAge) }
        return (current.title, HakoTVSubscriptionUpdatedWords.text(updatedAt: current.updatedAt))
    }
}

extension View {
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func hakoTVTitleSafe() -> some View {
        safeAreaPadding(EdgeInsets(top: 60, leading: 90, bottom: 60, trailing: 90))
    }


}
