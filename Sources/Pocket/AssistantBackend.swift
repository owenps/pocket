import Foundation

/// A text-reply adapter, not a transport or provider registry.
/// History includes the accepted input, without an empty reply placeholder.
/// Emit ordered text deltas only before returning; return to complete, throw to fail.
/// Cancellation must stop backend work where supported. Never block the main actor.
@MainActor
protocol AssistantBackend {
    func reply(
        to history: [ConversationMessage],
        onText: @escaping @MainActor (String) -> Void
    ) async throws
}

struct DemoAssistantBackend: AssistantBackend {
    private let delay: @Sendable (Duration) async throws -> Void

    init(delay: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.delay = delay
    }

    func reply(
        to history: [ConversationMessage],
        onText: @escaping @MainActor (String) -> Void
    ) async throws {
        // Local visual rehearsal only: no reasoning, tools, or external actions.
        let replies = [
            "Would you like a reminder, a task, or a quick conversation about that?",
            "What timing or extra detail would you want your assistant to have?",
            "Understood. This is a local preview; nothing has been created or scheduled. Your connected assistant would handle the work from here.",
        ]
        let turn = max(0, history.filter { $0.role == .user }.count - 1)
        let response = replies[min(turn, replies.count - 1)]
        try await delay(.milliseconds(900))
        try Task.checkCancellation()
        for (index, word) in response.split(separator: " ").enumerated() {
            try await delay(.milliseconds(45))
            try Task.checkCancellation()
            onText((index == 0 ? "" : " ") + word)
        }
    }
}
