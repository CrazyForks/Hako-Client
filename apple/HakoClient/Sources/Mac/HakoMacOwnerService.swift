#if os(macOS)
import Darwin
import Foundation
import os

 
 
 
 
 
 
 
 
 
 
 
final class HakoMacOwnerService: @unchecked Sendable {
    static let socketName = "owner.sock"

    private let path: String
    private let owners: HakoMacSocketOwners
    private var listener: Int32 = -1
    private let counter = NSLock()
    private var asked = 0
    private var answered = 0
    private var took: [UInt64] = []
    private static let log = Logger(subsystem: "org.example.hako", category: "process-owner")

    init?(container: URL, owners: HakoMacSocketOwners = .shared) {
        let path = container.appendingPathComponent(Self.socketName).path
         
        guard path.utf8.count < 104 else { return nil }
        self.path = path
        self.owners = owners
    }

     
     
    func start() {
        guard listener < 0 else { return }
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        var address = Self.address(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(fd, 8) == 0 else {
            Self.log.error("owner.sock listen failed errno=\(errno, privacy: .public) path=\(self.path, privacy: .public)")
            close(fd)
            return
        }
        Self.log.info("owner.sock listening path=\(self.path, privacy: .public)")
        listener = fd
        let thread = Thread { [weak self] in self?.acceptLoop(fd) }
        thread.name = "hako.owner-service"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    private func acceptLoop(_ fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return
            }
            var on: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            let thread = Thread { [weak self] in self?.serve(client) }
            thread.name = "hako.owner-service.client"
            thread.qualityOfService = .userInitiated
            thread.start()
        }
    }

    private func serve(_ client: Int32) {
        defer { close(client) }
        var pending = [UInt8]()
        var chunk = [UInt8](repeating: 0, count: 1024)
        while true {
            let count = read(client, &chunk, chunk.count)
            guard count > 0 else { return }
            pending.append(contentsOf: chunk[0..<count])
            while let newline = pending.firstIndex(of: 0x0A) {
                let line = String(decoding: pending[..<newline], as: UTF8.self)
                pending.removeSubrange(...newline)
                let started = DispatchTime.now().uptimeNanoseconds
                let text = answer(line)
                note(question: line, reply: text, took: DispatchTime.now().uptimeNanoseconds &- started)
                let reply = Array((text + "\n").utf8)
                guard reply.withUnsafeBytes({ write(client, $0.baseAddress, reply.count) }) == reply.count else { return }
            }
            if pending.count > 4096 { return }
        }
    }

     
     
     
     
    private func note(question: String, reply: String, took nanoseconds: UInt64) {
        counter.lock()
        asked += 1
        if reply.hasPrefix("O ") { answered += 1 }
        took.append(nanoseconds)
        let (n, hits) = (asked, answered)
        var window: [UInt64] = []
        if took.count == 200 { window = took.sorted(); took.removeAll(keepingCapacity: true) }
        counter.unlock()
        if !window.isEmpty {
            func ms(_ q: Double) -> String {
                String(format: "%.2f", Double(window[min(window.count - 1, Int(Double(window.count) * q))]) / 1e6)
            }
            Self.log.info("owner.sock took n=\(n, privacy: .public) answered=\(hits, privacy: .public) p50=\(ms(0.5), privacy: .public)ms p90=\(ms(0.9), privacy: .public)ms p99=\(ms(0.99), privacy: .public)ms max=\(ms(1), privacy: .public)ms")
        }
        guard n <= 20 || n % 500 == 0 else { return }
        Self.log.info("owner.sock n=\(n, privacy: .public) answered=\(hits, privacy: .public) q=\(question, privacy: .public) a=\(reply, privacy: .public)")
    }

     
    func answer(_ line: String) -> String {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 6, parts[0] == "Q",
              let proto = UInt8(parts[1]), proto == 6 || proto == 17,
              let sourcePort = UInt16(parts[3]),
              let destinationPort = UInt16(parts[5])
        else { return "N" }
        guard let owner = owners.owner(
            proto: proto, source: parts[2], sourcePort: sourcePort,
            destination: parts[4], destinationPort: destinationPort
        ), !owner.path.isEmpty else { return "N" }
        return "O \(owner.uid)\t\(Self.userName(owner.uid))\t\(owner.path)"
    }

    private static func userName(_ uid: Int32) -> String {
        var record = passwd()
        var result: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: 1024)
        guard getpwuid_r(uid_t(bitPattern: uid), &record, &buffer, buffer.count, &result) == 0,
              let name = result?.pointee.pw_name
        else { return "" }
        return String(cString: name)
    }

    static func address(_ path: String) -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            let bytes = Array(path.utf8.prefix(raw.count - 1))
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return address
    }
}
#endif
