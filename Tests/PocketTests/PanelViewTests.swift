import AppKit
import PocketTestSupport
import SwiftUI
import Testing
@testable import Pocket

@MainActor
struct PanelViewTests {
    @Test func submittingFromUnreadPreviewKeepsComposerReadyForNextDraft() async throws {
        try await withPanel { state, window, host in
            state.conversation.draft = "Earlier question"
            #expect(state.submitDraft())
            state.conversation.stopReply()
            state.openPanel()
            try #require(state.conversationPresentation == .unread)
            try await waitForLayout(host) { window.firstResponder is NSTextView }
            let editor = try #require(window.firstResponder as? NSTextView)

            try press(48, in: window)
            try await waitForLayout(host) { window.firstResponder !== editor }
            try #require((window.firstResponder as? NSTextView)?.isEditable == false)
            try press(36, in: window)
            try await waitForLayout(host) { window.firstResponder === editor }

            editor.insertText("Follow-up", replacementRange: editor.selectedRange())
            try press(36, in: window)
            try await waitForLayout(host) { editor.string.isEmpty }
            #expect(state.conversation.messages.filter { $0.role == .user }.map(\.text) == ["Earlier question", "Follow-up"])
            #expect(window.firstResponder === editor)

            let focusedEditor = try #require(window.firstResponder as? NSTextView)
            focusedEditor.insertText("Next thought", replacementRange: focusedEditor.selectedRange())
            #expect(state.conversation.draft == "Next thought")
        }
    }

    @Test func acceptedSendShowsTranscriptAboveComposerAndStartsANewUndoHistory() async throws {
        try await withPanel { state, window, host in
            state.openPanel()
            try await waitForLayout(host) { window.firstResponder is NSTextView }
            let editor = try #require(window.firstResponder as? NSTextView)
            let undo = try #require(editor.undoManager)
            let groupsByEvent = undo.groupsByEvent
            undo.groupsByEvent = false
            defer { undo.groupsByEvent = groupsByEvent }
            let input = "Keep this message in the conversation"
            undo.beginUndoGrouping()
            editor.insertText(input, replacementRange: editor.selectedRange())
            editor.breakUndoCoalescing()
            undo.endUndoGrouping()
            #expect(state.conversation.draft == input)
            try press(36, in: window)
            try await waitForLayout(host) {
                textViews(in: host).contains { !$0.isEditable && $0.string.contains("Keep this message") }
            }
            let transcript = try #require(textViews(in: host).first {
                !$0.isEditable && $0.string.contains("Keep this message")
            })
            let historyViewport = try #require(transcript.enclosingScrollView)
            let composerViewport = try #require(editor.enclosingScrollView)
            let historyFrame = historyViewport.convert(historyViewport.bounds, to: nil)
            let composerFrame = composerViewport.convert(composerViewport.bounds, to: nil)
            #expect(historyFrame.minY >= composerFrame.maxY)
            #expect(window.firstResponder === editor)
            #expect(state.conversation.messages.filter { $0.role == .user }.map(\.text) == [input])
            #expect(editor.string.isEmpty)
            #expect(state.conversation.draft.isEmpty)
            #expect(!undo.canUndo)
            #expect(!undo.canRedo)

            undo.beginUndoGrouping()
            editor.insertText("New draft", replacementRange: editor.selectedRange())
            editor.breakUndoCoalescing()
            undo.endUndoGrouping()
            undo.undo()
            #expect(editor.string.isEmpty)
            #expect(state.conversation.draft.isEmpty)
            #expect(!undo.canUndo)
        }
    }

    @Test func livePreferencesPreserveDraftEditingAndReading() async throws {
        try await withPanel { state, window, host in
            state.conversation.draft = "Earlier question"
            #expect(state.submitDraft())
            state.conversation.stopReply()
            let draft = "Keep this draft"
            state.conversation.draft = draft
            state.buddyEntranceProgress = 0
            state.avatar.size = .small
            state.openPanel(resuming: true)
            try await waitForLayout(host) { window.firstResponder is NSTextView }
            let editor = try #require(window.firstResponder as? NSTextView)
            let transcript = try #require(textViews(in: host).first { !$0.isEditable })
            let viewport = try #require(editor.enclosingScrollView)
            let undo = try #require(editor.undoManager)
            let groupsByEvent = undo.groupsByEvent
            undo.groupsByEvent = false
            defer { undo.groupsByEvent = groupsByEvent }
            editor.setSelectedRange(NSRange(location: draft.utf16.count, length: 0))
            undo.beginUndoGrouping()
            editor.insertText(" safely", replacementRange: editor.selectedRange())
            editor.breakUndoCoalescing()
            undo.endUndoGrouping()
            let editedDraft = draft + " safely"
            let selection = NSRange(location: 5, length: 4)
            editor.setSelectedRange(selection)
            let initialFrame = viewport.convert(viewport.bounds, to: host)

            @MainActor func expectEditingContinuity() {
                #expect(textViews(in: host).contains { $0 === editor })
                #expect(window.firstResponder === editor)
                #expect(editor.string == editedDraft)
                #expect(state.conversation.draft == editedDraft)
                #expect(editor.selectedRange() == selection)
                #expect(undo.canUndo)
            }

            state.avatar.palette = .lilac
            state.avatar.headwear = .sprout
            state.avatar.face = .mellow
            state.avatar.size = .large
            let expectedWidth = initialFrame.width - (AvatarAppearance.Size.large.points - AvatarAppearance.Size.small.points)
            try await waitForLayout(host) { abs(viewport.bounds.width - expectedWidth) < 0.5 }
            for showBuddy in [false, true] {
                state.showBuddy = showBuddy
                let width = expectedWidth + (showBuddy ? 0 : state.avatar.size.points + 12)
                try await waitForLayout(host) { abs(viewport.bounds.width - width) < 0.5 }
                #expect(abs(viewport.convert(viewport.bounds, to: host).maxX - initialFrame.maxX) < 0.5)
                expectEditingContinuity()
            }

            state.buddyEntranceProgress = 1
            state.fontSize = 24
            try await waitForLayout(host) {
                editor.font?.pointSize == 24
                    && (transcript.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 24
                    && state.editorHeight == min(DraftEditor.maximumHeight, NativeTextTestSupport.height(of: editor))
                    && state.naturalTranscriptHeight == NativeTextTestSupport.height(of: transcript)
            }
            #expect(textViews(in: host).contains { $0 === transcript })
            expectEditingContinuity()
            undo.undo()
            #expect(editor.string == draft)
            #expect(state.conversation.draft == draft)
            undo.redo()
            #expect(editor.string == editedDraft)
            #expect(state.conversation.draft == editedDraft)
        }
    }

    @Test func idleReplyStaysUnreadUntilNativeTranscriptReachesItsEnd() async throws {
        let backend = ControlledAssistantBackend()
        try await withPanel(backend: backend) { state, window, host in
            state.openPanel()
            try await waitForLayout(host) { window.firstResponder is DraftTextView }
            let editor = try #require(window.firstResponder as? DraftTextView)
            editor.insertText("Question", replacementRange: editor.selectedRange())
            try press(36, in: window)
            let run = try await backend.waitForRun(at: 0)
            let answer = Array(repeating: "A reply that needs native scrolling.", count: 40).joined(separator: "\n")
            run.emit(answer)
            try await waitForLayout(host) {
                textViews(in: host).contains { !$0.isEditable && $0.string.contains(answer) }
            }
            let transcript = try #require(textViews(in: host).first { !$0.isEditable })
            let viewport = try #require(transcript.enclosingScrollView)
            #expect(state.conversation.hasUnreadReply) // Visible streaming text is not a receipt.
            transcript.moveToBeginningOfDocument(nil)
            run.finish()
            try await waitForLayout(host) {
                state.conversation.replyPhase == .idle && run.didReturn
            }
            #expect(state.conversation.messages.last?.outcome == .completed)
            #expect(viewport.contentView.bounds.maxY < transcript.frame.maxY - 2)
            #expect(state.conversation.hasUnreadReply)

            transcript.moveToEndOfDocument(nil)
            try await waitForLayout(host) { !state.conversation.hasUnreadReply }
        }
    }

    @Test(arguments: ["hidden", "background", "occluded", "partial final line"])
    func hostedReceiptWaitsForVisibleForegroundAndEntireFinalLine(blockedBy: String) async throws {
        let backend = ControlledAssistantBackend()
        try await withPanel(backend: backend) { state, window, host in
            state.openPanel()
            try await waitForLayout(host) { window.firstResponder is DraftTextView }
            let editor = try #require(window.firstResponder as? DraftTextView)
            window.shown = blockedBy != "hidden"
            window.key = blockedBy != "background"
            window.exposed = blockedBy != "occluded"
            editor.insertText("Question", replacementRange: editor.selectedRange())
            try press(36, in: window)
            let run = try await backend.waitForRun(at: 0)
            run.emit("An answer\nFinal line")
            try await waitForLayout(host) {
                textViews(in: host).contains { !$0.isEditable && $0.string.contains("Final line") }
            }
            let transcript = try #require(textViews(in: host).first { !$0.isEditable })
            let viewport = try #require(transcript.enclosingScrollView)
            if blockedBy == "partial final line" {
                let manager = try #require(transcript.layoutManager)
                let line = manager.lineFragmentRect(forGlyphAt: manager.numberOfGlyphs - 1, effectiveRange: nil)
                let partialHeight = ceil(line.height / 2) + transcript.textContainerInset.height
                state.transcriptHeight = partialHeight
                try await waitForLayout(host) { abs(viewport.bounds.height - partialHeight) < 0.5 }
            }
            run.finish()
            transcript.moveToEndOfDocument(nil)
            try await waitForLayout(host) { state.conversation.replyPhase == .idle && run.didReturn }
            #expect(state.conversation.messages.last?.outcome == .completed)
            #expect(viewport.contentView.bounds.maxY >= transcript.frame.maxY - 2)
            #expect(state.conversation.hasUnreadReply)

            switch blockedBy {
            case "background":
                window.key = true
                NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
            case "occluded":
                window.exposed = true
                NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
            case "hidden":
                window.shown = true
                NotificationCenter.default.post(name: NSWindow.didExposeNotification, object: window)
            default:
                state.transcriptHeight = 112
            }
            try await waitForLayout(host) { !state.conversation.hasUnreadReply }
        }
    }

    @Test(arguments: [11.0, 24.0])
    func compactComposerCentersInputAndGrowsBeyondTheBuddy(fontSize: Double) async throws {
        try await withPanel { state, window, host in
            state.transcriptHeight = 0
            state.transcriptGap = 0
            state.contentHeight = state.composerHeight + 28
            state.fontSize = fontSize
            state.openPanel()
            try await waitForLayout(host) { window.firstResponder is DraftTextView }
            let editor = try #require(window.firstResponder as? DraftTextView)
            let viewport = try #require(editor.enclosingScrollView as? DraftEditorScrollView)
            let lineHeight = DraftEditor.singleLineHeight(fontSize: fontSize)

            for size in AvatarAppearance.Size.allCases {
                state.avatar.size = size
                for showBuddy in [true, false] {
                    state.showBuddy = showBuddy
                    let rowHeight = max(lineHeight, showBuddy ? size.points : 0)
                    try await waitForLayout(host) {
                        abs(state.displayedComposerHeight - rowHeight) < 0.5
                            && abs(viewport.frame.height - lineHeight) < 0.5
                    }
                    #expect(state.composerHeight == rowHeight)
                    #expect(state.contentHeight == rowHeight + 28)
                    let frame = viewport.convert(viewport.bounds, to: host)
                    let centerFromTop = 12 + rowHeight / 2
                    let center = host.isFlipped ? centerFromTop : host.bounds.height - centerFromTop
                    #expect(abs(frame.midY - center) < 0.5)
                }
            }

            state.showBuddy = true
            state.avatar.size = .large
            state.conversation.draft = Array(repeating: "Another line", count: 30).joined(separator: "\n")
            try await waitForLayout(host) {
                viewport.frame.height == DraftEditor.maximumHeight
                    && state.displayedComposerHeight == DraftEditor.maximumHeight
            }
            #expect(state.composerHeight == DraftEditor.maximumHeight)
            #expect(viewport.measuredContentHeight ?? 0 > DraftEditor.maximumHeight)
            #expect(window.firstResponder === editor)

            state.conversation.draft = ""
            try await waitForLayout(host) {
                viewport.frame.height == lineHeight
                    && state.displayedComposerHeight == AvatarAppearance.Size.large.points
            }
            #expect(window.firstResponder === editor)
        }
    }

    private func textViews(in view: NSView) -> [NSTextView] {
        (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap { textViews(in: $0) }
    }

    private func withPanel(
        backend: ControlledAssistantBackend? = nil,
        _ body: @MainActor (PanelState, OffscreenTestWindow, NSView) async throws -> Void
    ) async throws {
        try await withConversationFixture(backend: backend ?? ControlledAssistantBackend()) { conversation, _, defaults in
            let state = PanelState(conversation: conversation, defaults: defaults)
            state.expandedSize = CGSize(width: 460, height: 210)
            state.surfaceRect = CGRect(origin: .zero, size: state.expandedSize)
            state.transcriptHeight = 112
            state.transcriptGap = 10
            state.contentHeight = state.expandedSize.height
            state.expansionProgress = 1
            let fixture = OffscreenHost(PanelTestContent(state: state), size: state.expandedSize)
            defer { fixture.close() }
            try await body(state, fixture.window, fixture.view)
        }
    }

    private func press(_ keyCode: UInt16, in window: NSWindow) throws {
        let responder = try #require(window.firstResponder as? NSTextView)
        responder.keyDown(with: NativeTextTestSupport.keyEvent(code: keyCode))
    }

    private func waitForLayout(_ host: NSView, until condition: () -> Bool) async throws {
        try await AsyncTestSupport.wait {
            host.layoutSubtreeIfNeeded()
            return condition()
        }
    }
}

private struct PanelTestContent: View {
    @Bindable var state: PanelState

    var body: some View {
        PanelView(
            state: state, expand: { state.openPanel() }, collapse: { state.closePanel() },
            editorHeightChanged: { state.editorHeight = $0 }, submit: { state.submitDraft() },
            transcriptHeightChanged: { state.naturalTranscriptHeight = $0 }
        )
        .onChange(of: [state.editorHeight, state.composerHeight], initial: true) {
            // Apply final allocations without running the spring/window controller.
            state.displayedEditorHeight = state.editorHeight
            state.displayedComposerHeight = state.composerHeight
            state.contentHeight = state.bodyLayout.height
        }
    }
}
