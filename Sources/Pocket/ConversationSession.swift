import Foundation
import Observation

/// App-lifetime conversation and execution. Knows nothing about windows or focus.
@MainActor
@Observable
final class ConversationSession {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let backend: any AssistantBackend
    @ObservationIgnored private var replyTask: Task<Void, Never>?
    private var execution = ReplyExecution()

    var draft: String {
        didSet { defaults.set(draft, forKey: "draft") }
    }

    private(set) var messages: [ConversationMessage] = []
    private(set) var unreadReplyID: UUID?

    var replyPhase: ReplyPhase { execution.phase }
    var isBusy: Bool { replyPhase != .idle }
    var hasUnreadReply: Bool { unreadReplyID != nil }

    init(backend: any AssistantBackend, defaults: UserDefaults = .standard) {
        self.backend = backend
        self.defaults = defaults
        draft = defaults.string(forKey: "draft") ?? ""
    }

    deinit {
        replyTask?.cancel()
    }

    @discardableResult
    func submitDraft() -> Bool {
        let input = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return false }
        if input.hasPrefix("/") {
            guard let command = ConversationCommand(rawValue: input) else { return false }
            switch command {
            case .new: reset()
            case .stop: stopReply()
            }
            draft = ""
            return true
        }
        let reply = ConversationMessage(role: .assistant, text: "")
        guard let transition = execution.transition(.start(runID: UUID(), replyID: reply.id)) else { return false }
        messages.append(ConversationMessage(role: .user, text: draft))
        messages.append(reply)
        draft = ""
        apply(transition)
        return true
    }

    func stopReply() {
        receive(.stop)
    }

    func reset() {
        stopReply()
        messages = []
        unreadReplyID = nil
    }

    /// The presentation owner establishes visibility before acknowledging a reply.
    func markReplyViewed(_ id: UUID) {
        guard !isBusy, unreadReplyID == id else { return }
        unreadReplyID = nil
    }

    private func receive(_ event: ReplyExecution.Event) {
        guard let transition = execution.transition(event) else { return }
        apply(transition)
    }

    private func apply(_ transition: ReplyExecution.Transition) {
        execution = transition.execution
        for effect in transition.effects {
            switch effect {
            case .start(let runID):
                startReply(runID: runID)
            case .append(let replyID, let text):
                precondition(messages.last?.id == replyID, "The active run owns the trailing reply")
                messages[messages.count - 1].text += text
                unreadReplyID = replyID
            case .complete(let replyID, let outcome):
                precondition(messages.last?.id == replyID, "The active run owns the trailing reply")
                messages[messages.count - 1].outcome = outcome
                unreadReplyID = replyID
                replyTask = nil
            case .cancel:
                replyTask?.cancel()
            }
        }
    }

    private func startReply(runID: UUID) {
        // History includes accepted input, but not the empty reply placeholder.
        let history = Array(messages.dropLast())
        // Capture the backend and input, not the session, across suspension.
        replyTask = Task { [weak self, backend] in
            do {
                try Task.checkCancellation()
                try await backend.reply(to: history) { [weak self] delta in
                    self?.receive(.delta(runID: runID, text: delta))
                }
                try Task.checkCancellation()
                self?.receive(.finished(runID: runID, outcome: .completed))
            } catch is CancellationError {
                self?.receive(.finished(runID: runID, outcome: .stopped))
            } catch {
                self?.receive(.finished(runID: runID, outcome: .failed(error.localizedDescription)))
            }
        }
    }
}
