import Foundation

 
 
 
 
 
 
 
 
public enum HakoWidgetMailbox {
    public static let directory = "widgets"
     
    public static let requestFile = "widgets/request.json"
     
    public static let snapshotFile = "widgets/snapshot.json"
     
    public static let appFile = "widgets/app.json"
     
     
    public static let modeFile = "widgets/mode.json"
    public static let requestNotification = "org.example.hako.widget.request"
     
    public static let updatedNotification = "org.example.hako.widget.updated"
     
     
    public static let waitForSnapshot: TimeInterval = 1.5
     
     
     
     
    public static let groupMemberLimit = 16

     
     
     
     
     
     
     
    public enum Kind {
        public static let main = "org.example.hako.widget.main"
        public static let all = [main]
    }
}

public struct HakoWidgetRequest: Codable, Equatable, Sendable {
    public enum Command: Codable, Equatable, Sendable {
        case refresh
        case setMode(HakoWidgetMode)
        case select(group: String, name: String)
    }

    public let id: String
    public let command: Command
     
     
    public let group: String?
    public let at: Date

    public init(command: Command, group: String?, at: Date = Date()) {
        id = UUID().uuidString
        self.command = command
        self.group = group
        self.at = at
    }
}

 
 
 
 
 
 
public struct HakoWidgetModeChoice: Codable, Equatable, Sendable {
    public let mode: HakoWidgetMode
    public let at: Date

    public init(mode: HakoWidgetMode, at: Date) {
        self.mode = mode
        self.at = at
    }
}

 
 
 
public struct HakoWidgetAppFacts: Codable, Equatable, Sendable {
    public let profile: String?
    public let firstGroup: String?
    public let groups: [String]
     
     
    public let members: [String: [String]]
     
    public let selections: [String: String]
     
     
     
     
     
    public let mode: HakoWidgetMode?
     
     
     
     
     
    public let countsWired: Bool?
    public let writtenAt: Date

    public init(
        profile: String?, firstGroup: String?, groups: [String],
        members: [String: [String]] = [:], selections: [String: String] = [:],
        mode: HakoWidgetMode? = nil, countsWired: Bool? = nil,
        writtenAt: Date
    ) {
        self.profile = profile
        self.firstGroup = firstGroup
        self.groups = groups
        self.members = members
        self.selections = selections
        self.mode = mode
        self.countsWired = countsWired
        self.writtenAt = writtenAt
    }
}

 
 
 
 
 
 
public enum HakoWidgetStoredMode {
     
     
    public static let key = "config.runtime.flclash.v1"

    public static func read(from defaults: UserDefaults) -> HakoWidgetMode? {
        guard let data = defaults.data(forKey: key),
              let record = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let patchJSON = record["patchJSON"] as? String,
              let patch = (try? JSONSerialization.jsonObject(with: Data(patchJSON.utf8))) as? [String: Any],
              let mode = patch["mode"] as? String else { return nil }
        return HakoWidgetMode(rawValue: mode.lowercased())
    }
}

 
 
 
 
public struct HakoWidgetMailboxStore {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func readSnapshot() -> HakoWidgetSnapshot? {
        read(HakoWidgetMailbox.snapshotFile)
    }

    public func writeSnapshot(_ snapshot: HakoWidgetSnapshot) throws {
        try write(snapshot, to: HakoWidgetMailbox.snapshotFile)
    }

    public func readAppFacts() -> HakoWidgetAppFacts? {
        read(HakoWidgetMailbox.appFile)
    }

    public func writeAppFacts(_ facts: HakoWidgetAppFacts) throws {
        try write(facts, to: HakoWidgetMailbox.appFile)
    }

    public func readModeChoice() -> HakoWidgetModeChoice? {
        read(HakoWidgetMailbox.modeFile)
    }

    public func writeModeChoice(_ choice: HakoWidgetModeChoice) throws {
        try write(choice, to: HakoWidgetMailbox.modeFile)
    }

    public func clearModeChoice() {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(HakoWidgetMailbox.modeFile))
    }

     
     
    public func restingMode(stored: HakoWidgetMode?) -> HakoWidgetMode? {
        readModeChoice()?.mode ?? stored
    }

    public func writeRequest(_ request: HakoWidgetRequest) throws {
        try write(request, to: HakoWidgetMailbox.requestFile)
    }

     
    public func takeRequest() -> HakoWidgetRequest? {
        guard let request: HakoWidgetRequest = read(HakoWidgetMailbox.requestFile) else { return nil }
        try? FileManager.default.removeItem(at: root.appendingPathComponent(HakoWidgetMailbox.requestFile))
        return request
    }

    private func read<T: Decodable>(_ relative: String) -> T? {
        guard let data = try? Data(contentsOf: root.appendingPathComponent(relative)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(T.self, from: data)
    }

    private func write<T: Encodable>(_ value: T, to relative: String) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
