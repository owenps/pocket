import CoreGraphics
import Foundation
import Testing
@testable import Pocket

struct AvatarAnimationTests {
    @Test func startsInactive() {
        var animation = AvatarAnimation(blinkInterval: 8...8)
        animation.advance(to: 100)
        #expect(animation.state == .inactive)
        #expect(animation.pose == AvatarAnimation.Pose())
        #expect(animation.drawingOffset == .zero)
        #expect(animation.nextDeadline == nil)
    }

    @Test func defaultBlinkWaitIsWithinRange() throws {
        var animation = AvatarAnimation()
        animation.update(behavior: .idle, at: 20)
        let deadline = try #require(animation.nextDeadline)
        #expect((24...28).contains(deadline))
        animation.update(behavior: .idle, at: 21)
        #expect(animation.nextDeadline == deadline)
    }

    @Test func equalUpdatesKeepDeadlinesAndAdvanceDueEvents() {
        var animation = AvatarAnimation(blinkInterval: 8...8)
        animation.update(behavior: .idle, at: 10)
        animation.update(behavior: .idle, at: 17)
        #expect(animation.nextDeadline == 18)
        animation.update(behavior: .idle, at: 18)
        #expect(animation.state == .idle)
        #expect(animation.pose == AvatarAnimation.Pose(eyes: .blink))
        #expect(animation.nextDeadline == 18.125)
        animation.update(behavior: .idle, at: 18.0625)
        #expect(animation.nextDeadline == 18.125)
        animation.update(behavior: .idle, at: 18.125)
        #expect(animation.pose == AvatarAnimation.Pose())
        #expect(animation.nextDeadline == 26.125)
    }

    @Test func blinkLastsOneEighthSecond() {
        var animation = AvatarAnimation(blinkInterval: 2...2)
        animation.update(behavior: .idle, at: 0)
        animation.advance(to: 1.999)
        #expect(animation.pose == AvatarAnimation.Pose())
        animation.advance(to: 2)
        #expect(animation.pose == AvatarAnimation.Pose(eyes: .blink))
        #expect(animation.drawingOffset == .zero)
        animation.advance(to: 2.124)
        #expect(animation.pose.eyes == .blink)
        animation.advance(to: 2.125)
        #expect(animation.pose == AvatarAnimation.Pose())
        #expect(animation.nextDeadline == 4.125)
    }

    @Test func restingNeverBlinksOrGlances() {
        var animation = AvatarAnimation(blinkInterval: 2...2)
        animation.update(behavior: .resting, at: 0)
        for time in [0.125, 2, 4, 100, 1000] {
            animation.update(behavior: .resting, at: time)
            #expect(animation.state == .idle)
            #expect(animation.pose == AvatarAnimation.Pose())
            #expect(animation.drawingOffset == .zero)
            #expect(animation.nextDeadline == nil)
        }
    }

    @Test func idleOnlyBlinksAndNeverMovesEyesOrBody() {
        var animation = AvatarAnimation(blinkInterval: 2...2)
        animation.update(behavior: .idle, at: 0)
        var eyes = Set<AvatarRenderer.Eyes>()
        for frame in 0...160 {
            animation.update(behavior: .idle, at: Double(frame) / 8)
            eyes.insert(animation.pose.eyes)
            #expect(animation.pose.mouth == .resting)
            #expect(animation.drawingOffset == .zero)
        }
        #expect(eyes == [.natural, .blink])
    }

    @Test func speakingPreemptsBlinkAndDiscardsItsDeadline() {
        var animation = AvatarAnimation(blinkInterval: 2...2)
        animation.update(behavior: .idle, at: 0)
        animation.advance(to: 2)
        animation.update(behavior: .speaking, at: 2.0625)
        #expect(animation.state == .speaking)
        #expect(animation.pose == AvatarAnimation.Pose(mouth: .small))
        #expect(animation.drawingOffset == .zero)
        #expect(animation.nextDeadline == nil)
        for time in [2.125, 2.4, 4, 100] {
            animation.advance(to: time)
            #expect(animation.state == .speaking)
            #expect(animation.nextDeadline == nil)
        }
    }

    @Test func speakingUpdatesDoNotRestartAndReturningToIdleWaitsFresh() {
        var animation = AvatarAnimation(blinkInterval: 8...8)
        animation.update(behavior: .speaking, at: 0.125)
        animation.update(behavior: .speaking, at: 0.25)
        #expect(animation.pose.mouth == .resting)
        animation.update(behavior: .idle, at: 4)
        #expect(animation.state == .idle)
        #expect(animation.pose == AvatarAnimation.Pose())
        #expect(animation.drawingOffset == .zero)
        #expect(animation.nextDeadline == 12)
    }

    @Test func previewBlinksThenTalksAndStopsAtOneAndThreeEighthSeconds() {
        var animation = AvatarAnimation(blinkInterval: 0.01...0.01)
        animation.update(behavior: .preview, at: 10)
        #expect(animation.state == .previewBlink)
        #expect(animation.pose == AvatarAnimation.Pose(eyes: .blink))
        #expect(animation.drawingOffset == .zero)
        #expect(animation.nextDeadline == 10.125)
        animation.update(behavior: .preview, at: 10.124)
        #expect(animation.pose == AvatarAnimation.Pose(eyes: .blink))
        #expect(animation.nextDeadline == 10.125)
        var mouths = Set<AvatarRenderer.Mouth>()
        for frame in 0..<10 {
            animation.update(behavior: .preview, at: 10.125 + Double(frame) / 8)
            #expect(animation.state == .speaking)
            #expect(animation.pose.eyes == .natural)
            #expect(animation.nextDeadline == 11.375)
            mouths.insert(animation.pose.mouth)
        }
        #expect(mouths == [.resting, .small, .open])
        for time in [11.375, 12, 100, 1000] {
            animation.update(behavior: .preview, at: time)
            #expect(animation.state == .inactive)
            #expect(animation.pose == AvatarAnimation.Pose())
            #expect(animation.drawingOffset == .zero)
            #expect(animation.nextDeadline == nil)
        }
    }

    @Test(arguments: [0.0625, 0.5, 1.375])
    func leavingPreviewCancelsEveryPhaseAndReentryStartsFresh(elapsed: TimeInterval) {
        var animation = AvatarAnimation()
        animation.update(behavior: .preview, at: 0)
        animation.advance(to: elapsed)
        animation.update(behavior: .inactive, at: elapsed)
        animation.advance(to: 100)
        #expect(animation.pose == AvatarAnimation.Pose())
        #expect(animation.drawingOffset == .zero)
        #expect(animation.nextDeadline == nil)
        animation.update(behavior: .preview, at: 100)
        #expect(animation.pose == AvatarAnimation.Pose(eyes: .blink))
        #expect(animation.nextDeadline == 100.125)
    }

    @Test func missedPreviewFinishesWithoutReplayingSpeechOrBlinks() {
        var animation = AvatarAnimation()
        animation.update(behavior: .preview, at: 0)
        animation.advance(to: 10_000)
        #expect(animation.state == .inactive)
        #expect(animation.pose == AvatarAnimation.Pose())
        #expect(animation.drawingOffset == .zero)
        #expect(animation.nextDeadline == nil)
    }

    @Test(arguments: [AvatarAnimation.Behavior.idle, .resting, .speaking, .preview])
    func inactiveCancelsEverythingAndReactivationIsFresh(_ behavior: AvatarAnimation.Behavior) {
        var animation = AvatarAnimation(blinkInterval: 8...8)
        animation.update(behavior: behavior, at: 0)
        animation.advance(to: 0.25)
        animation.update(behavior: .inactive, at: 0.3)
        animation.advance(to: 100)
        #expect(animation.state == .inactive)
        #expect(animation.pose == AvatarAnimation.Pose())
        #expect(animation.drawingOffset == .zero)
        #expect(animation.nextDeadline == nil)
        animation.update(behavior: behavior, at: 100)
        switch behavior {
        case .idle: #expect(animation.nextDeadline == 108)
        case .preview:
            #expect(animation.pose == AvatarAnimation.Pose(eyes: .blink))
            #expect(animation.nextDeadline == 100.125)
        default: #expect(animation.nextDeadline == nil)
        }
    }

    @Test func speechVariesMouthAndEyesWithBoundedSubpointDrawingMotion() {
        var animation = AvatarAnimation()
        animation.update(behavior: .speaking, at: 100)
        var mouths: Set<AvatarRenderer.Mouth> = []
        var eyes: Set<AvatarRenderer.Eyes> = []
        var offsets: [CGPoint] = []
        for elapsed in [0.0, 0.2, 0.4, 2.1, 4.1, 7.3, 12.8, 210.2] {
            animation.advance(to: 100 + elapsed)
            mouths.insert(animation.pose.mouth)
            eyes.insert(animation.pose.eyes)
            offsets.append(animation.drawingOffset)
            #expect(animation.state == .speaking)
            #expect(animation.drawingOffset.x.isFinite && animation.drawingOffset.y.isFinite)
            #expect(abs(animation.drawingOffset.x) < 1 && abs(animation.drawingOffset.y) < 1)
            #expect(animation.nextDeadline == nil)
        }
        #expect(mouths == Set(AvatarRenderer.Mouth.allCases))
        #expect(eyes == Set(AvatarRenderer.Eyes.allCases))
        #expect(offsets.contains { $0 != .zero })
        #expect(offsets.contains { $0.x < 0 } && offsets.contains { $0.x > 0 })
        #expect(offsets.contains { $0.y < 0 } && offsets.contains { $0.y > 0 })
    }

    @Test func speechBeforeItsStartUsesTheInitialPose() {
        var animation = AvatarAnimation()
        animation.update(behavior: .speaking, at: 100)
        let initial = animation.pose
        for time in [100.05, 99] {
            animation.advance(to: time)
            #expect(animation.pose == initial)
            #expect(animation.drawingOffset == .zero)
        }
    }

    @Test func largeElapsedTimesDoNotReplayMissedIdleEvents() {
        var animation = AvatarAnimation(blinkInterval: 2...2)
        animation.update(behavior: .idle, at: 0)
        animation.advance(to: 10_000)
        #expect(animation.pose == AvatarAnimation.Pose(eyes: .blink))
        #expect(animation.nextDeadline == 10_000.125)
        animation.advance(to: 20_000)
        #expect(animation.pose == AvatarAnimation.Pose())
        #expect(animation.nextDeadline == 20_002)
    }

    @Test func largeElapsedSpeechSamplesCurrentFrameDirectly() {
        var animation = AvatarAnimation()
        animation.update(behavior: .speaking, at: 10)
        animation.advance(to: 10 + Double(1680 * 1000 + 32) / 8)
        #expect(animation.state == .speaking)
        #expect(animation.pose == AvatarAnimation.Pose(mouth: .small, eyes: .blink))
        #expect(animation.nextDeadline == nil)
    }
}
