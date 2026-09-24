@preconcurrency import NetworkExtension
import Combine
import Foundation
import Hako
import HakoClientUI

enum NETimeoutError: LocalizedError, Equatable {
    case nePreferencesTimeout
    case extensionMessageTimeout

    var errorDescription: String? {
        "The system VPN service isn’t responding. Please try again in a moment, or restart your Mac."
    }
}

private final class HakoMacNETimeoutGate<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: T) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(throwing: error)
    }
}

private final class HakoMacManagerLoadResult: @unchecked Sendable {
    let managers: [NETunnelProviderManager]
    let error: Error?

    init(_ managers: [NETunnelProviderManager]?, _ error: Error?) {
        self.managers = managers ?? []
        self.error = error
    }
}

@MainActor
final class VPNController: ObservableObject, DNSOnlyTunnelControlling {
    static let vpnProfileTitle = "Clash"
    static let vpnProfileDescription = "Clash by Hako"
    private static let packetTunnelExtensionBundleID =
        HakoAppIdentifiers.base + ".packet-tunnel"

    enum OnDemandSaveOutcome: Equatable {
        case applied
        case refused(String)
        case indeterminate(String)
    }

     
     
     
    static func armOnDemand(
        _ manager: NETunnelProviderManager,
        configuration: OnDemandConfiguration
    ) throws {
        try OnDemandSettings.apply(configuration, to: manager)
    }

     
     
     
     
    static func disarmOnDemandForUserStop(
        _ manager: NETunnelProviderManager
    ) -> Bool {
        guard manager.isOnDemandEnabled else { return false }
        manager.isOnDemandEnabled = false
        return true
    }

     
     
     
     
     
    @Published var legacySettingsMigration: LegacyClientSettingsMigrationResult?
    @Published private(set) var status = "idle"
    @Published private(set) var lastError = "" {
        didSet { installationReadError = nil }
    }
    @Published private(set) var vpnAuthorization: HakoVPNAuthorizationState?
    private var installationReadError: String?
    private var installationReadGeneration: UInt64 = 0
    private var systemVPNInstallationKnown = false
    private let startRequests = TunnelRequestCoalescer()
    var isStarting: Bool { startRequestsInFlight > 0 }
    var systemVPNAuthorization: HakoVPNAuthorizationState? {
        vpnAuthorization ?? (systemVPNInstallationKnown && manager == nil ? .required : nil)
    }
     
     
    @Published private(set) var tunnelSettings = VPNTunnelSettings()
     
     
     
    @Published private(set) var configurationStrictRoute = false

    private let preferences: UserDefaults
    private let preferencesReadTimeout: Double
    private let systemVPNManagers: @MainActor () async throws -> [NETunnelProviderManager]
    private var manager: NETunnelProviderManager?
     
     
     
     
     
    private var appliedConfigIntent: PlatformConfigIntent?
    private var statusObserver: NSObjectProtocol?
     
     
     
     
    private var reachedConnectedSinceStart = false
     
     
     
    private var disconnectNoticeTracker = VPNDisconnectNotice.Tracker()
     
     
    private var managerReloadInFlight = false
    private var managerReloadCooldownUntil = ContinuousClock.now

    private var userStopInFlight = false

    var clientPreferences: UserDefaults { preferences }

    @Published private(set) var applyingIPStackSettings = false
    @Published private(set) var ipStackSaveNotice = ""
    private let profileWriter = IPStackProfileWriter()
    private var profileWriteIntentGeneration: UInt64 = 0
    private var startRequestsInFlight = 0


    @MainActor
    func updateIPStackSettings(_ settings: IPStackSettings) async throws {
        guard !applyingIPStackSettings, startRequestsInFlight == 0 else {
            throw IPStackSettingsApplicationError.operationInProgress
        }
        let stopAtEntry = stopGeneration
        applyingIPStackSettings = true
        defer { applyingIPStackSettings = false; ipStackSaveNotice = "" }
        var restoreInstalledProtocol: (() async throws -> Void)?
        try await IPStackSettingsApplication.apply(
            settings, defaults: preferences,
            saveProtocol: { [self] snapshot in
                let installed: NETunnelProviderManager?
                if let manager { installed = manager }
                else { installed = try await loadManager() }
                guard let installed else { return }
                guard let proto = installed.protocolConfiguration?.copy() as? NETunnelProviderProtocol else {
                    throw IPStackSettingsError.invalidSnapshot
                }
                let previous = IPStackSystemProfileSnapshot(installed)
                proto.providerConfiguration = try snapshot.applying(to: proto.providerConfiguration)
                installed.protocolConfiguration = proto
                do {
                    try await saveIPStackProfile(installed)
                    self.manager = installed
                    if stopGeneration != stopAtEntry { installed.connection.stopVPNTunnel() }
                    restoreInstalledProtocol = { [self] in
                        previous.apply(to: installed, disarm: stopGeneration != stopAtEntry)
                        try await saveIPStackProfile(installed)
                        if stopGeneration != stopAtEntry { installed.connection.stopVPNTunnel() }
                    }
                } catch {
                    previous.apply(to: installed)
                    throw error
                }
            }, restoreProtocol: { try await restoreInstalledProtocol?() },
            withProfileWrite: { [self] in try await profileWriter.settingsTransaction($0) },
            isRunning: { [self] in stopGeneration == stopAtEntry && ["connected", "connecting", "reasserting"].contains(status) },
            restart: { [self] in
                guard await forceRestart() else {
                    throw NSError(domain: "HakoClient.IPStack", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: lastError.isEmpty
                            ? String(localized: "IP Stack settings were saved, but the VPN did not restart. Connect again to apply them.")
                            : lastError,
                    ])
                }
            }
        )
    }


    private func saveIPStackProfile(_ manager: NETunnelProviderManager) async throws {
        let frozen = IPStackSystemProfileSnapshot(manager)
        try await IPStackProfileWriter.awaitConfirmation(operation: { [self] in
            frozen.apply(to: manager)
            try await rawSaveToPreferences(manager)
        }, onWaiting: { [self] in
            ipStackSaveNotice = String(localized: "Waiting for the system to confirm the VPN settings. You can leave this page or stop the VPN.")
        })
        ipStackSaveNotice = ""
    }

    var session: NETunnelProviderSession? {
        manager?.connection as? NETunnelProviderSession
    }
    var reportableLastError: String { lastError }
    var systemVPNProfileResetAvailable: Bool { manager != nil }

    init(
        preferences: UserDefaults? = UserDefaults(
            suiteName: HakoAppIdentifiers.appGroup
        ),
        systemVPNManagers: (@MainActor () async throws -> [NETunnelProviderManager])? = nil,
        preferencesReadTimeout: Double = 15
    ) {
        self.preferences = preferences ?? .standard
        self.preferencesReadTimeout = preferencesReadTimeout
        self.systemVPNManagers = systemVPNManagers ?? { try await Self.loadSystemManagers() }
        tunnelSettings = VPNTunnelSettings.load(from: self.preferences)
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let connection = notification.object as? NEVPNConnection else {
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if connection !== manager?.connection {
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                    let now = ContinuousClock.now
                    guard !isStarting, !profileWriter.isBusy, !managerReloadInFlight,
                          now >= managerReloadCooldownUntil else { return }
                    managerReloadInFlight = true
                    await refreshSystemVPNInstallation()
                    managerReloadInFlight = false
                    managerReloadCooldownUntil =
                        ContinuousClock.now.advanced(by: .seconds(2))
                     
                     
                    guard manager != nil else { return }
                }
                let status = manager?.connection.status ?? connection.status
                updateStatus(status)
                if status == .connected {
                    if !reachedConnectedSinceStart {
                         
                         
                         
                         
                         
                         
                        ProviderFirstLoadRetry.kick(trigger: .connected)
                    }
                    reachedConnectedSinceStart = true
                } else if status == .disconnected || status == .invalid {
                    reachedConnectedSinceStart = false
                }
                if disconnectNoticeTracker.observe(
                    status,
                    userInitiated: userStopInFlight,
                    enabled: OnDemandSettings.configuration()
                        .showDisconnectMessage
                ) {
                    VPNDisconnectNotice.post()
                }
                if status == .connecting || status == .connected {
                    userStopInFlight = false
                }
            }
        }
    }

    deinit {
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver)
        }
    }

     
     
    func refreshSystemVPNInstallation() async {
        guard !isStarting, !profileWriter.isBusy else { return }
        let intent = profileWriteIntentGeneration
        let revision = profileWriter.revision
        installationReadGeneration &+= 1
        let read = installationReadGeneration
        func isCurrent() -> Bool {
            !Task.isCancelled && intent == profileWriteIntentGeneration
                && revision == profileWriter.revision && read == installationReadGeneration
                && !isStarting && !profileWriter.isBusy
        }
        do {
            let installed = try await loadManager()
            guard isCurrent() else { return }
            adoptInstalledManager(installed)
            if installationReadError != nil { lastError = "" }
        } catch {
            guard isCurrent() else { return }
            systemVPNInstallationKnown = false
            vpnAuthorization = nil
            fail(error)
            installationReadError = lastError
        }
    }

    private func adoptInstalledManager(_ installed: NETunnelProviderManager?) {
        let wasInstalled = manager != nil
        manager = installed
        systemVPNInstallationKnown = true
        if installed != nil || wasInstalled { vpnAuthorization = nil }
        updateStatus(installed?.connection.status ?? .invalid)
    }

    func refresh() async {
        await refreshSystemVPNInstallation()
         
         
         
        if let stampJSON = TunnelIntentStamp.readJSON(from: intentStampDefaults),
           let recovered = try? JSONDecoder().decode(
               PlatformConfigIntent.self, from: Data(stampJSON.utf8)
           ) {
            configurationStrictRoute = recovered.strictRoute
        }
    }

     

     
     
    var routingPolicy: VPNRoutingPolicy {
        VPNRoutingPolicy(
            tunnel: tunnelSettings,
            configurationStrictRoute: configurationStrictRoute
        )
    }

     
     
     
     
     
     
    @discardableResult
    func updateTunnelSettings(_ settings: VPNTunnelSettings) async -> Bool {
        let previous = tunnelSettings
        guard settings != previous else { return true }
        settings.save(to: preferences)
        tunnelSettings = settings
        guard await installRoutingPolicy(reconnectIfNeeded: true) else {
            previous.save(to: preferences)
            tunnelSettings = previous
            return false
        }
        return true
    }

     
     
     
     
     
    private func installRoutingPolicy(reconnectIfNeeded: Bool) async -> Bool {
        do {
            let manager = try await currentOrNewManager()
            guard let tunnelProtocol = manager.protocolConfiguration
                as? NETunnelProviderProtocol
            else {
                fail(NETimeoutError.nePreferencesTimeout)
                return false
            }
            let wanted = routingPolicy
            if self.manager == nil || VPNRoutingPolicy.installed(from: tunnelProtocol) != wanted {
                wanted.apply(to: tunnelProtocol)
                manager.protocolConfiguration = tunnelProtocol
                try await saveToPreferences(manager)
                try await loadFromPreferences(manager)
                self.manager = manager
            }
            lastError = ""
        } catch {
            fail(error)
            return false
        }
        guard reconnectIfNeeded, tunnelIsUp else { return true }
        return await forceRestart()
    }

    @discardableResult
    func start() async -> Bool {
        do { try profileWriter.requireStartReady() }
        catch { lastError = error.localizedDescription; return false }
        let cancellation = VPNStartCancellation()
        return await withTaskCancellationHandler {
            await startRequests.run(origin: .programmatic) { [weak self] in
                guard let self, !cancellation.isCancelled else { return false }
                return await self.performStart(cancellation: cancellation)
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    private func performStart(cancellation: VPNStartCancellation) async -> Bool {
        profileWriteIntentGeneration &+= 1
        let intent = profileWriteIntentGeneration
        startRequestsInFlight += 1
        var phase = "prepare"
        var needsAuthorization = false
        lastError = ""
        vpnAuthorization = nil
        defer {
            startRequestsInFlight -= 1
            if vpnAuthorization == .waiting { vpnAuthorization = nil }
        }
        func isCurrent() -> Bool {
            intent == profileWriteIntentGeneration && !cancellation.isCancelled
        }
        func checkIntent() throws {
            try Task.checkCancellation()
            guard isCurrent() else { throw CancellationError() }
        }
        do {
            try checkIntent()
            let ipStack = try IPStackSettings.load(from: preferences)
            if let container = HakoMacAppGroupAccess.readableContainer() {
                try Self.ensureCoreSetup(container: container, settings: ipStack)
                try await ProviderFirstLoadRetry.recoverCoreOwnedRoutesBeforeStart(container: container)
            }
            try checkIntent()
            let manager = try await currentOrNewManager()
            try checkIntent()
            needsAuthorization = self.manager == nil
            if needsAuthorization { vpnAuthorization = .waiting }
            let proto = (manager.protocolConfiguration?.copy() as? NETunnelProviderProtocol)
                ?? NETunnelProviderProtocol()
            proto.providerBundleIdentifier = Self.packetTunnelExtensionBundleID
            proto.serverAddress = Self.vpnProfileDescription
            proto.providerConfiguration = try ipStack.applying(to: proto.providerConfiguration)
            routingPolicy.apply(to: proto)
            manager.protocolConfiguration = proto
            manager.localizedDescription = Self.vpnProfileDescription
            manager.isEnabled = true
            try Self.armOnDemand(manager, configuration: OnDemandSettings.configuration())
            let frozen = IPStackSystemProfileSnapshot(manager)
            try await VPNStartAuthorization.perform(
                save: { [self] in
                    phase = "save"
                    try await profileWriter.run { [self] in
                        try checkIntent()
                        frozen.apply(to: manager)
                        try await rawSaveToPreferences(manager)
                    }
                },
                reload: { [self] in
                    phase = "reload"
                    try await loadFromPreferences(manager)
                },
                start: { [self] in
                    phase = "start"
                    try manager.connection.startVPNTunnel()
                    adoptInstalledManager(manager)
                    lastError = ""
                },
                abort: { [self] in
                     
                     
                    await Task { @MainActor in
                        do {
                            try await self.profileWriter.run {
                                if manager.isOnDemandEnabled {
                                    try await self.rawSaveToPreferences(manager, disarmOnly: true)
                                }
                            }
                        } catch {
                            HakoLogStore.shared.append("vpn cancelled-start disarm failed: \(error)",
                                stream: .app, level: .warning)
                        }
                        manager.connection.stopVPNTunnel()
                        self.adoptInstalledManager(manager)
                    }.value
                },
                isCurrent: isCurrent,
                onWaiting: { [weak self] in
                    guard isCurrent() else { return }
                    if needsAuthorization { self?.vpnAuthorization = .waiting }
                })
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard isCurrent(), !Task.isCancelled else { return false }
            presentSystemVPNStartFailure(error, phase: phase, needsAuthorization: needsAuthorization)
            return false
        }
    }

    func presentSystemVPNStartFailure(_ error: Error, phase: String, needsAuthorization: Bool) {
        if needsAuthorization, phase == "save", VPNStartAuthorization.isPermissionDenial(error as NSError) {
            vpnAuthorization = .notCompleted
            lastError = ""
        } else {
            vpnAuthorization = nil
            fail(error)
        }
    }

    func stop() async {
         
         
         
         
         
        profileWriteIntentGeneration &+= 1
        let writeIntent = profileWriteIntentGeneration
        stopGeneration &+= 1
        vpnAuthorization = nil
        if applyingIPStackSettings { manager?.connection.stopVPNTunnel() }
        userStopInFlight = true
        if let manager, Self.disarmOnDemandForUserStop(manager) || applyingIPStackSettings {
             
             
            try? await saveToPreferences(manager, whileIntent: writeIntent, disarmOnly: true)
        }
        if profileWriteIntentGeneration == writeIntent { manager?.connection.stopVPNTunnel() }
        if let status = manager?.connection.status {
            updateStatus(status)
        } else {
            self.status = "disconnected"
        }
    }

     
     
     
    private var stopGeneration: UInt = 0

    @discardableResult
    func forceRestart() async -> Bool {
        await stop()
        let restartGeneration = stopGeneration
         
         
         
         
         
         
        var confirmedDown = manager == nil
        for _ in 0..<150 where !confirmedDown {
            guard let connectionStatus = manager?.connection.status else {
                confirmedDown = true
                break
            }
            if connectionStatus == .disconnected
                || connectionStatus == .invalid
            {
                confirmedDown = true
                break
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard confirmedDown else {
            lastError = NETimeoutError.nePreferencesTimeout
                .errorDescription ?? "The tunnel did not finish stopping."
            return false
        }
         
         
         
         
        guard stopGeneration == restartGeneration else {
            {
                let verb = "wound"
                HakoLogStore.shared.append(
                    "restart abandoned, a stop arrived while the tunnel \(verb) down",
                    stream: .app, level: .warning)
            }()
            return false
        }
        return await start()
    }

    @discardableResult
    func resetSystemVPNProfile() async -> Bool {
        guard let manager else { return true }
        do {
            try await removeFromPreferences(manager)
            self.manager = nil
            status = "disconnected"
            lastError = ""
            return true
        } catch {
            fail(error)
            return false
        }
    }

    func activationCoordinator(
        store: ConfigResourceStore,
        container: URL
    ) throws -> ProfileActivationCoordinator {
        try Self.ensureCoreSetup(container: container)
        let working = container.appendingPathComponent(
            "working",
            isDirectory: true
        )
        return ProfileActivationCoordinator(
            store: store,
            profileStore: ProfileStore(
                fileURL: working.appendingPathComponent("store/profiles.json")
            ),
            credentials: CredentialStore(),
            downloader: ResourceDownloader(),
            coreHomeDir: working,
             
             
             
             
             
             
             
             
            compileRuleSets: true,
             
             
             
             
             
             
            deferRuleSetCompilation: true,
            runtimeOverride: { [preferences] in
                FlClashRuntimeConfig.load(from: preferences)
            },
            activator: { _ in },
            preflight: { PreflightService.check(finalYAML: $0, container: container) }
        )
    }

     
     
     
     
    func migrateLegacyGlobalSettingsIfNeeded()
        -> LegacyClientSettingsMigrationResult
    {
         
         
         
         
         
         
        guard let container = HakoMacAppGroupAccess.readableContainer() else {
            return .init(
                globalConfig: .blocked(.storageUnavailable),
                globalScript: nil
            )
        }
        do { try Self.ensureCoreSetup(container: container) }
        catch {
            lastError = error.localizedDescription
            return .init(globalConfig: .blocked(.coreSetupFailed(error.localizedDescription)), globalScript: nil)
        }
        let working = container.appendingPathComponent(
            "working",
            isDirectory: true
        )
        let globalConfig = LegacyGlobalConfigMigrationCoordinator.run(
            workingDirectory: working,
            defaults: preferences
        )
        guard globalConfig.userMessage.isEmpty else {
            return .init(globalConfig: globalConfig, globalScript: nil)
        }
        return .init(
            globalConfig: globalConfig,
            globalScript: LegacyGlobalScriptMigrationCoordinator.run(
                workingDirectory: working,
                defaults: preferences
            )
        )
    }

     
     
     
     
     
    var intentStampDefaults: UserDefaults = GlobalConfig.appGroupDefaults

     
     
     
     
     
     
     
     
     
     
     
     
    @discardableResult
    func applyActiveConfiguration(
        nextIntent intent: PlatformConfigIntent
    ) async -> Bool {
         
         
         
        configurationStrictRoute = intent.strictRoute
        let tunnelUp: Bool
        switch manager?.connection.status {
        case .connected, .connecting, .reasserting: tunnelUp = true
        default: tunnelUp = false
        }
        if appliedConfigIntent == nil, tunnelUp,
           let stampJSON = TunnelIntentStamp.readJSON(
               from: intentStampDefaults
           ),
           let recovered = try? JSONDecoder().decode(
               PlatformConfigIntent.self, from: Data(stampJSON.utf8)
           ) {
            appliedConfigIntent = recovered
        }
        let succeeded: Bool
        switch ActivationDecision.decide(
            current: appliedConfigIntent, next: intent, tunnelUp: tunnelUp
        ) {
        case .start:
            succeeded = await start()
        case .reload:
             
             
             
             
             
             
             
            await awaitConnectedBeforeReload()
             
             
             
             
             
             
            guard tunnelIsUp else {
                {
                    let verb = "waited"
                    HakoLogStore.shared.append(
                        "reload skipped, tunnel went down while it \(verb)",
                        stream: .app, level: .warning)
                }()
                succeeded = false
                break
            }
            var reply = await sendReloadMessage()
             
             
             
             
             
             
            var attemptsLeft = 3
            while attemptsLeft > 0, reloadIsWorthRetrying(reply) {
                attemptsLeft -= 1
                HakoLogStore.shared.append(
                    "reload raced activation, retrying  reason=\(reply.reason)",
                    stream: .app, level: .warning)
                 
                 
                 
                 
                 
                await awaitConnectedBeforeReload(ticks: 50)
                try? await Task.sleep(nanoseconds: 400_000_000)
                reply = await sendReloadMessage()
            }
            switch reply {
            case .reloaded:
                lastError = ""
                succeeded = true
            case .notSent(let why):
                 
                 
                 
                 
                 
                switch manager?.connection.status {
                case .connected:
                     
                     
                     
                     
                    switch await sendReloadMessage() {
                    case .reloaded:
                        lastError = ""
                        succeeded = true
                    case .refused(let answered):
                         
                         
                        guard session?.status == .connected else {
                            HakoLogStore.shared.append(
                                "reload skipped, tunnel went down after refusing  reason=\(answered)",
                                stream: .app, level: .warning)
                            succeeded = false
                            break
                        }
                        HakoLogStore.shared.append(
                            "reload refused after reconnect, restarting  reason=\(answered)",
                            stream: .app, level: .warning)
                        succeeded = await forceRestart()
                    case .notSent(let again):
                        HakoLogStore.shared.append(
                            "reload skipped, session flapping  reason=\(again)",
                            stream: .app, level: .warning)
                        succeeded = false
                    }
                case .connecting, .reasserting:
                     
                     
                     
                     
                    HakoLogStore.shared.append(
                        "reload not delivered, tunnel stuck in transition, restarting  reason=\(why)",
                        stream: .app, level: .warning)
                    succeeded = await forceRestart()
                default:
                     
                     
                     
                     
                    HakoLogStore.shared.append(
                        "reload skipped, tunnel went down  reason=\(why)",
                        stream: .app, level: .warning)
                    succeeded = false
                }
            case .refused(let why):
                 
                 
                 
                guard session?.status == .connected else {
                    HakoLogStore.shared.append(
                        "reload skipped, tunnel went down after refusing  reason=\(why)",
                        stream: .app, level: .warning)
                    succeeded = false
                    break
                }
                HakoLogStore.shared.append(
                    "reload refused, restarting  reason=\(why)",
                    stream: .app, level: .warning)
                succeeded = await forceRestart()
            }
        case .restart:
            succeeded = await forceRestart()
        }
        if succeeded {
            appliedConfigIntent = intent
        }
        return succeeded
    }

     
     
     
    private func awaitConnectedBeforeReload(ticks: Int = 100) async {
        for _ in 0..<ticks {
            switch manager?.connection.status {
            case .connecting, .reasserting:
                try? await Task.sleep(nanoseconds: 100_000_000)
            default:
                return
            }
        }
    }

     
     
     
    private var tunnelIsUp: Bool {
        switch manager?.connection.status {
        case .connected, .connecting, .reasserting: return true
        default: return false
        }
    }

     
     
     
     
     
     
     
     
     
     
    private func reloadIsWorthRetrying(_ reply: ReloadReply) -> Bool {
        switch reply {
        case .reloaded:
            return false
        case .notSent:
            switch manager?.connection.status {
            case .connecting, .reasserting: return true
            default: return false
            }
        case .refused(let why):
            return manager?.connection.status == .connected
                && ReloadRefusal.isRaceWithActivation(why)
        }
    }

     
     
     
     
     
    private enum ReloadReply: Equatable {
         
        case reloaded
         
         
         
        case notSent(String)
         
         
         
         
        case refused(String)

        var reason: String {
            switch self {
            case .reloaded: return "reloaded"
            case .notSent(let why), .refused(let why): return why
            }
        }
    }

     
     
     
     
     
     
     
     
     
     
    private func sendReloadMessage() async -> ReloadReply {
        guard let session, session.status == .connected else {
             
             
             
             
            return .notSent({ let what = "not connected"; return "session \(what)" }())
        }
        guard let payload = try? JSONSerialization.data(
            withJSONObject: ["cmd": "reload"]
        ) else {
            return .notSent({ let verb = "encoded"; return "reload payload could not be \(verb)" }())
        }
        do {
            return try await Self.withNETimeout(
                seconds: 20, .extensionMessageTimeout
            ) {
                try await withCheckedThrowingContinuation { continuation in
                    do {
                        try session.sendProviderMessage(payload) { reply in
                            guard let reply,
                                  let json = try? JSONSerialization
                                      .jsonObject(with: reply)
                                      as? [String: Any]
                            else {
                                 
                                 
                                 
                                continuation.resume(
                                    returning: .refused({ let why = "silent"; return "the extension replied \(why)" }())
                                )
                                return
                            }
                            if let error = json["error"] as? String {
                                 
                                 
                                 
                                 
                                 
                                continuation.resume(returning: .refused(error))
                                return
                            }
                            continuation.resume(returning: .reloaded)
                        }
                    } catch {
                         
                         
                         
                         
                        continuation.resume(
                            returning: .notSent(error.localizedDescription)
                        )
                    }
                }
            }
        } catch {
             
             
            return .refused({ let why = "unanswered"; return "the extension went \(why) for 20s" }())
        }
    }

    func applyOnDemandSettingsReportingOutcome() async
        -> OnDemandSaveOutcome
    {
        do {
            let manager = try await currentOrNewManager()
            try Self.armOnDemand(
                manager,
                configuration: OnDemandSettings.configuration()
            )
            try await saveToPreferences(manager)
            self.manager = manager
            lastError = ""
            return .applied
        } catch let error as OnDemandValidationError {
             
            fail(error)
            return .refused(lastError)
        } catch {
             
             
             
             
            fail(error)
            return .indeterminate(lastError)
        }
    }

    func suspendPacketTunnelForDNSOnly() async -> Bool {
        do {
            guard let manager = try await loadManager() else {
                status = "disconnected"
                lastError = ""
                return true
            }
            if manager.connection.status == .connected
                || manager.connection.status == .connecting
                || manager.connection.status == .reasserting
            {
                manager.connection.stopVPNTunnel()
                for _ in 0..<50 {
                    if manager.connection.status == .disconnected
                        || manager.connection.status == .invalid
                    {
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            manager.isOnDemandEnabled = false
            manager.onDemandRules = []
            manager.isEnabled = false
            try await saveToPreferences(manager)
            try await loadFromPreferences(manager)
            self.manager = manager
            updateStatus(manager.connection.status)
            lastError = ""
            return true
        } catch {
            fail(error)
            return false
        }
    }

    func restorePacketTunnelAfterDNSOnly() async -> Bool {
        do {
            guard let manager = try await loadManager() else {
                lastError = ""
                return true
            }
            manager.isEnabled = true
            try await saveToPreferences(manager)
            try await loadFromPreferences(manager)
            self.manager = manager
            updateStatus(manager.connection.status)
            lastError = ""
            return true
        } catch {
            fail(error)
            return false
        }
    }

    nonisolated static func withNETimeout<T: Sendable>(
        seconds: Double,
        _ timeoutError: NETimeoutError,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<T, Error>) in
            let gate = HakoMacNETimeoutGate(continuation)
            let timeout = Task {
                try? await Task.sleep(for: .seconds(seconds))
                gate.resume(throwing: timeoutError)
            }
            Task {
                defer { timeout.cancel() }
                do {
                    gate.resume(returning: try await operation())
                } catch {
                    gate.resume(throwing: error)
                }
            }
        }
    }

    func currentOrNewManager() async throws
        -> NETunnelProviderManager
    {
        let intent = profileWriteIntentGeneration
        let saved: NETunnelProviderManager?
        do { saved = try await loadManager() }
        catch {
            guard intent == profileWriteIntentGeneration, !Task.isCancelled else { throw CancellationError() }
            systemVPNInstallationKnown = false
            throw error
        }
        try Task.checkCancellation()
        guard intent == profileWriteIntentGeneration else { throw CancellationError() }
        adoptInstalledManager(saved)
        if let saved { return saved }

        let created = NETunnelProviderManager()
        let tunnelProtocol = NETunnelProviderProtocol()
        tunnelProtocol.providerBundleIdentifier =
            Self.packetTunnelExtensionBundleID
        tunnelProtocol.serverAddress = Self.vpnProfileDescription
        routingPolicy.apply(to: tunnelProtocol)
         
         
         
        tunnelProtocol.disconnectOnSleep =
            OnDemandSettings.configuration().disconnectOnSleep
        tunnelProtocol.providerConfiguration = try IPStackSettings.load(from: preferences)
            .applying(to: tunnelProtocol.providerConfiguration)
        created.protocolConfiguration = tunnelProtocol
        created.localizedDescription = Self.vpnProfileDescription
        created.isEnabled = true
        return created
    }

    private static func loadSystemManagers() async throws -> [NETunnelProviderManager] {
        let result = await withCheckedContinuation {
            (continuation:
                CheckedContinuation<HakoMacManagerLoadResult, Never>) in
            NETunnelProviderManager.loadAllFromPreferences {
                managers,
                error in
                continuation.resume(
                    returning: HakoMacManagerLoadResult(managers, error)
                )
            }
        }
        if let error = result.error { throw error }
        return result.managers
    }

    private func loadManager() async throws -> NETunnelProviderManager? {
        let managers = try await Self.withNETimeout(seconds: preferencesReadTimeout, .nePreferencesTimeout) { [self] in
            try await systemVPNManagers()
        }
        return managers.first {
            ($0.protocolConfiguration as? NETunnelProviderProtocol)?
                .providerBundleIdentifier
                == Self.packetTunnelExtensionBundleID
        }
    }

    private func saveToPreferences(_ manager: NETunnelProviderManager, whileIntent intent: UInt64? = nil, disarmOnly: Bool = false) async throws {
        let frozen = IPStackSystemProfileSnapshot(manager)
        try await profileWriter.run { [self] in
            if let intent, intent != profileWriteIntentGeneration { throw CancellationError() }
            frozen.apply(to: manager)
            try await rawSaveToPreferences(manager, disarmOnly: disarmOnly)
        }
    }

    private func rawSaveToPreferences(
        _ manager: NETunnelProviderManager, disarmOnly: Bool = false
    ) async throws {
        let frozen = IPStackSystemProfileSnapshot(manager)
        try await profileWriter.saveConfirmed(frozen, to: manager, disarmOnly: disarmOnly) {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                manager.saveToPreferences { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }

    private func loadFromPreferences(_ manager: NETunnelProviderManager) async throws {
        try await Self.withNETimeout(seconds: preferencesReadTimeout, .nePreferencesTimeout) {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                manager.loadFromPreferences { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            }
        }
    }

    private func removeFromPreferences(
        _ manager: NETunnelProviderManager
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            manager.removeFromPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func updateStatus(_ status: NEVPNStatus) {
        switch status {
        case .invalid, .disconnected: self.status = "disconnected"
        case .connecting, .reasserting: self.status = "connecting"
        case .connected: self.status = "connected"
        case .disconnecting: self.status = "disconnecting"
        @unknown default: self.status = "unavailable"
        }
    }

    private func fail(_: Error) {
        status = "unavailable"
        lastError = "The VPN configuration could not be read or saved."
    }

    func prepareCoreForUIReview(container: URL) {
        do { try Self.ensureCoreSetup(container: container) }
        catch { lastError = error.localizedDescription }
    }

    static func ensureCoreSetup(container: URL, settings: IPStackSettings? = nil) throws {
        try AppCoreSetup.ensure(container: container, settings: settings)
    }
}
