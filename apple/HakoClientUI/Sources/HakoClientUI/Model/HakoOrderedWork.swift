import Foundation

 
 
 
 
 
 
 
 
 
@MainActor
public final class HakoOrderedWork {
    private var last: Task<Void, Never>?

    public nonisolated init() {}

    public func run<T: Sendable>(_ body: @escaping @MainActor () async throws -> T) async throws -> T {
        let previous = last
        let job = Task { @MainActor () throws -> T in
            await previous?.value
            return try await body()
        }
        last = Task { @MainActor in _ = await job.result }
        return try await job.value
    }
}
