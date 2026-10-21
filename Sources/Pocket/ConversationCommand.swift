import Foundation

enum ConversationCommand: String, CaseIterable {
    case new = "/new"
    case stop = "/stop"

    var summary: String {
        switch self {
        case .new: "start a new conversation"
        case .stop: "interrupt the response"
        }
    }

    /// Nil means ordinary text; an empty list means an unsupported command.
    static func suggestions(for draft: String) -> [Self]? {
        let input = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.hasPrefix("/") else { return nil }
        return allCases.filter { $0.rawValue.hasPrefix(input) }
    }
}
