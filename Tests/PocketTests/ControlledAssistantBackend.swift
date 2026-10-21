import Foundation
import PocketTestSupport
@testable import Pocket

/// Deliberately retains callbacks and ignores cancellation until explicitly finished.
@MainActor
final class ControlledAssistantBackend: AssistantBackend {
    @MainActor
    final class Run {
        let history: [ConversationMessage]
        private let onText: @MainActor (String) -> Void
        private var continuation: CheckedContinuation<Void, any Error>?
        private(set) var didReturn = false
        private(set) var wasCancelled = false

        var isPending: Bool { continuation != nil }

        fileprivate init(
            history: [ConversationMessage],
            onText: @escaping @MainActor (String) -> Void,
            continuation: CheckedContinuation<Void, any Error>
        ) {
            self.history = history
            self.onText = onText
            self.continuation = continuation
        }

        func emit(_ delta: String) {
            onText(delta)
        }

        func finish(_ result: Result<Void, any Error> = .success(())) {
            let pending = continuation
            continuation = nil
            pending?.resume(with: result)
        }

        fileprivate func returned(cancelled: Bool) {
            wasCancelled = cancelled
            didReturn = true
        }
    }

    private(set) var runs: [Run] = []
    var runCount: Int { runs.count }

    func reply(
        to history: [ConversationMessage],
        onText: @escaping @MainActor (String) -> Void
    ) async throws {
        let index = runs.count
        defer { runs[index].returned(cancelled: Task.isCancelled) }
        try await withCheckedThrowingContinuation { continuation in
            runs.append(Run(history: history, onText: onText, continuation: continuation))
        }
    }

    func waitForRun(at index: Int) async throws -> Run {
        try await waitUntil { self.runs.count > index }
        return runs[index]
    }

    /// Finish even cancelled requests so no checked continuation escapes a test.
    func drain() async throws {
        for run in runs { run.finish() }
        try await waitUntil { self.runs.allSatisfy(\.didReturn) }
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        try await AsyncTestSupport.wait(until: condition)
    }
}
