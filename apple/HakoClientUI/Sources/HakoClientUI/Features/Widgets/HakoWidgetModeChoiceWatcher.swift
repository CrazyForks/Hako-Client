import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
public final class HakoWidgetModeChoiceWatcher {
    private let store: HakoWidgetMailboxStore
    private let heard: @MainActor () -> Void
    private var source: DispatchSourceFileSystemObject?

     
     
     
     
    public var isListening: Bool { source != nil }

    public init(store: HakoWidgetMailboxStore, heard: @escaping @MainActor () -> Void) {
        self.store = store
        self.heard = heard
    }

     
     
     
     
     
     
    @discardableResult
    public func start() -> Bool {
        if source == nil { arm() }
        report()
        return isListening
    }

    public func stop() {
        source?.cancel()
        source = nil
    }

    deinit {
         
         
        source?.cancel()
    }

    private func arm() {
        let directory = store.root.appendingPathComponent(HakoWidgetMailbox.directory, isDirectory: true)
         
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .delete, .rename], queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.changed() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    private func changed() {
        guard let source else { return }
        if !source.data.isDisjoint(with: [.delete, .rename]) {
             
             
             
            stop()
            arm()
        }
        report()
    }

    private func report() {
        if store.readModeChoice() != nil { heard() }
    }
}
