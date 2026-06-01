// ============================================================================
// AsyncBridge.swift — Run an async throws operation from the synchronous
// top-level main script, blocking until completion. Used for FoundationModels
// integration (Cleaner) which is async-only.
// ============================================================================

import Foundation
import AugeCore

/// Block the current thread until the async operation completes.
/// Returns the value or rethrows the error. Designed for CLI top-level use only.
/// The operation MUST be free of main-actor hops — it runs on a detached task while
/// this thread blocks, so a main-actor dependency would deadlock.
func runAsync<T: Sendable>(_ operation: @Sendable @escaping () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    // Self-describing sentinel: only observable on the impossible path where the task
    // never runs, so a future regression surfaces a clear error, not a cancellation lie.
    nonisolated(unsafe) var result: Result<T, Error> =
        .failure(AugeError.unknown("runAsync: operation produced no result"))

    Task.detached {
        do {
            let value = try await operation()
            result = .success(value)
        } catch {
            result = .failure(error)
        }
        semaphore.signal()
    }

    semaphore.wait()
    return try result.get()
}
