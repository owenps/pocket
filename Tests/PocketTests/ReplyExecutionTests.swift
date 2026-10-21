import Foundation
import Testing
@testable import Pocket

struct ReplyExecutionTests {
    private let runID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let replyID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let nextRunID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    private let nextReplyID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!

    @Test func idleIgnoresEventsOtherThanStart() {
        let execution = ReplyExecution()
        #expect(execution.phase == .idle)
        #expect(execution.transition(.stop) == nil)
        #expect(execution.transition(.delta(runID: runID, text: "Late")) == nil)
        #expect(execution.transition(.finished(runID: runID, outcome: .completed)) == nil)
    }

    @Test func startEntersWorkingAndStartsTheRun() throws {
        let started = try #require(ReplyExecution().transition(.start(runID: runID, replyID: replyID)))
        #expect(started.execution.phase == .working)
        #expect(started.effects == [.start(runID: runID)])
    }

    @Test func orderedDeltasAppendToTheSameReplyThenComplete() throws {
        var execution = try #require(ReplyExecution().transition(.start(runID: runID, replyID: replyID))).execution
        for text in ["Hello", " ", "world"] {
            let delta = try #require(execution.transition(.delta(runID: runID, text: text)))
            #expect(delta.execution.phase == .streaming)
            #expect(delta.effects == [.append(replyID: replyID, text: text)])
            execution = delta.execution
        }
        let finished = try #require(execution.transition(.finished(runID: runID, outcome: .completed)))
        #expect(finished.execution.phase == .idle)
        #expect(finished.effects == [.complete(replyID: replyID, outcome: .completed)])
        #expect(finished.execution.transition(.delta(runID: runID, text: "Late")) == nil)
        #expect(finished.execution.transition(.finished(runID: runID, outcome: .completed)) == nil)
    }

    @Test(arguments: [false, true])
    func activeExecutionRejectsBusyStartsEmptyDeltasAndStaleEvents(streaming: Bool) throws {
        var execution = try #require(ReplyExecution().transition(.start(runID: runID, replyID: replyID))).execution
        if streaming {
            execution = try #require(execution.transition(.delta(runID: runID, text: "Partial"))).execution
        }
        #expect(execution.transition(.start(runID: nextRunID, replyID: nextReplyID)) == nil)
        #expect(execution.transition(.start(runID: runID, replyID: replyID)) == nil)
        #expect(execution.transition(.delta(runID: runID, text: "")) == nil)
        #expect(execution.transition(.delta(runID: nextRunID, text: "Stale")) == nil)
        #expect(execution.transition(.finished(runID: nextRunID, outcome: .completed)) == nil)
    }

    @Test(arguments: [false, true], [ReplyOutcome.completed, .stopped, .failed("Backend failed")])
    func finishedPreservesExplicitOutcomesExceptEmptyCompletion(streaming: Bool, outcome: ReplyOutcome) throws {
        var execution = try #require(ReplyExecution().transition(.start(runID: runID, replyID: replyID))).execution
        if streaming {
            execution = try #require(execution.transition(.delta(runID: runID, text: "Partial"))).execution
        }
        let finished = try #require(execution.transition(.finished(runID: runID, outcome: outcome)))
        let expected: ReplyOutcome = !streaming && outcome == .completed ? .failed("No reply received.") : outcome
        #expect(finished.execution.phase == .idle)
        #expect(finished.effects == [.complete(replyID: replyID, outcome: expected)])
    }

    @Test(arguments: [false, true])
    func stopCancelsBeforeCompletingAndRejectsLateEvents(streaming: Bool) throws {
        var execution = try #require(ReplyExecution().transition(.start(runID: runID, replyID: replyID))).execution
        if streaming {
            execution = try #require(execution.transition(.delta(runID: runID, text: "Partial"))).execution
        }
        let stopped = try #require(execution.transition(.stop))
        #expect(stopped.execution.phase == .idle)
        #expect(stopped.effects == [.cancel, .complete(replyID: replyID, outcome: .stopped)])
        #expect(stopped.execution.transition(.stop) == nil)
        #expect(stopped.execution.transition(.delta(runID: runID, text: "Late")) == nil)
        #expect(stopped.execution.transition(.finished(runID: runID, outcome: .failed("Late failure"))) == nil)
    }

    @Test func stoppedRunCannotAffectANewRun() throws {
        let started = try #require(ReplyExecution().transition(.start(runID: runID, replyID: replyID)))
        let stopped = try #require(started.execution.transition(.stop))
        let restarted = try #require(stopped.execution.transition(.start(runID: nextRunID, replyID: nextReplyID)))
        #expect(restarted.execution.phase == .working)
        #expect(restarted.effects == [.start(runID: nextRunID)])
        var execution = restarted.execution
        for text in ["New", " answer"] {
            #expect(execution.transition(.delta(runID: runID, text: "Stale")) == nil)
            for outcome: ReplyOutcome in [.completed, .stopped, .failed("Stale failure")] {
                #expect(execution.transition(.finished(runID: runID, outcome: outcome)) == nil)
            }
            let delta = try #require(execution.transition(.delta(runID: nextRunID, text: text)))
            #expect(delta.effects == [.append(replyID: nextReplyID, text: text)])
            execution = delta.execution
        }
        let finished = try #require(execution.transition(.finished(runID: nextRunID, outcome: .completed)))
        #expect(finished.execution.phase == .idle)
        #expect(finished.effects == [.complete(replyID: nextReplyID, outcome: .completed)])
    }
}
