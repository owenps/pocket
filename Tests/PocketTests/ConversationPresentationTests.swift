import Foundation
import PocketTestSupport
import Testing
@testable import Pocket

@MainActor
struct ConversationPresentationTests {
    @Test func freshOpenIsCaptureWithoutFocusRequests() async throws {
        try await withConversationFixture { session, _, defaults in
            let state = PanelState(conversation: session, defaults: defaults)
            #expect(state.conversationPresentation == .capture)
            #expect(state.presentedMessages.isEmpty)
            #expect(!state.conversation.hasUnreadReply)
            #expect(state.conversation.unreadReplyID == nil)
            #expect(state.collapsedSize == CGSize(width: 96, height: 24))
            state.openPanel()
            state.focusConversation()
            #expect(state.isExpanded)
            #expect(state.conversationPresentation == .capture)
            #expect(state.focusRequest == 0)
            #expect(state.transcriptFocusRequest == 0)
        }
    }

    @Test func panelStartsCollapsedAndOpeningAndClosingPreserveUnsentDraft() async throws {
        try await withConversationFixture { session, _, defaults in
            let state = PanelState(conversation: session, defaults: defaults)
            #expect(!state.isExpanded)
            state.conversation.draft = "Keep this thought"
            state.openPanel()
            state.closePanel()
            #expect(state.conversation.draft == "Keep this thought")
        }
    }

    @Test func acknowledgedHistoryStaysHiddenUntilANewSubmission() async throws {
        try await withConversationFixture { session, _, defaults in
            let state = PanelState(conversation: session, defaults: defaults)
            state.openPanel()
            state.conversation.draft = "First question"
            #expect(state.submitDraft())
            state.conversation.stopReply()
            let reply = try #require(state.conversation.messages.last)
            state.markReplyViewed(reply.id)
            let history = state.conversation.messages
            #expect(!state.conversation.hasUnreadReply)
            #expect(state.presentedMessages == history)
            state.closePanel()
            #expect(state.conversationPresentation == .thread)
            #expect(state.presentedMessages == history)
            state.openPanel()
            #expect(state.conversationPresentation == .capture)
            #expect(state.presentedMessages.isEmpty)
            state.focusConversation()
            #expect(state.transcriptFocusRequest == 0)
            state.editorHeight = 140
            state.conversation.draft = "  "
            #expect(!state.submitDraft())
            #expect(state.conversationPresentation == .capture)
            #expect(state.editorHeight == 140)
            state.conversation.draft = "Follow-up"
            #expect(state.submitDraft())
            #expect(state.editorHeight == DraftEditor.minimumHeight)
            #expect(state.conversationPresentation == .thread)
            #expect(state.presentedMessages == state.conversation.messages)
            #expect(Array(state.conversation.messages.prefix(history.count)) == history)
            state.focusConversation()
            #expect(state.transcriptFocusRequest == 1)
        }
    }

    @Test func completedHiddenReplyPreviewsOnlyLastAssistantAndStaysAfterReceipt() async throws {
        try await withConversationFixture { session, backend, defaults in
            let state = PanelState(conversation: session, defaults: defaults)
            state.openPanel()
            state.conversation.draft = "First"
            #expect(state.submitDraft())
            try await completeReply(state.conversation, backend, at: 0, text: "First answer")
            state.markReplyViewed(try #require(state.conversation.messages.last?.id))
            state.conversation.draft = "Second"
            #expect(state.submitDraft())
            state.closePanel()
            try await completeReply(state.conversation, backend, at: 1, text: "Second answer")
            let reply = try #require(state.conversation.messages.last)
            #expect(reply.text == "Second answer")
            #expect(state.conversation.hasUnreadReply)
            #expect(state.conversation.unreadReplyID == reply.id)
            #expect(!state.isExpanded)
            #expect(state.focusRequest == 0)
            #expect(state.transcriptFocusRequest == 0)
            state.openPanel()
            #expect(state.conversationPresentation == .unread)
            #expect(state.presentedMessages == [reply])
            #expect(state.conversation.hasUnreadReply)
            state.markReplyViewed(reply.id)
            #expect(!state.conversation.hasUnreadReply)
            #expect(state.presentedMessages == [reply])
            state.openPanel()
            #expect(state.conversationPresentation == .unread)
            state.closePanel()
            #expect(state.presentedMessages == [reply])
            state.openPanel()
            #expect(state.conversationPresentation == .capture)
            #expect(state.presentedMessages.isEmpty)
            #expect(state.conversation.messages.count == 4)
        }
    }

    @Test func receiptsRejectHiddenWorkingStreamingAndWrongReplies() async throws {
        try await withConversationFixture { session, backend, defaults in
            let state = PanelState(conversation: session, defaults: defaults)
            state.openPanel()
            state.conversation.draft = "First"
            #expect(state.submitDraft())
            try await completeReply(state.conversation, backend, at: 0, text: "First answer")
            let oldID = try #require(state.conversation.unreadReplyID)
            state.closePanel()
            state.markReplyViewed(oldID)
            #expect(state.conversation.unreadReplyID == oldID)
            state.openPanel()
            state.markReplyViewed(UUID())
            #expect(state.conversation.unreadReplyID == oldID)
            state.conversation.draft = "Second"
            #expect(state.submitDraft())
            let currentID = try #require(state.conversation.messages.last?.id)
            state.markReplyViewed(oldID)
            state.markReplyViewed(currentID)
            #expect(state.conversation.unreadReplyID == oldID)
            let run = try await backend.waitForRun(at: 1)
            run.emit("Partial answer")
            #expect(state.conversation.replyPhase == .streaming)
            #expect(state.conversation.unreadReplyID == currentID)
            state.markReplyViewed(currentID)
            #expect(state.conversation.hasUnreadReply)
            state.conversation.stopReply()
            state.markReplyViewed(oldID)
            #expect(state.conversation.unreadReplyID == currentID)
            state.markReplyViewed(currentID)
            #expect(!state.conversation.hasUnreadReply)
        }
    }

    @Test func captureRejectsReceiptEvenAfterBackgroundReplyFinishes() async throws {
        try await withConversationFixture { session, backend, defaults in
            let state = PanelState(conversation: session, defaults: defaults)
            state.openPanel()
            state.conversation.draft = "Background question"
            #expect(state.submitDraft())
            state.closePanel()
            state.openPanel()
            #expect(state.conversationPresentation == .capture)
            try await completeReply(state.conversation, backend, at: 0, text: "Background answer")
            let id = try #require(state.conversation.unreadReplyID)
            state.markReplyViewed(id)
            #expect(state.conversation.unreadReplyID == id)
            #expect(state.presentedMessages.isEmpty)
            state.focusConversation()
            #expect(state.transcriptFocusRequest == 0)
            state.closePanel()
            state.openPanel()
            #expect(state.conversationPresentation == .unread)
            state.markReplyViewed(id)
            #expect(!state.conversation.hasUnreadReply)
        }
    }

    @Test func closingMidstreamPreservesLayoutAndFutureUnreadWithoutFocusOrExpansion() async throws {
        try await withConversationFixture { session, backend, defaults in
            let state = PanelState(conversation: session, defaults: defaults)
            state.openPanel()
            state.conversation.draft = "Keep going"
            #expect(state.submitDraft())
            let run = try await backend.waitForRun(at: 0)
            run.emit("Partial")
            let partial = try #require(state.conversation.messages.last)
            #expect(partial.text == "Partial")
            #expect(state.conversation.unreadReplyID == partial.id)
            state.expandedSize = CGSize(width: 460, height: 240)
            state.transcriptHeight = 150
            state.closePanel()
            #expect(state.conversationPresentation == .thread)
            #expect(state.presentedMessages == state.conversation.messages)
            #expect(state.expandedSize.height == 240)
            #expect(state.transcriptHeight == 150)
            run.emit(" answer")
            run.finish(.success(()))
            try await AsyncTestSupport.wait { !state.conversation.isBusy }
            #expect(state.conversation.messages.last?.text == "Partial answer")
            #expect(state.conversation.unreadReplyID == partial.id)
            #expect(!state.isExpanded)
            #expect(state.focusRequest == 0)
            #expect(state.transcriptFocusRequest == 0)
        }
    }

    @Test func reversingClosePreservesThreadAndAcknowledgedUnreadPresentation() async throws {
        try await withConversationFixture { session, _, defaults in
            let state = PanelState(conversation: session, defaults: defaults)
            state.openPanel()
            state.conversation.draft = "Question"
            #expect(state.submitDraft())
            state.conversation.stopReply()
            state.closePanel()
            state.openPanel(resuming: true)
            #expect(state.conversationPresentation == .thread)
            state.closePanel()
            state.openPanel()
            #expect(state.conversationPresentation == .unread)
            state.markReplyViewed(try #require(state.conversation.unreadReplyID))
            state.closePanel()
            state.openPanel(resuming: true)
            #expect(state.conversationPresentation == .unread)
            #expect(!state.presentedMessages.isEmpty)
            #expect(!state.conversation.hasUnreadReply)
            #expect(state.focusRequest == 0)
            #expect(state.transcriptFocusRequest == 0)
        }
    }

    @Test func stoppedEmptyReplyCanBePresentedAndAcknowledged() async throws {
        try await withConversationFixture { session, _, defaults in
            let state = PanelState(conversation: session, defaults: defaults)
            state.conversation.draft = "Stop before text"
            #expect(state.submitDraft())
            state.conversation.stopReply()
            let reply = try #require(state.conversation.messages.last)
            try #require(reply.text.isEmpty && reply.isStopped)

            state.openPanel()
            #expect(state.conversationPresentation == .unread)
            #expect(state.presentedMessages == [reply])
            state.markReplyViewed(reply.id)
            #expect(!state.conversation.hasUnreadReply)
            #expect(state.presentedMessages == [reply])
        }
    }

    @Test func resetReturnsToCaptureAndFocusesComposer() async throws {
        try await withConversationFixture { session, _, defaults in
            let state = PanelState(conversation: session, defaults: defaults)
            state.openPanel()
            state.conversation.draft = "Discard"
            #expect(state.submitDraft())
            state.conversation.stopReply()
            state.focusConversation()
            state.naturalTranscriptHeight = 100

            state.resetConversation()
            #expect(state.presentedMessages.isEmpty)
            #expect(state.conversationPresentation == .capture)
            #expect(state.naturalTranscriptHeight == 0)
            #expect(state.transcriptFocusRequest == 0)
            #expect(state.focusRequest == 1)
        }
    }

    @Test func recreatingPanelDuringReplyKeepsSessionAliveAndOpensLatestUnread() async throws {
        try await withConversationFixture { session, backend, defaults in
            var state: PanelState? = PanelState(conversation: session, defaults: defaults)
            weak var original = state
            state?.openPanel()
            session.draft = "Keep replying"
            #expect(state?.submitDraft() == true)
            let run = try await backend.waitForRun(at: 0)
            run.emit("Partial")
            state = nil
            #expect(original == nil)
            #expect(session.isBusy)

            let restored = PanelState(conversation: session, defaults: defaults)
            #expect(restored.conversation === session)
            #expect(restored.conversationPresentation == .capture)
            run.emit(" answer after recreation")
            run.finish(.success(()))
            try await AsyncTestSupport.wait { !session.isBusy }
            #expect(!run.wasCancelled)
            let reply = try #require(session.messages.last)
            #expect(reply.text == "Partial answer after recreation")
            #expect(session.unreadReplyID == reply.id)
            #expect(!restored.isExpanded)
            #expect(restored.focusRequest == 0)
            #expect(restored.transcriptFocusRequest == 0)
            restored.openPanel()
            #expect(restored.conversationPresentation == .unread)
            #expect(restored.presentedMessages == [reply])
            restored.markReplyViewed(reply.id)
            #expect(!session.hasUnreadReply)
        }
    }

    private func completeReply(
        _ session: ConversationSession,
        _ backend: ControlledAssistantBackend,
        at index: Int,
        text: String
    ) async throws {
        let run = try await backend.waitForRun(at: index)
        run.emit(text)
        run.finish(.success(()))
        try await AsyncTestSupport.wait { !session.isBusy }
    }
}
