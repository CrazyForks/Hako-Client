import Foundation
import Hako

 
 
 
enum AppCoreSetup {
    private static let lock = NSRecursiveLock()
    private static var containerForApplication: URL?

    static func serialized<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }

    static var applicationContainer: URL? {
        serialized { containerForApplication ?? HakoAppIdentifiers.appGroupContainer }
    }

    static func currentSettings() throws -> IPStackSettings {
        try IPStackSettings.load(from: UserDefaults(suiteName: HakoAppIdentifiers.appGroup) ?? .standard)
    }

    static func withConfiguration<T>(
        container: URL,
        settings: IPStackSettings? = nil,
        memoryLimit: Int64 = 0,
        _ operation: () throws -> T
    ) throws -> T {
        let frozen = try settings ?? currentSettings()
        return try serialized {
            let options = HakoSetupOptions()
            options.basePath = container.path
            options.workingPath = container.appendingPathComponent("working").path
            options.tempPath = container.appendingPathComponent("temp").path
            options.timeZone = TimeZone.current.identifier
            options.logMaxLines = 100
            options.memoryLimit = memoryLimit
            options.disablePersistentCache = true
#if os(macOS)
            options.runtimeProfile = "macosPacketTunnel"
#endif
            options.ipQueryMode = frozen.queryMode.rawValue
            options.tunIPv6Mode = frozen.tunIPv6Mode.rawValue
            options.systemDNSServerLines = HakoSystemResolverLines()
            var error: NSError?
            HakoSetup(options, &error)
            if let error { throw error }
            return try operation()
        }
    }

     
     
    static func ensure(container: URL, settings: IPStackSettings? = nil, memoryLimit: Int64 = 0) throws {
        try withConfiguration(container: container, settings: settings, memoryLimit: memoryLimit) {
            containerForApplication = container
        }
    }
}
