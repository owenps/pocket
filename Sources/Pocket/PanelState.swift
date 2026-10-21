import AppKit
import Foundation
import Observation

enum ConversationPresentation: Equatable {
    case capture, thread, unread
}

/// Panel presentation and preferences. Never owns the assistant's execution.
@MainActor
@Observable
final class PanelState {
    let conversation: ConversationSession
    @ObservationIgnored private let defaults: UserDefaults

    static let defaultFontSize = Double(NSFont.preferredFont(forTextStyle: .body).pointSize)
    static let fontSizeRange = 11.0...24.0
    private var storedFontSize: Double
    var fontSize: Double {
        get { storedFontSize }
        set {
            guard newValue.isFinite else { return }
            storedFontSize = min(Self.fontSizeRange.upperBound, max(Self.fontSizeRange.lowerBound, newValue))
            defaults.set(storedFontSize, forKey: "fontSize")
        }
    }

    var userName: String {
        didSet { defaults.set(userName, forKey: "userName") }
    }

    var showBuddy: Bool {
        didSet { defaults.set(showBuddy, forKey: "showBuddy") }
    }

    var avatar: AvatarAppearance {
        didSet {
            if let data = try? JSONEncoder().encode(avatar) {
                defaults.set(data, forKey: "avatarAppearance")
            }
        }
    }

    var shortcut: ShortcutChoice {
        didSet { defaults.set(shortcut.rawValue, forKey: "shortcut") }
    }

    var shortcutError: String?
    var focusRequest = 0
    var isExpanded = false
    var expansionProgress = 0.0
    var buddyEntranceProgress = 1.0
    var surfaceRect = CGRect(x: 0, y: 0, width: 96, height: 24)
    var editorHeight: CGFloat
    var displayedEditorHeight: CGFloat
    var displayedComposerHeight: CGFloat

    var composerHeight: CGFloat {
        max(editorHeight, showBuddy ? avatar.size.points : 0)
    }

    var naturalTranscriptHeight: CGFloat = 0
    var transcriptGap: CGFloat = 0
    var contentHeight: CGFloat = 88
    var expandedSize = CGSize(width: 460, height: 88)
    var collapsedSize = CGSize(width: 96, height: 24)
    var notchHeight: CGFloat = 0
    var transcriptHeight: CGFloat = 0
    var transcriptFocusRequest = 0
    private(set) var conversationPresentation: ConversationPresentation = .capture

    var presentedMessages: [ConversationMessage] {
        switch conversationPresentation {
        case .capture: []
        case .thread: conversation.messages
        case .unread: conversation.messages.last(where: { $0.role == .assistant }).map { [$0] } ?? []
        }
    }

    init(conversation: ConversationSession, defaults: UserDefaults = .standard) {
        self.conversation = conversation
        self.defaults = defaults
        let savedFontSize = (defaults.object(forKey: "fontSize") as? NSNumber)?.doubleValue
        let fontSize = savedFontSize.flatMap { $0.isFinite ? $0 : nil } ?? Self.defaultFontSize
        let initialFontSize = min(Self.fontSizeRange.upperBound, max(Self.fontSizeRange.lowerBound, fontSize))
        storedFontSize = initialFontSize
        userName = defaults.string(forKey: "userName") ?? ""
        showBuddy = defaults.object(forKey: "showBuddy") as? Bool ?? true
        avatar = defaults.data(forKey: "avatarAppearance")
            .flatMap { try? JSONDecoder().decode(AvatarAppearance.self, from: $0) } ?? AvatarAppearance()
        shortcut = defaults.string(forKey: "shortcut")
            .flatMap(ShortcutChoice.init(rawValue:)) ?? .default
        let initialEditorHeight = DraftEditor.singleLineHeight(fontSize: initialFontSize)
        editorHeight = initialEditorHeight
        displayedEditorHeight = initialEditorHeight
        displayedComposerHeight = initialEditorHeight
        displayedComposerHeight = composerHeight
        contentHeight = displayedComposerHeight + 28
        expandedSize.height = contentHeight
    }

    @discardableResult
    func changeShortcut(
        to choice: ShortcutChoice,
        register: (ShortcutChoice) throws -> Void
    ) -> Bool {
        do {
            try register(choice)
            shortcut = choice
            shortcutError = nil
            return true
        } catch {
            shortcutError = error.localizedDescription
            return false
        }
    }

    func openPanel(resuming: Bool = false) {
        if !isExpanded, !resuming {
            let presentation: ConversationPresentation = conversation.hasUnreadReply ? .unread : .capture
            if presentation != conversationPresentation { naturalTranscriptHeight = 0 }
            conversationPresentation = presentation
        }
        isExpanded = true
    }

    func closePanel() {
        isExpanded = false
        transcriptFocusRequest = 0
    }

    func markReplyViewed(_ id: UUID) {
        guard isExpanded, conversationPresentation != .capture,
              presentedMessages.last(where: { $0.role == .assistant })?.id == id else { return }
        conversation.markReplyViewed(id)
    }

    @discardableResult
    func submitDraft() -> Bool {
        guard conversation.submitDraft() else { return false }
        if conversationPresentation != .thread { naturalTranscriptHeight = 0 }
        conversationPresentation = .thread
        editorHeight = DraftEditor.singleLineHeight(fontSize: fontSize)
        return true
    }

    func resetConversation() {
        conversation.reset()
        conversationPresentation = .capture
        naturalTranscriptHeight = 0
        transcriptFocusRequest = 0
        focusComposer()
    }

    func focusConversation() {
        guard isExpanded, !presentedMessages.isEmpty else { return }
        transcriptFocusRequest &+= 1
    }

    func focusComposer() {
        guard isExpanded else { return }
        transcriptFocusRequest = 0
        focusRequest &+= 1
    }
}
