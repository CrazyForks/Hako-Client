import Foundation
import HakoClientKit

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct StorageMaintenance {
    enum Area: String, CaseIterable, Hashable, Sendable {
        case configurations, library, geodata, providerCaches, compiledGeodata, logs, temporary
    }

    struct Measurement: Equatable, Sendable {
        let area: Area
         
        let bytes: Int64
         
        let reclaimable: Int64
    }

    struct Outcome: Equatable, Sendable {
        var reclaimedBytes: Int64 = 0
        var areas: [Area] = []
    }

    let containerURL: URL
     
     
    let tunnelIsRunning: () -> Bool

    init(containerURL: URL, tunnelIsRunning: @escaping () -> Bool) {
        self.containerURL = containerURL
        self.tunnelIsRunning = tunnelIsRunning
    }

    static let namedGeodataFiles = GeodataManager.namedGeodataFiles

    private var working: URL { containerURL.appendingPathComponent("working", isDirectory: true) }
    private var fileManager: FileManager { .default }

     

    func measure() -> [Measurement] { Area.allCases.map(measure) }

    func measure(_ area: Area) -> Measurement {
        let bytes = paths(area).reduce(0) { $0 + StorageMeasurement.allocatedBytes(at: $1) }
        let reclaimable = reclaimableItems(area).reduce(0) { $0 + StorageMeasurement.allocatedBytes(at: $1) }
        return Measurement(area: area, bytes: bytes, reclaimable: min(reclaimable, bytes))
    }

     
    func paths(_ area: Area) -> [URL] {
        switch area {
        case .configurations:
            return [working.appendingPathComponent("store", isDirectory: true)]
        case .library:
            return [working.appendingPathComponent("configuration-library", isDirectory: true)]
        case .geodata:
            return [working.appendingPathComponent("geodata", isDirectory: true)]
                + Self.namedGeodataFiles.map { working.appendingPathComponent($0) }
        case .providerCaches:
            return [working.appendingPathComponent("provider-runtime", isDirectory: true)]
        case .compiledGeodata:
            return [working.appendingPathComponent("compiled-geoip", isDirectory: true),
                    working.appendingPathComponent("compiled-geosite", isDirectory: true)]
        case .logs:
            return [containerURL.appendingPathComponent("logs", isDirectory: true)]
        case .temporary:
            return temporaryItems()
        }
    }

     
    func reclaimableItems(_ area: Area) -> [URL] {
        switch area {
        case .configurations:
            guard let store = try? ConfigResourceStore(containerURL: containerURL) else { return [] }
            return (try? store.orphanedProfileDirectories(registered: registeredProfileIDs())) ?? []
        case .library, .providerCaches, .logs:
            return []
        case .geodata:
            return GeodataManager.staleGeodataBlobs(homeDir: working)
        case .compiledGeodata:
            return tunnelIsRunning() ? [] : paths(.compiledGeodata).filter { fileManager.fileExists(atPath: $0.path) }
        case .temporary:
            return temporaryItems()
        }
    }

     

     
     
    @discardableResult
    func reclaim() throws -> Outcome {
        var outcome = Outcome()
        for area in Area.allCases {
            let before = measure(area).reclaimable
            guard before > 0 else { continue }
            switch area {
            case .configurations:
                let store = try ConfigResourceStore(containerURL: containerURL)
                try store.removeOrphanedProfileDirectories(registered: registeredProfileIDs())
            case .geodata:
                GeodataManager.removeStaleGeodataBlobs(homeDir: working)
            case .compiledGeodata:
                guard !tunnelIsRunning() else { continue }
                for url in paths(.compiledGeodata) { try? fileManager.removeItem(at: url) }
            case .temporary:
                for url in temporaryItems() { try? fileManager.removeItem(at: url) }
            case .library, .providerCaches, .logs:
                continue
            }
            let freed = before - measure(area).reclaimable
            if freed > 0 {
                outcome.reclaimedBytes += freed
                outcome.areas.append(area)
            }
        }
        return outcome
    }

     

     
     
    func registeredProfileIDs() -> Set<String> {
        let store = ProfileStore(fileURL: working.appendingPathComponent("store/profiles.json"))
        var ids = Set(store.load().map(\.id))
        let library = ConfigurationLibraryStore(directory: working.appendingPathComponent("configuration-library"))
        if let pending = try? library.snapshot().pendingPublications {
            ids.formUnion(pending.map(\.profileID))
        }
        return ids
    }

     
     
    private func temporaryItems() -> [URL] {
        var items: [URL] = []
        let temp = containerURL.appendingPathComponent("temp", isDirectory: true)
        if fileManager.fileExists(atPath: temp.path) { items.append(temp) }
        let store = working.appendingPathComponent("store", isDirectory: true)
        if let enumerator = fileManager.enumerator(at: store, includingPropertiesForKeys: [.isDirectoryKey], options: []) {
            for case let url as URL in enumerator where url.lastPathComponent.hasPrefix(".tmp-") {
                items.append(url)
                enumerator.skipDescendants()
            }
        }
        return items
    }
}

 
enum StorageMeasurement {
    static func allocatedBytes(at url: URL, fileManager: FileManager = .default) -> Int64 {
        guard let values = try? url.resourceValues(
            forKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        ) else { return 0 }
        if values.isDirectory != true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let child as URL in enumerator {
            guard let childValues = try? child.resourceValues(
                forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
            ), childValues.isRegularFile == true else { continue }
            total += Int64(childValues.totalFileAllocatedSize ?? childValues.fileAllocatedSize ?? 0)
        }
        return total
    }
}
