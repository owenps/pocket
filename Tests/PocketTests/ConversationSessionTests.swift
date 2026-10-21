import Foundation
import PocketTestSupport
import Testing
@testable import Pocket

@MainActor
struct ConversationSessionTests {
    @Test func blankSubmissionLeavesStateAndPersistenceUnchanged() async throws {
        try await withConversationFixture { session, backend, defaults in
            for blank in ["", " \t\n "] {
                session.draft = blank
                #expect(!session.submitDraft())
                #expect(session.draft == blank)
                #expect(defaults.string(forKey: "draft") == blank)
                #expect(session.messages.isEmpty)
                #expect(session.replyPhase == .idle)
                #expect(!session.isBusy)
                #expect(!session.hasUnreadReply)
                #expect(backend.runCount == 0)
            }
        }
    }

    @Test func acceptedSubmissionSnapshotsInputAndClearsPersistedDraftSynchronously() async throws {
        try await withConversationFixture { session, backend, defaults in
            let input = "  Remember Friday\nBring notes  "
            session.draft = input
            #expect(session.submitDraft())
            try #require(session.messages.count == 2)
            #expect(session.messages.map(\.role) == [.user, .assistant])
            #expect(session.messages.map(\.text) == [input, ""])
            #expect(session.messages[0].id != session.messages[1].id)
            #expect(session.messages.allSatisfy { $0.outcome == nil })
            #expect(session.draft.isEmpty)
            #expect(defaults.string(forKey: "draft") == "")
            #expect(session.replyPhase == .working)
            #expect(session.isBusy)
            #expect(!session.hasUnreadReply)
            session.draft = "Next thought"
            let run = try await backend.waitForRun(at: 0)
            #expect(run.history == [session.messages[0]])
            #expect(run.history[0].text == input)
        }
    }

    @Test func busySubmissionPreservesNewDraftDuringWorkingAndStreaming() async throws {
        try await withConversationFixture { session, backend, defaults in
            session.draft = "First"
            #expect(session.submitDraft())
            let run = try await backend.waitForRun(at: 0)
            session.draft = "Unsent follow-up"
            for phase: ReplyPhase in [.working, .streaming] {
                let messages = session.messages
                #expect(session.replyPhase == phase)
                #expect(!session.submitDraft())
                #expect(session.messages == messages)
                #expect(session.draft == "Unsent follow-up")
                #expect(defaults.string(forKey: "draft") == "Unsent follow-up")
                #expect(backend.runCount == 1)
                if phase == .working { run.emit("Partial") }
            }
        }
    }

    @Test func orderedDeltasCompleteTheSameReplyAndReceiptsRequireASettledMatchingID() async throws {
        try await withConversationFixture { session, backend, _ in
            session.draft = "Hello"
            #expect(session.submitDraft())
            let ids = session.messages.map(\.id)
            let replyID = try #require(ids.last)
            let run = try await backend.waitForRun(at: 0)
            run.emit("")
            #expect(session.replyPhase == .working)
            #expect(!session.hasUnreadReply)
            session.markReplyViewed(replyID)
            run.emit("Hello")
            #expect(session.replyPhase == .streaming)
            #expect(session.isBusy)
            #expect(session.unreadReplyID == replyID)
            session.markReplyViewed(replyID)
            #expect(session.hasUnreadReply)
            run.emit(", world")
            #expect(session.messages.last?.text == "Hello, world")
            run.finish()
            try await AsyncTestSupport.wait { !session.isBusy }
            #expect(session.replyPhase == .idle)
            #expect(session.messages.map(\.id) == ids)
            #expect(session.messages.first?.text == "Hello")
            #expect(session.messages.last?.outcome == .completed)
            #expect(session.messages.first?.outcome == nil)
            session.markReplyViewed(UUID())
            #expect(session.unreadReplyID == replyID)
            session.markReplyViewed(replyID)
            #expect(session.unreadReplyID == nil)
            #expect(!session.hasUnreadReply)
            let completed = session.messages
            run.emit("Late output")
            #expect(session.messages == completed)
            #expect(!session.hasUnreadReply)
        }
    }

    @Test(arguments: [false, true])
    func stopRetainsDraftAndPartialReplyAndRejectsLateUpdates(streaming: Bool) async throws {
        try await withConversationFixture { session, backend, defaults in
            session.draft = "Question"
            #expect(session.submitDraft())
            let run = try await backend.waitForRun(at: 0)
            if streaming { run.emit("Partial answer") }
            let partialReply = session.messages.last?.text
            session.draft = "Keep typing"
            session.stopReply()
            let stopped = session.messages
            #expect(session.replyPhase == .idle)
            #expect(!session.isBusy)
            #expect(stopped.last?.text == partialReply)
            #expect(stopped.last?.outcome == .stopped)
            #expect(stopped.first?.outcome == nil)
            #expect(session.unreadReplyID == stopped.last?.id)
            #expect(session.draft == "Keep typing")
            #expect(defaults.string(forKey: "draft") == "Keep typing")
            session.stopReply()
            run.emit("Late output")
            run.finish(.failure(BackendFailure()))
            try await AsyncTestSupport.wait { run.didReturn }
            #expect(run.wasCancelled)
            #expect(session.messages == stopped)
            #expect(session.replyPhase == .idle)
            #expect(session.draft == "Keep typing")
        }
    }

    @Test func stopBeforeBackendStartsCancelsOnlyThatRunAndAllowsImmediateFollowup() async throws {
        try await withConversationFixture { session, backend, _ in
            session.draft = "First question"
            #expect(session.submitDraft())
            session.stopReply()
            let stopped = session.messages
            #expect(stopped.last?.outcome == .stopped)
            #expect(!session.isBusy)

            session.draft = "Next question"
            #expect(session.submitDraft())
            let run = try await backend.waitForRun(at: 0)
            #expect(backend.runCount == 1)
            #expect(Array(run.history.prefix(2)) == stopped)
            #expect(run.history.last?.text == "Next question")
            #expect(session.replyPhase == .working)
            run.emit("New reply")
            run.finish()
            try await AsyncTestSupport.wait { !session.isBusy }
            #expect(session.messages.last?.text == "New reply")
            #expect(session.messages.last?.outcome == .completed)
            #expect(Array(session.messages.prefix(2)) == stopped)
        }
    }

    @Test(arguments: [false, true])
    func stoppedRunCannotAppendToOrFinishANewerTurn(fails: Bool) async throws {
        try await withConversationFixture { session, backend, _ in
            session.draft = "Old question"
            #expect(session.submitDraft())
            let oldRun = try await backend.waitForRun(at: 0)
            oldRun.emit("Old partial")
            session.stopReply()
            let stoppedTurn = session.messages
            session.draft = "New question"
            #expect(session.submitDraft())
            let newRun = try await backend.waitForRun(at: 1)
            session.draft = "Keep composing"
            let working = session.messages
            let unreadID = session.unreadReplyID
            oldRun.emit("Stale delta")
            oldRun.finish(fails ? .failure(BackendFailure()) : .success(()))
            try await AsyncTestSupport.wait { oldRun.didReturn }
            #expect(session.messages == working)
            #expect(session.replyPhase == .working)
            #expect(session.unreadReplyID == unreadID)
            newRun.emit("New answer")
            oldRun.emit("Still stale")
            #expect(session.messages.last?.text == "New answer")
            #expect(session.replyPhase == .streaming)
            newRun.finish()
            try await AsyncTestSupport.wait { !session.isBusy }
            #expect(Array(session.messages.prefix(2)) == stoppedTurn)
            #expect(session.messages[2].text == "New question")
            #expect(session.messages.last?.outcome == .completed)
            #expect(session.draft == "Keep composing")
        }
    }

    @Test func resetCancelsAndClearsTranscriptAndUnreadButKeepsUnsentDraft() async throws {
        try await withConversationFixture { session, backend, defaults in
            session.draft = "Discard this turn"
            #expect(session.submitDraft())
            let run = try await backend.waitForRun(at: 0)
            run.emit("Partial answer")
            session.draft = "Keep this unsent"
            session.reset()
            #expect(session.messages.isEmpty)
            #expect(session.replyPhase == .idle)
            #expect(!session.isBusy)
            #expect(!session.hasUnreadReply)
            #expect(session.unreadReplyID == nil)
            #expect(session.draft == "Keep this unsent")
            #expect(defaults.string(forKey: "draft") == "Keep this unsent")
            run.emit("Stale output")
            run.finish(.failure(BackendFailure()))
            try await AsyncTestSupport.wait { run.didReturn }
            #expect(run.wasCancelled)
            #expect(session.messages.isEmpty)
            #expect(session.replyPhase == .idle)
            #expect(!session.hasUnreadReply)
            #expect(session.draft == "Keep this unsent")
        }
    }

    @Test(arguments: [false, true])
    func resetRunCannotCorruptAnImmediateNewSubmission(fails: Bool) async throws {
        try await withConversationFixture { session, backend, defaults in
            session.draft = "Discarded question"
            #expect(session.submitDraft())
            let oldRun = try await backend.waitForRun(at: 0)
            oldRun.emit("Discarded partial")

            session.reset()
            session.draft = "New question"
            #expect(session.submitDraft())
            let newRun = try await backend.waitForRun(at: 1)
            #expect(newRun.history == Array(session.messages.dropLast()))
            #expect(newRun.history.map(\.text) == ["New question"])
            let newTurn = session.messages
            let replyID = try #require(newTurn.last?.id)
            session.draft = "Keep composing"

            oldRun.emit("Stale delta")
            oldRun.finish(fails ? .failure(BackendFailure()) : .success(()))
            try await AsyncTestSupport.wait { oldRun.didReturn }
            #expect(oldRun.wasCancelled)
            #expect(session.messages == newTurn)
            #expect(session.replyPhase == .working)
            #expect(!session.hasUnreadReply)

            newRun.emit("New answer")
            oldRun.emit("Still stale")
            #expect(session.messages.last?.text == "New answer")
            #expect(session.replyPhase == .streaming)
            #expect(session.unreadReplyID == replyID)
            newRun.finish()
            try await AsyncTestSupport.wait { !session.isBusy }
            #expect(!newRun.wasCancelled)
            #expect(session.messages.count == 2)
            #expect(session.messages.first == newTurn.first)
            #expect(session.messages.last?.id == replyID)
            #expect(session.messages.last?.text == "New answer")
            #expect(session.messages.last?.outcome == .completed)
            #expect(session.unreadReplyID == replyID)
            #expect(session.draft == "Keep composing")
            #expect(defaults.string(forKey: "draft") == "Keep composing")
        }
    }

    @Test func recreatedSessionRestoresDraftButNotConversationOrExecution() async throws {
        try await withConversationFixture { session, backend, defaults in
            session.draft = "An earlier turn"
            #expect(session.submitDraft())
            let run = try await backend.waitForRun(at: 0)
            run.emit("Completed answer")
            run.finish()
            try await AsyncTestSupport.wait { !session.isBusy }
            session.draft = "Persistent unsent draft"
            let restored = ConversationSession(backend: backend, defaults: defaults)
            #expect(restored.draft == "Persistent unsent draft")
            #expect(restored.messages.isEmpty)
            #expect(restored.replyPhase == .idle)
            #expect(!restored.isBusy)
            #expect(!restored.hasUnreadReply)
            #expect(backend.runCount == 1)
        }
    }

    @Test func followupHistorySnapshotsPriorTurnsAndAcceptedInputWithoutPlaceholder() async throws {
        try await withConversationFixture { session, backend, _ in
            session.draft = "First question"
            #expect(session.submitDraft())
            let first = try await backend.waitForRun(at: 0)
            first.emit("First answer")
            first.finish()
            try await AsyncTestSupport.wait { !session.isBusy }
            let firstTurn = session.messages
            session.draft = "Follow-up question"
            #expect(session.submitDraft())
            let second = try await backend.waitForRun(at: 1)
            let history = second.history
            #expect(history == Array(session.messages.dropLast()))
            #expect(history.map(\.role) == [.user, .assistant, .user])
            #expect(Array(history.prefix(2)) == firstTurn)
            #expect(history.last?.text == "Follow-up question")
            session.draft = "Another unsent thought"
            second.emit("Follow-up answer")
            second.finish()
            try await AsyncTestSupport.wait { !session.isBusy }
            #expect(second.history == history)
            #expect(Array(session.messages.prefix(2)) == firstTurn)
            #expect(session.messages.last?.text == "Follow-up answer")
            #expect(session.draft == "Another unsent thought")
        }
    }

    @Test(arguments: [false, true])
    func backendFailurePreservesPartialTextAndRecordsFailure(streaming: Bool) async throws {
        try await withConversationFixture { session, backend, _ in
            session.draft = "Question"
            #expect(session.submitDraft())
            let run = try await backend.waitForRun(at: 0)
            let replyID = try #require(session.messages.last?.id)
            if streaming { run.emit("Partial answer") }
            session.draft = "Unsent follow-up"
            run.finish(.failure(BackendFailure()))
            try await AsyncTestSupport.wait { !session.isBusy }
            let reply = try #require(session.messages.last)
            #expect(reply.id == replyID)
            #expect(reply.text == (streaming ? "Partial answer" : ""))
            #expect(reply.outcome == .failed(BackendFailure().localizedDescription))
            #expect(session.messages.first?.outcome == nil)
            #expect(session.replyPhase == .idle)
            #expect(session.unreadReplyID == replyID)
            #expect(session.draft == "Unsent follow-up")
            let failed = session.messages
            run.emit("Too late")
            #expect(session.messages == failed)
            session.markReplyViewed(replyID)
            #expect(!session.hasUnreadReply)
        }
    }

    @Test func emptyBackendCompletionProducesAReadableFailure() async throws {
        try await withConversationFixture { session, backend, _ in
            session.draft = "Question"
            #expect(session.submitDraft())
            let run = try await backend.waitForRun(at: 0)
            run.finish()
            try await AsyncTestSupport.wait { !session.isBusy }
            let reply = try #require(session.messages.last)
            let outcome = try #require(reply.outcome)
            guard case .failed(let message) = outcome else {
                Issue.record("Expected a failed reply")
                return
            }
            #expect(!message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(session.unreadReplyID == reply.id)
            session.markReplyViewed(reply.id)
            #expect(!session.hasUnreadReply)
        }
    }

    @Test func backendCancellationSettlesAsStoppedRatherThanFailed() async throws {
        try await withConversationFixture { session, backend, _ in
            session.draft = "Question"
            #expect(session.submitDraft())
            let run = try await backend.waitForRun(at: 0)
            run.finish(.failure(CancellationError()))
            try await AsyncTestSupport.wait { !session.isBusy }
            #expect(session.messages.last?.outcome == .stopped)
            #expect(session.unreadReplyID == session.messages.last?.id)
        }
    }

    @Test(arguments: [false, true])
    func fixtureFailureCancelsAndDrainsRetainedRuns(reset: Bool) async throws {
        var runs: [ControlledAssistantBackend.Run] = []
        do {
            try await withConversationFixture { session, backend, _ in
                session.draft = "Old question"
                #expect(session.submitDraft())
                runs.append(try await backend.waitForRun(at: 0))
                if reset { session.reset() } else { session.stopReply() }
                session.draft = "New question"
                #expect(session.submitDraft())
                runs.append(try await backend.waitForRun(at: 1))
                throw BackendFailure()
            }
            Issue.record("Expected fixture to rethrow the body failure")
        } catch is BackendFailure {
            #expect(runs.count == 2)
            for run in runs {
                #expect(run.wasCancelled)
                #expect(run.didReturn)
                #expect(!run.isPending)
            }
        }
    }

    @Test func releasingSessionWhileBackendIsSuspendedCancelsWorkWithoutRetainingSession() async throws {
        let name = "ConversationSessionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let backend = ControlledAssistantBackend()
        var session: ConversationSession? = ConversationSession(backend: backend, defaults: defaults)
        let isReleased = { @MainActor [weak session] in session == nil }
        session?.draft = "Question"
        #expect(session?.submitDraft() == true)
        let result: Result<Void, any Error>
        do {
            let run = try await backend.waitForRun(at: 0)
            session = nil
            #expect(isReleased())
            // The retained callback must not keep its owner alive either.
            run.emit("Late output after release")
            run.finish()
            try await AsyncTestSupport.wait { run.didReturn }
            #expect(run.wasCancelled)
            #expect(isReleased())
            result = .success(())
        } catch {
            result = .failure(error)
        }
        session?.stopReply()
        session = nil
        try await backend.drain()
        try result.get()
    }
}

private struct BackendFailure: LocalizedError {
    var errorDescription: String? { "Backend unavailable" }
}
