import Foundation

/// Thrown when work was stopped on request. Not a failure: whatever was partly done is kept where that is useful.
public struct Cancelled: Error, CustomStringConvertible {
    public init() {}
    public var description: String { "Stopped." }
}

/// A way to stop long work (a download, an unpack) from another thread.
public final class Cancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var handlers: [@Sendable () -> Void] = []

    public init() {}

    public var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    public func cancel() {
        let pending: [@Sendable () -> Void] = lock.withLock {
            guard !cancelled else { return [] }
            cancelled = true
            defer { handlers = [] }
            return handlers
        }
        pending.forEach { $0() }
    }

    /// Runs `handler` when cancelled, or straight away if that has already happened.
    func onCancel(_ handler: @escaping @Sendable () -> Void) {
        let runNow = lock.withLock {
            if cancelled { return true }
            handlers.append(handler)
            return false
        }
        if runNow { handler() }
    }

    public func check() throws {
        if isCancelled { throw Cancelled() }
    }
}
