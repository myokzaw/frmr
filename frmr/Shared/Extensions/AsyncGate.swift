import Foundation

/// A small async semaphore: at most `limit` holders at once, the rest wait
/// in order. A waiter whose task is cancelled leaves the queue and gets
/// `false`, so a row that scrolled away never renders.
actor AsyncGate {
    /// Shared by every on-screen thumbnail render.
    static let display = AsyncGate(limit: 2)

    private let limit: Int
    private var running = 0
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Bool, Never>)] = []
    private var cancelledEarly: Set<UUID> = []

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    /// Runs `work` once a slot is free. nil, without running, if the
    /// calling task is cancelled before or while waiting.
    func run<T: Sendable>(_ work: @Sendable () async -> T) async -> T? {
        guard await acquire() else { return nil }
        if Task.isCancelled {
            release()
            return nil
        }
        let result = await work()
        release()
        return result
    }

    private func acquire() async -> Bool {
        if Task.isCancelled { return false }
        if running < limit {
            running += 1
            return true
        }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                if cancelledEarly.remove(id) != nil {
                    continuation.resume(returning: false)
                } else {
                    waiters.append((id, continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        if let index = waiters.firstIndex(where: { $0.id == id }) {
            waiters.remove(at: index).continuation.resume(returning: false)
        } else {
            cancelledEarly.insert(id)
        }
    }

    private func release() {
        if waiters.isEmpty {
            running -= 1
        } else {
            // The slot passes straight to the next waiter
            waiters.removeFirst().continuation.resume(returning: true)
        }
    }
}
