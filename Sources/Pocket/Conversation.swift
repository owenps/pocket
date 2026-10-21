import Foundation

enum ConversationRole {
    case user
    case assistant
}

enum ReplyOutcome: Equatable {
    case completed
    case stopped
    case failed(String)
}

struct ConversationMessage: Identifiable, Equatable {
    let id: UUID
    let role: ConversationRole
    var text: String
    var outcome: ReplyOutcome?

    var isStopped: Bool { outcome == .stopped }
    var failure: String? {
        if case .failed(let description)? = outcome { description } else { nil }
    }

    init(id: UUID = UUID(), role: ConversationRole, text: String, outcome: ReplyOutcome? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.outcome = outcome
    }
}

enum ReplyPhase: Equatable {
    case idle
    case working
    case streaming
}
