import Foundation
import PocketTestSupport
import Testing
@testable import Pocket

@MainActor
struct SettingsCommandTests {
    @Test(arguments: [false, true])
    func idleOpensSettingsAfterClearingDraftWithoutChangingPresentation(dismissed: Bool) async throws {
        try await withConversationFixture { session, backend, defaults in
            var openings = 0
            let state = PanelState(conversation: session, defaults: defaults, openSettings: {
                openings += 1
                #expect(session.draft.isEmpty)
                #expect(defaults.string(forKey: "draft") == "")
            })
            session.draft = "Question"
            #expect(session.submitDraft())
            let run = try await backend.waitForRun(at: 0)
            run.emit("Answer")
            run.finish()
            try await AsyncTestSupport.wait { !session.isBusy }
            state.openPanel()
            state.focusConversation()
            state.naturalTranscriptHeight = 240
            state.editorHeight = 140
            let history = session.messages
            let unreadID = try #require(session.unreadReplyID)
            let presented = state.presentedMessages
            let focus = state.focusRequest
            let transcriptFocus = state.transcriptFocusRequest
            state.updateDraft(dismissed ? " \n/settings\t" : "/se")
            #expect(ConversationCommand.settings.summary == "open settings")
            #expect(state.selectedCommand == .settings)
            if dismissed {
                #expect(state.dismissCommands())
                #expect(state.selectedCommand == nil)
            }

            #expect(state.submitDraft())
            #expect(openings == 1)
            #expect(session.draft.isEmpty)
            #expect(defaults.string(forKey: "draft") == "")
            #expect(state.selectedCommand == nil)
            #expect(state.commandSuggestions == nil)
            #expect(state.commandHeight == 0)
            #expect(state.editorHeight == DraftEditor.singleLineHeight(fontSize: state.fontSize))
            #expect(session.messages == history)
            #expect(session.unreadReplyID == unreadID)
            #expect(session.replyPhase == .idle)
            #expect(state.isExpanded)
            #expect(state.conversationPresentation == .unread)
            #expect(state.presentedMessages == presented)
            #expect(state.naturalTranscriptHeight == 240)
            #expect(state.focusRequest == focus)
            #expect(state.transcriptFocusRequest == transcriptFocus)
            #expect(backend.runCount == 1)
            #expect(!state.submitDraft())
            #expect(openings == 1)
        }
    }

    @Test(arguments: [false, true])
    func selectedSettingsLeavesWorkingOrStreamingReplyRunning(streaming: Bool) async throws {
        try await withConversationFixture { session, backend, defaults in
            var openings = 0
            let state = PanelState(conversation: session, defaults: defaults, openSettings: {
                openings += 1
                #expect(session.draft.isEmpty)
                #expect(defaults.string(forKey: "draft") == "")
            })
            state.openPanel()
            state.updateDraft("Question")
            #expect(state.submitDraft())
            let run = try await backend.waitForRun(at: 0)
            if streaming { run.emit("Partial ") }
            state.focusConversation()
            state.naturalTranscriptHeight = 240
            state.editorHeight = 140
            let history = session.messages
            let unreadID = session.unreadReplyID
            let phase = session.replyPhase
            let focus = state.focusRequest
            let transcriptFocus = state.transcriptFocusRequest
            state.updateDraft("/")
            #expect(state.moveCommandSelection(by: -1))
            #expect(state.selectedCommand == .settings)

            #expect(state.submitDraft())
            #expect(openings == 1)
            #expect(session.draft.isEmpty)
            #expect(state.selectedCommand == nil)
            #expect(state.commandHeight == 0)
            #expect(state.editorHeight == DraftEditor.singleLineHeight(fontSize: state.fontSize))
            #expect(session.messages == history)
            #expect(session.unreadReplyID == unreadID)
            #expect(session.replyPhase == phase)
            #expect(session.isBusy)
            #expect(state.isExpanded)
            #expect(state.conversationPresentation == .thread)
            #expect(state.presentedMessages == history)
            #expect(state.naturalTranscriptHeight == 240)
            #expect(state.focusRequest == focus)
            #expect(state.transcriptFocusRequest == transcriptFocus)
            #expect(backend.runCount == 1)

            run.emit("Later answer")
            #expect(session.messages.last?.text == (streaming ? "Partial Later answer" : "Later answer"))
            run.finish()
            try await AsyncTestSupport.wait { !session.isBusy && run.didReturn }
            #expect(!run.wasCancelled)
            #expect(session.messages.last?.outcome == .completed)
            #expect(session.unreadReplyID == history.last?.id)
            #expect(backend.runCount == 1)
            #expect(openings == 1)
        }
    }

    @Test(arguments: [false, true])
    func missingHandlerAndDirectSessionRejectSettingsUnchanged(busy: Bool) async throws {
        try await withConversationFixture { session, backend, defaults in
            let state = PanelState(conversation: session, defaults: defaults)
            state.openPanel()
            state.updateDraft("Question")
            #expect(state.submitDraft())
            let run = try await backend.waitForRun(at: 0)
            run.emit("Answer")
            if !busy {
                run.finish()
                try await AsyncTestSupport.wait { !session.isBusy }
            }
            state.focusConversation()
            state.naturalTranscriptHeight = 240
            state.editorHeight = 140
            let history = session.messages
            let unreadID = session.unreadReplyID
            let phase = session.replyPhase
            let focus = state.focusRequest
            let transcriptFocus = state.transcriptFocusRequest
            for draft in ["/se", " \n/settings\t"] {
                state.updateDraft(draft)
                #expect(state.selectedCommand == .settings)
                let suggestions = state.commandSuggestions
                let commandHeight = state.commandHeight
                #expect(!state.submitDraft())
                #expect(!session.submitDraft())
                #expect(session.draft == draft)
                #expect(defaults.string(forKey: "draft") == draft)
                #expect(state.selectedCommand == .settings)
                #expect(state.commandSuggestions == suggestions)
                #expect(state.commandHeight == commandHeight)
                #expect(state.editorHeight == 140)
                #expect(session.messages == history)
                #expect(session.unreadReplyID == unreadID)
                #expect(session.replyPhase == phase)
                #expect(state.isExpanded)
                #expect(state.conversationPresentation == .thread)
                #expect(state.presentedMessages == history)
                #expect(state.naturalTranscriptHeight == 240)
                #expect(state.focusRequest == focus)
                #expect(state.transcriptFocusRequest == transcriptFocus)
                #expect(backend.runCount == 1)
            }
            if busy {
                run.emit(" continues")
                run.finish()
                try await AsyncTestSupport.wait { !session.isBusy && run.didReturn }
                #expect(!run.wasCancelled)
                #expect(session.messages.last?.text == "Answer continues")
                #expect(session.messages.last?.outcome == .completed)
            }
        }
    }
}
