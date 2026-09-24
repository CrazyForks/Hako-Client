import Foundation
import Network

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
final class BearerWitnessSystemStackProbe {
     
    static let linePrefix = "[Apple] bearer witness:"
     
    static let timeout: TimeInterval = 2

    private let queue: DispatchQueue
    private let readHealth: () -> String
    private let dialer: any SystemStackDialing
    private let report: (_ address: String, _ atUnix: Int64, _ connected: Bool, _ tookMillis: Int64, _ failure: String) -> Void
    private let log: (String) -> Void
     
    private var probedAtUnix: Int64?

    init(
        queue: DispatchQueue,
        readHealth: @escaping () -> String,
        dialer: any SystemStackDialing,
        report: @escaping (_ address: String, _ atUnix: Int64, _ connected: Bool, _ tookMillis: Int64, _ failure: String) -> Void,
        log: @escaping (String) -> Void
    ) {
        self.queue = queue
        self.readHealth = readHealth
        self.dialer = dialer
        self.report = report
        self.log = log
    }

     
     
     
    func observe(coreLine: String) {
        guard coreLine.contains(Self.linePrefix) else { return }
        queue.async { [self] in probeIfNewNetworkVerdict() }
    }

    private func probeIfNewNetworkVerdict() {
        guard let verdict = BearerWitnessVerdict.parse(healthJSON: readHealth()),
              verdict.kind == "network",
              verdict.atUnix != probedAtUnix
        else { return }
        guard let target = BearerWitnessVerdict.dialTarget(of: verdict.address) else {
             
             
             
            probedAtUnix = verdict.atUnix
            log("bearer witness probe: the verdict's address cannot be dialled as host:port: \(verdict.address)")
            return
        }
        guard dialer.canDial else {
             
             
             
            log("bearer witness probe: no physical interface to pin the dial to; \(verdict.address) not dialled")
            return
        }
         
         
        probedAtUnix = verdict.atUnix
        let address = verdict.address
        let atUnix = verdict.atUnix
        let report = report
        dialer.dial(host: target.host, port: target.port, timeout: Self.timeout) { outcome in
            switch outcome {
            case .connected(let tookMillis):
                report(address, atUnix, true, tookMillis, "")
            case .failed(let reason, let tookMillis):
                report(address, atUnix, false, tookMillis, reason)
            }
        }
    }
}

 
 
 
struct BearerWitnessVerdict: Equatable {
    let kind: String
    let address: String
    let atUnix: Int64

    static func parse(healthJSON: String) -> BearerWitnessVerdict? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(healthJSON.utf8)) as? [String: Any],
              let witness = object["bearerWitness"] as? [String: Any],
              let kind = witness["kind"] as? String,
              let address = witness["address"] as? String,
              let atUnix = (witness["atUnix"] as? NSNumber)?.int64Value
        else { return nil }
        return BearerWitnessVerdict(kind: kind, address: address, atUnix: atUnix)
    }

     
     
     
    static func dialTarget(of address: String) -> (host: String, port: UInt16)? {
        guard let colon = address.lastIndex(of: ":") else { return nil }
        var host = String(address[..<colon])
        guard let port = UInt16(address[address.index(after: colon)...]), port != 0 else { return nil }
        if host.hasPrefix("["), host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }
        guard !host.isEmpty else { return nil }
        return (host, port)
    }
}

enum SystemStackDialOutcome: Equatable {
    case connected(tookMillis: Int64)
    case failed(reason: String, tookMillis: Int64)
}

 
protocol SystemStackDialing {
     
     
     
    var canDial: Bool { get }
    func dial(host: String, port: UInt16, timeout: TimeInterval, completion: @escaping (SystemStackDialOutcome) -> Void)
}

 
 
 
 
 
 
final class AppleSystemStackDialer: SystemStackDialing {
    private let queue: DispatchQueue
    private let physicalInterface: () -> NWInterface?

    init(queue: DispatchQueue, physicalInterface: @escaping () -> NWInterface?) {
        self.queue = queue
        self.physicalInterface = physicalInterface
    }

    var canDial: Bool { physicalInterface() != nil }

    func dial(host: String, port: UInt16, timeout: TimeInterval, completion: @escaping (SystemStackDialOutcome) -> Void) {
        guard let port = NWEndpoint.Port(rawValue: port) else {
            completion(.failed(reason: "port out of range", tookMillis: 0))
            return
        }
        guard let interface = physicalInterface() else {
             
             
            completion(.failed(reason: "the physical interface left before the dial", tookMillis: 0))
            return
        }
        let parameters = NWParameters.tcp
        parameters.requiredInterface = interface
        parameters.prohibitedInterfaceTypes = [.other]
        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: parameters)
        let started = DispatchTime.now()
        var answered = false
         
         
         
        var lastWaiting: NWError?
        let answer: (SystemStackDialOutcome?) -> Void = { outcome in
            guard !answered else { return }
            answered = true
            connection.stateUpdateHandler = nil
            connection.cancel()
            let took = Int64((DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000)
            switch outcome {
            case .connected: completion(.connected(tookMillis: took))
            case .failed(let reason, _): completion(.failed(reason: reason, tookMillis: took))
            case nil:
                let waiting = lastWaiting.map { " (waiting: \(Self.describe($0)))" } ?? ""
                completion(.failed(reason: "timed out\(waiting)", tookMillis: took))
            }
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                answer(.connected(tookMillis: 0))
            case .failed(let error):
                answer(.failed(reason: Self.describe(error), tookMillis: 0))
            case .waiting(let error):
                lastWaiting = error
            case .cancelled:
                answer(.failed(reason: "cancelled", tookMillis: 0))
            case .setup, .preparing:
                break
            @unknown default:
                break
            }
        }
        queue.asyncAfter(deadline: .now() + timeout) { answer(nil) }
        connection.start(queue: queue)
    }

     
     
     
    static func describe(_ error: NWError) -> String {
        String(describing: error)
    }
}
