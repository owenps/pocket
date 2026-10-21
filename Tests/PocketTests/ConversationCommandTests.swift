import Foundation
import PocketTestSupport
import Testing
@testable import Pocket

@MainActor
struct ConversationCommandTests {
    @Test func suggestionsMatchTrimmedPrefixesOnly() {
        for draft in ["", " \t\n ", "Hello", "Use /new", "hello /stop"] {
            #expect(ConversationCommand.suggestions(for: draft) == nil)
        }
        #expect(ConversationCommand.suggestions(for: " / \n") == [.new, .stop])
        #expect(ConversationCommand.suggestions(for: "\n/n\t") == [.new])
        #expect(ConversationCommand.suggestions(for: "/new") == [.new])
        #expect(ConversationCommand.suggestions(for: "/s") == [.stop])
        #expect(ConversationCommand.suggestions(for: " /stop ") == [.stop])
        for draft in ["/clear", "/help", "/NEW", "/new now", "/stop now"] {
            #expect(ConversationCommand.suggestions(for: draft) == [])
        }
    }

    @Test func newCancelsClearsAndStartsWithFreshHistoryDespiteStaleEvents() async throws {
        try await withConversationFixture { session, backend, defaults in
            session.draft = "Old question"
            #expect(session.submitDraft())
            let oldRun = try await backend.waitForRun(at: 0)
            oldRun.emit("Old partial")
            session.draft = " \n/new\t "
            #expect(session.submitDraft())
            #expect(session.messages.isEmpty)
            #expect(session.replyPhase == .idle)
            #expect(session.unreadReplyID == nil)
            #expect(session.draft.isEmpty)
            #expect(defaults.string(forKey: "draft") == "")
            #expect(backend.runCount == 1)

            oldRun.emit("Stale before new turn")
            #expect(session.messages.isEmpty)
            #expect(!session.hasUnreadReply)
            session.draft = "Fresh question"
            #expect(session.submitDraft())
            let newRun = try await backend.waitForRun(at: 1)
            #expect(newRun.history == [session.messages[0]])
            #expect(newRun.history.map(\.text) == ["Fresh question"])
            let freshMessages = session.messages
            oldRun.emit("Stale during new turn")
            oldRun.finish(.failure(CancellationError()))
            try await AsyncTestSupport.wait { oldRun.didReturn }
            #expect(oldRun.wasCancelled)
            #expect(session.messages == freshMessages)
            #expect(session.replyPhase == .working)
            #expect(!session.hasUnreadReply)

            newRun.emit("Fresh answer")
            newRun.finish()
            try await AsyncTestSupport.wait { !session.isBusy }
            #expect(session.messages.last?.outcome == .completed)
            #expect(session.hasUnreadReply)
            session.draft = "/new"
            #expect(session.submitDraft())
            #expect(session.messages.isEmpty)
            #expect(!session.hasUnreadReply)
            #expect(session.draft.isEmpty)
            #expect(defaults.string(forKey: "draft") == "")
            #expect(backend.runCount == 2)
        }
    }

    @Test(arguments: [false, true])
    func stopWhileBusyRetainsHistoryAndRejectsStaleEvents(streaming: Bool) async throws {
        try await withConversationFixture { session, backend, defaults in
            session.draft = "Question"
            #expect(session.submitDraft())
            let oldRun = try await backend.waitForRun(at: 0)
            if streaming { oldRun.emit("Partial answer") }
            let ids = session.messages.map(\.id)
            let texts = session.messages.map(\.text)
            session.draft = " \t/stop\n"
            #expect(session.submitDraft())
            #expect(session.replyPhase == .idle)
            #expect(session.messages.map(\.id) == ids)
            #expect(session.messages.map(\.text) == texts)
            #expect(session.messages.last?.outcome == .stopped)
            #expect(session.unreadReplyID == ids.last)
            #expect(session.draft.isEmpty)
            #expect(defaults.string(forKey: "draft") == "")
            #expect(backend.runCount == 1)

            let stopped = session.messages
            session.draft = "Follow-up"
            #expect(session.submitDraft())
            let newRun = try await backend.waitForRun(at: 1)
            #expect(newRun.history == stopped + [session.messages[2]])
            #expect(newRun.history.last?.text == "Follow-up")
            let working = session.messages
            let unreadID = session.unreadReplyID
            oldRun.emit("Stale answer")
            oldRun.finish()
            try await AsyncTestSupport.wait { oldRun.didReturn }
            #expect(oldRun.wasCancelled)
            #expect(session.messages == working)
            #expect(session.replyPhase == .working)
            #expect(session.unreadReplyID == unreadID)
        }
    }

    @Test func stopWhileIdleConsumesDraftWithoutChangingHistoryOrUnread() async throws {
        try await withConversationFixture { session, backend, defaults in
            session.draft = "/stop"
            #expect(session.submitDraft())
            #expect(session.messages.isEmpty)
            #expect(!session.hasUnreadReply)
            #expect(session.draft.isEmpty)
            #expect(defaults.string(forKey: "draft") == "")
            #expect(backend.runCount == 0)

            session.draft = "Question"
            #expect(session.submitDraft())
            let run = try await backend.waitForRun(at: 0)
            run.emit("Answer")
            run.finish()
            try await AsyncTestSupport.wait { !session.isBusy }
            let history = session.messages
            let unreadID = session.unreadReplyID
            session.draft = "/stop"
            #expect(session.submitDraft())
            #expect(session.messages == history)
            #expect(session.unreadReplyID == unreadID)
            #expect(session.replyPhase == .idle)
            #expect(session.draft.isEmpty)
            #expect(defaults.string(forKey: "draft") == "")
            #expect(backend.runCount == 1)
        }
    }

    @Test(arguments: [false, true])
    func unsupportedSlashDraftsAreRejectedUnchanged(busy: Bool) async throws {
        try await withConversationFixture { session, backend, defaults in
            session.draft = "Question"
            #expect(session.submitDraft())
            let run = try await backend.waitForRun(at: 0)
            run.emit("Answer")
            if !busy {
                run.finish()
                try await AsyncTestSupport.wait { !session.isBusy }
            }
            let history = session.messages
            let unreadID = session.unreadReplyID
            let phase = session.replyPhase
            for draft in ["/clear", " /help\n", "/", "/n", "/NEW", "/new now", "/stop now", "/new\n/stop"] {
                session.draft = draft
                #expect(!session.submitDraft())
                #expect(session.draft == draft)
                #expect(defaults.string(forKey: "draft") == draft)
                #expect(session.messages == history)
                #expect(session.unreadReplyID == unreadID)
                #expect(session.replyPhase == phase)
                #expect(backend.runCount == 1)
            }
        }
    }

    @Test func panelNewReturnsToCaptureAndFocusesComposer() async throws {
        try await withConversationFixture { session, _, defaults in
            let state = PanelState(conversation: session, defaults: defaults)
            state.openPanel()
            session.draft = "Question"
            #expect(state.submitDraft())
            state.focusConversation()
            try #require(state.transcriptFocusRequest > 0)
            state.naturalTranscriptHeight = 240
            state.editorHeight = 140
            let focusRequest = state.focusRequest
            session.draft = " \n/new "
            #expect(state.submitDraft())
            #expect(state.conversationPresentation == .capture)
            #expect(state.presentedMessages.isEmpty)
            #expect(state.naturalTranscriptHeight == 0)
            #expect(state.topContentHeight == 0)
            #expect(state.transcriptFocusRequest == 0)
            #expect(state.focusRequest == focusRequest + 1)
            #expect(state.editorHeight == DraftEditor.singleLineHeight(fontSize: state.fontSize))
        }
    }

    @Test(arguments: [ConversationPresentation.capture, .unread, .thread])
    func panelStopPreservesPresentationAndOrdinaryTextRevealsThread(presentation: ConversationPresentation) async throws {
        try await withConversationFixture { session, backend, defaults in
            let state = PanelState(conversation: session, defaults: defaults)
            state.openPanel()
            session.draft = "Question"
            #expect(state.submitDraft())
            let run = try await backend.waitForRun(at: 0)
            run.emit("Answer")
            run.finish()
            try await AsyncTestSupport.wait { !session.isBusy }
            if presentation != .thread {
                if presentation == .capture {
                    state.markReplyViewed(try #require(session.messages.last?.id))
                }
                state.closePanel()
                state.openPanel()
            }
            try #require(state.conversationPresentation == presentation)
            state.naturalTranscriptHeight = 240
            state.focusConversation()
            let presented = state.presentedMessages
            let focus = state.focusRequest
            let transcriptFocus = state.transcriptFocusRequest
            let unreadID = session.unreadReplyID
            session.draft = "/stop"
            #expect(state.submitDraft())
            #expect(state.conversationPresentation == presentation)
            #expect(state.presentedMessages == presented)
            #expect(state.naturalTranscriptHeight == 240)
            #expect(state.focusRequest == focus)
            #expect(state.transcriptFocusRequest == transcriptFocus)
            #expect(session.unreadReplyID == unreadID)
            #expect(backend.runCount == 1)

            session.draft = "Follow-up"
            #expect(state.submitDraft())
            #expect(state.conversationPresentation == .thread)
            #expect(state.presentedMessages == session.messages)
            #expect(state.naturalTranscriptHeight == (presentation == .thread ? 240 : 0))
        }
    }

    @Test func selectionWrapsFiltersAndResetsOnEditingOrReopening() async throws {
        try await withConversationFixture { session, _, defaults in
            let state = PanelState(conversation: session, defaults: defaults)
            state.openPanel()
            state.updateDraft("/")
            #expect(state.selectedCommand == .new)
            #expect(state.moveCommandSelection(by: 1))
            #expect(state.selectedCommand == .stop)
            #expect(state.moveCommandSelection(by: 1))
            #expect(state.selectedCommand == .new)
            #expect(state.moveCommandSelection(by: -1))
            #expect(state.selectedCommand == .stop)
            state.updateDraft("/n")
            #expect(state.selectedCommand == .new)
            #expect(state.moveCommandSelection(by: -1))
            #expect(state.selectedCommand == .new)
            #expect(state.dismissCommands())
            #expect(state.commandSuggestions == nil)
            #expect(state.commandHeight == 0)
            #expect(!state.moveCommandSelection(by: 1))
            #expect(!state.dismissCommands())
            #expect(session.draft == "/n")
            state.updateDraft("/")
            state.updateDraft("/n")
            #expect(state.selectedCommand == .new)
            #expect(state.dismissCommands())
            state.closePanel()
            state.openPanel()
            #expect(state.selectedCommand == .new)
        }
    }

    @Test func returnRunsSelectedCompletionWithoutSendingTheSlashPrefix() async throws {
        try await withConversationFixture { session, backend, defaults in
            let state = PanelState(conversation: session, defaults: defaults)
            state.openPanel()
            session.draft = "Question"
            #expect(state.submitDraft())
            let run = try await backend.waitForRun(at: 0)
            run.emit("Partial answer")
            let texts = session.messages.map(\.text)
            state.updateDraft("/")
            #expect(state.moveCommandSelection(by: 1))
            #expect(state.submitDraft())
            #expect(!session.isBusy)
            #expect(session.messages.map(\.text) == texts)
            #expect(session.messages.last?.isStopped == true)
            #expect(session.draft.isEmpty)
            #expect(backend.runCount == 1)
            state.updateDraft("/n")
            #expect(state.submitDraft())
            #expect(session.messages.isEmpty)
            #expect(state.conversationPresentation == .capture)
            #expect(state.commandHeight == 0)
        }
    }

    @Test func suggestionsKeepConversationVisibleAndReadable() async throws {
        try await withConversationFixture { session, backend, defaults in
            let state = PanelState(conversation: session, defaults: defaults)
            state.openPanel()
            session.draft = "Question"
            #expect(state.submitDraft())
            let run = try await backend.waitForRun(at: 0)
            run.emit("Answer")
            run.finish()
            try await AsyncTestSupport.wait { !session.isBusy }
            let replyID = try #require(session.unreadReplyID)
            state.naturalTranscriptHeight = 240
            #expect(state.topContentHeight == 240)
            let messages = state.presentedMessages
            for (draft, suggestions) in [("/", [ConversationCommand.new, .stop]), ("/n", [.new])] {
                state.updateDraft(draft)
                #expect(state.commandSuggestions == suggestions)
                #expect(state.commandHeight == CGFloat(suggestions.count) * state.commandRowHeight + 6)
                #expect(state.topContentHeight == 240)
                #expect(state.presentedMessages == messages)
            }
            state.focusConversation()
            state.markReplyViewed(replyID)
            #expect(state.transcriptFocusRequest == 1)
            #expect(!session.hasUnreadReply)
            for draft in ["/help", "/clear", "/unknown", "Ordinary text"] {
                state.updateDraft(draft)
                #expect(state.commandSuggestions == nil)
                #expect(state.commandHeight == 0)
                #expect(state.topContentHeight == 240)
            }
        }
    }
}
