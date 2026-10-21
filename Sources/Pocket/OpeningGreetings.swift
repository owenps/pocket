import Foundation

/// Opening copy only; follow-up messages use a neutral placeholder.
enum OpeningGreetings {
    static func messages(userName: String, hour: Int) -> [String] {
        let name = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = name.isEmpty ? "" : ", \(name)"
        var messages = [
            "What’s next?",
            "Need a hand?",
            "How can I help?",
            "Having a good day?",
            "How’s it going?",
            "Welcome back\(suffix)!"
        ]
        if !name.isEmpty {
            messages.append("Hello \(name)!")
        }
        switch hour {
        case 5..<12: messages.append("Good morning\(suffix)!")
        case 12..<17: messages.append("Good afternoon\(suffix)!")
        default: break
        }
        return messages
    }
}
