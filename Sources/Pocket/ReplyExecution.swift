import Foundation

/// Pure run transitions; ConversationSession applies task and transcript effects.
struct ReplyExecution: Equatable {
    enum Event {
        case start(runID: UUID, replyID: UUID)
        case delta(runID: UUID, text: String)
        case finished(runID: UUID, outcome: ReplyOutcome)
        case stop
    }

    enum Effect: Equatable {
        case start(runID: UUID)
        case append(replyID: UUID, text: String)
        case complete(replyID: UUID, outcome: ReplyOutcome)
        case cancel
    }

    struct Transition {
        let execution: ReplyExecution
        let effects: [Effect]
    }

    private struct Run: Equatable {
        let runID: UUID
        let replyID: UUID
    }

    private enum State: Equatable {
        case idle
        case working(Run)
        case streaming(Run)
    }

    private var state: State = .idle

    init() {}

    var phase: ReplyPhase {
        switch state {
        case .idle: .idle
        case .working: .working
        case .streaming: .streaming
        }
    }

    func transition(_ event: Event) -> Transition? {
        var execution = self
        let effects: [Effect]
        switch (state, event) {
        case let (.idle, .start(runID, replyID)):
            execution.state = .working(Run(runID: runID, replyID: replyID))
            effects = [.start(runID: runID)]

        case let (.working(run), .delta(runID, text)),
             let (.streaming(run), .delta(runID, text)):
            guard run.runID == runID, !text.isEmpty else { return nil }
            execution.state = .streaming(run)
            effects = [.append(replyID: run.replyID, text: text)]

        case let (.working(run), .finished(runID, outcome)),
             let (.streaming(run), .finished(runID, outcome)):
            guard run.runID == runID else { return nil }
            let result: ReplyOutcome = phase == .working && outcome == .completed
                ? .failed("No reply received.") : outcome
            execution.state = .idle
            effects = [.complete(replyID: run.replyID, outcome: result)]

        case let (.working(run), .stop), let (.streaming(run), .stop):
            execution.state = .idle
            effects = [.cancel, .complete(replyID: run.replyID, outcome: .stopped)]

        default:
            return nil
        }
        return Transition(execution: execution, effects: effects)
    }
}
