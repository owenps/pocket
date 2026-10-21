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
    @ObservationIgnored private let openSettings: (() -> Void)?

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
    var displayedCommandHeight: CGFloat = 0
    private var commandSelection: (draft: String, command: ConversationCommand)?
    private var dismissedCommandDraft: String?

    var composerHeight: CGFloat {
        max(editorHeight, showBuddy ? avatar.size.points : 0)
    }

    var commandSuggestions: [ConversationCommand]? {
        guard dismissedCommandDraft != conversation.draft,
              let suggestions = ConversationCommand.suggestions(for: conversation.draft),
              !suggestions.isEmpty else { return nil }
        return suggestions
    }

    var selectedCommand: ConversationCommand? {
        guard let suggestions = commandSuggestions else { return nil }
        if let commandSelection, commandSelection.draft == conversation.draft,
           suggestions.contains(commandSelection.command) {
            return commandSelection.command
        }
        return suggestions.first
    }

    var commandRowHeight: CGFloat {
        DraftEditor.singleLineHeight(fontSize: fontSize) + 6
    }

    var commandHeight: CGFloat {
        guard let commandSuggestions else { return 0 }
        return CGFloat(commandSuggestions.count) * commandRowHeight + 6
    }

    var topContentHeight: CGFloat {
        presentedMessages.isEmpty ? 0 : naturalTranscriptHeight
    }

    func updateDraft(_ text: String) {
        guard conversation.draft != text else { return }
        commandSelection = nil
        dismissedCommandDraft = nil
        conversation.draft = text
    }

    @discardableResult
    func moveCommandSelection(by offset: Int) -> Bool {
        guard let suggestions = commandSuggestions, let selectedCommand,
              let index = suggestions.firstIndex(of: selectedCommand) else { return false }
        let next = (index + offset % suggestions.count + suggestions.count) % suggestions.count
        commandSelection = (conversation.draft, suggestions[next])
        return true
    }

    @discardableResult
    func dismissCommands() -> Bool {
        guard commandSuggestions != nil else { return false }
        dismissedCommandDraft = conversation.draft
        commandSelection = nil
        return true
    }

    var naturalTranscriptHeight: CGFloat = 0
    var transcriptGap: CGFloat = 0
    var contentHeight: CGFloat = 0
    var expandedSize = CGSize(width: IslandGeometry.preferredExpandedWidth, height: 0)
    var collapsedSize = CGSize(width: 96, height: 24)
    var notchHeight: CGFloat = 0
    var transcriptHeight: CGFloat = 0
    var transcriptFocusRequest = 0
    private(set) var conversationPresentation: ConversationPresentation = .capture

    var bodyLayout: IslandGeometry.BodyLayout {
        IslandGeometry.bodyLayout(
            sample: IslandLayout(size: surfaceRect.size, composerHeight: displayedComposerHeight,
                                 editorHeight: displayedEditorHeight, transcriptHeight: transcriptHeight,
                                 transcriptGap: transcriptGap, commandHeight: displayedCommandHeight),
            notchHeight: notchHeight, includesError: shortcutError != nil
        )
    }

    var presentedMessages: [ConversationMessage] {
        switch conversationPresentation {
        case .capture: []
        case .thread: conversation.messages
        case .unread: conversation.messages.last(where: { $0.role == .assistant }).map { [$0] } ?? []
        }
    }

    init(
        conversation: ConversationSession, defaults: UserDefaults = .standard,
        openSettings: (() -> Void)? = nil
    ) {
        self.conversation = conversation
        self.defaults = defaults
        self.openSettings = openSettings
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
        contentHeight = bodyLayout.height
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
        commandSelection = nil
        dismissedCommandDraft = nil
    }

    func markReplyViewed(_ id: UUID) {
        guard isExpanded, conversationPresentation != .capture,
              presentedMessages.last(where: { $0.role == .assistant })?.id == id else { return }
        conversation.markReplyViewed(id)
    }

    @discardableResult
    func submitDraft() -> Bool {
        let command = selectedCommand
            ?? ConversationCommand(rawValue: conversation.draft.trimmingCharacters(in: .whitespacesAndNewlines))
        if command == .settings {
            guard openSettings != nil else { return false }
            conversation.draft = ""
        } else {
            if let command { conversation.draft = command.rawValue }
            guard conversation.submitDraft() else { return false }
        }
        switch command {
        case .new:
            resetPresentation()
        case .stop, .settings:
            break
        case nil:
            if conversationPresentation != .thread { naturalTranscriptHeight = 0 }
            conversationPresentation = .thread
        }
        commandSelection = nil
        dismissedCommandDraft = nil
        editorHeight = DraftEditor.singleLineHeight(fontSize: fontSize)
        if command == .settings { openSettings?() }
        return true
    }

    func resetConversation() {
        conversation.reset()
        resetPresentation()
    }

    private func resetPresentation() {
        conversationPresentation = .capture
        naturalTranscriptHeight = 0
        transcriptFocusRequest = 0
        commandSelection = nil
        dismissedCommandDraft = nil
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
