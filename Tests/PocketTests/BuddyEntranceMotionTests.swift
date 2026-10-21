import Foundation
import Testing
@testable import Pocket

struct BuddyEntranceMotionTests {
    @Test func popPeaksAtOneHundredFortyMillisecondsAndSettlesAtThreeHundredForty() {
        var motion = BuddyEntranceMotion()
        let hidden = BuddyEntranceMotion.pose(at: motion.progress)
        #expect(hidden == .init(opacity: 0, scale: 0.6, offsetY: 6))
        motion.update(expanded: true, contentVisibility: 1, elapsed: 0.05)
        #expect(motion.progress == 0)
        motion.update(expanded: true, contentVisibility: 1, elapsed: 0.14)
        let peak = BuddyEntranceMotion.pose(at: motion.progress)
        #expect(peak.opacity == 1)
        #expect(abs(peak.scale - 1.14) < 0.0001)
        #expect(abs(peak.offsetY) < 0.0001)
        #expect(motion.isActive)
        motion.update(expanded: true, contentVisibility: 1, elapsed: 0.09)
        let settling = BuddyEntranceMotion.pose(at: motion.progress)
        #expect(settling.scale > 1 && settling.scale < peak.scale)
        var completed = BuddyEntranceMotion()
        completed.update(expanded: true, contentVisibility: 1, elapsed: 0.39)
        #expect(BuddyEntranceMotion.pose(at: completed.progress) == .init(opacity: 1, scale: 1, offsetY: 0))
        #expect(!completed.isActive)
    }

    @Test func delayStartsAtRevealAndSurvivesPartialCloseWithoutRestarting() {
        var motion = BuddyEntranceMotion()
        motion.update(expanded: true, contentVisibility: 0.49, elapsed: 10)
        #expect(motion.progress == 0)
        motion.update(expanded: true, contentVisibility: 0.5, elapsed: 0.03)
        #expect(motion.progress == 0)
        #expect(motion.isActive)
        motion.update(expanded: false, contentVisibility: 0.2, elapsed: 10)
        #expect(!motion.isActive)
        motion.update(expanded: true, contentVisibility: 0.2, elapsed: 0.01)
        #expect(motion.progress == 0)
        motion.update(expanded: true, contentVisibility: 1, elapsed: 0.02)
        #expect(abs(motion.progress - 0.01 / 0.34) < 0.0001)
        motion.update(expanded: false, contentVisibility: 0)
        motion.update(expanded: true, contentVisibility: 1, elapsed: 0.04)
        #expect(motion.progress == 0)
    }

    @Test func popRemainsBoundedThroughoutArrivalAndSettle() {
        for step in 0...400 {
            let pose = BuddyEntranceMotion.pose(at: Double(step) / 400)
            #expect((0...1).contains(pose.opacity))
            #expect(pose.scale >= 0.6 - 1e-12 && pose.scale <= 1.14 + 1e-12)
            #expect((0...6).contains(pose.offsetY))
        }
        // Fully visible before the expansion reaches its peak.
        let arrival = BuddyEntranceMotion.pose(at: 0.05 / 0.34)
        #expect(arrival.opacity == 1)
        #expect(arrival.scale > 1 && arrival.scale < 1.14)
        let early = BuddyEntranceMotion.pose(at: 0.025 / 0.34)
        #expect(abs(early.opacity - 0.5) < 0.0001)
    }

    @Test func burstFlashesAtPeakThenDriftsOutAndDisappearsWithinOneHundredFiftyMilliseconds() {
        #expect(BuddyEntranceMotion.burst(at: 0).opacity == 0)
        #expect(BuddyEntranceMotion.burst(at: 0.13 / 0.34).opacity == 0)
        let peak = BuddyEntranceMotion.burst(at: 0.14 / 0.34)
        #expect(abs(peak.opacity - 1) < 0.0001)
        #expect(abs(peak.travel) < 0.0001)
        let fading = BuddyEntranceMotion.burst(at: 0.215 / 0.34)
        #expect(abs(fading.opacity - 0.5) < 0.0001)
        #expect(abs(fading.travel - 0.5) < 0.0001)
        #expect(BuddyEntranceMotion.burst(at: 0.29 / 0.34).opacity < 0.0001)
        #expect(BuddyEntranceMotion.burst(at: 1).opacity == 0)
        for step in 0...100 {
            let progress = Double(step) / 100
            #expect(BuddyEntranceMotion.burst(at: progress, reduceMotion: true).opacity == 0)
        }
    }

    @Test func reducedMotionIsAnUnscaledStationaryOneHundredEightyMillisecondFade() {
        var motion = BuddyEntranceMotion()
        motion.update(expanded: true, contentVisibility: 1, elapsed: 0.14)
        let halfway = BuddyEntranceMotion.pose(at: motion.progress, reduceMotion: true)
        #expect(abs(halfway.opacity - 0.5) < 0.0001)
        motion.update(expanded: true, contentVisibility: 1, elapsed: 0.09)
        #expect(abs(BuddyEntranceMotion.pose(at: motion.progress, reduceMotion: true).opacity - 1) < 0.0001)
        for step in 0...100 {
            let pose = BuddyEntranceMotion.pose(at: Double(step) / 100, reduceMotion: true)
            #expect(pose.scale == 1)
            #expect(pose.offsetY == 0)
        }
    }

    @Test func entranceIsBoundedMonotonicAndRestsIdempotently() {
        var motion = BuddyEntranceMotion()
        motion.update(expanded: true, contentVisibility: 1)
        #expect(motion.progress == 0)
        #expect(motion.isActive)
        var previous = motion.progress
        var hadIntermediatePose = false
        for _ in 0..<100 {
            motion.update(expanded: true, contentVisibility: 1, elapsed: 0.01)
            #expect(motion.progress >= previous && motion.progress <= 1)
            hadIntermediatePose = hadIntermediatePose || (motion.progress > 0 && motion.progress < 1)
            previous = motion.progress
        }
        #expect(hadIntermediatePose)
        #expect(motion.progress == 1)
        #expect(!motion.isActive)
        motion.update(expanded: true, contentVisibility: 1, elapsed: 10)
        #expect(motion.progress == 1)
        #expect(!motion.isActive)
    }

    @Test func fullyHiddenTimeDoesNotAdvanceOrAccumulate() {
        var motion = BuddyEntranceMotion()
        #expect(motion.progress == 0)
        #expect(!motion.isActive)
        motion.update(expanded: false, contentVisibility: 0, elapsed: 10)
        #expect(motion.progress == 0)
        #expect(!motion.isActive)
        motion.update(expanded: true, contentVisibility: 0, elapsed: 10)
        #expect(motion.progress == 0)
        #expect(motion.isActive)
        motion.update(expanded: true, contentVisibility: 1)
        #expect(motion.progress == 0)
        motion.update(expanded: true, contentVisibility: 1, elapsed: 0.09)
        #expect(motion.progress > 0 && motion.progress < 1)
    }

    @Test(arguments: [false, true])
    func partialCloseFreezesAndReopeningResumesWithoutReplay(completed: Bool) {
        var motion = BuddyEntranceMotion()
        motion.update(expanded: true, contentVisibility: 1, elapsed: completed ? 1 : 0.09)
        let retained = motion.progress
        for visibility in [0.8, 0.2] {
            motion.update(expanded: false, contentVisibility: visibility, elapsed: 10)
            #expect(motion.progress == retained)
            #expect(!motion.isActive)
        }
        motion.update(expanded: true, contentVisibility: 0.2)
        #expect(motion.progress == retained)
        #expect(motion.isActive == !completed)
        motion.update(expanded: true, contentVisibility: 1, elapsed: 0.04)
        if completed {
            #expect(motion.progress == 1)
            #expect(!motion.isActive)
        } else {
            #expect(motion.progress > retained && motion.progress < 1)
        }
    }

    @Test(arguments: [false, true])
    func fullyHiddenCloseRearmsNextOpening(completed: Bool) {
        var motion = BuddyEntranceMotion()
        motion.update(expanded: true, contentVisibility: 1, elapsed: completed ? 1 : 0.09)
        motion.update(expanded: false, contentVisibility: 0)
        #expect(motion.progress == 0)
        #expect(!motion.isActive)
        motion.update(expanded: true, contentVisibility: 0, elapsed: 1)
        #expect(motion.progress == 0)
        #expect(motion.isActive)
        motion.update(expanded: true, contentVisibility: 1, elapsed: 0.09)
        #expect(motion.progress > 0 && motion.progress < 1)
    }

    @Test func repeatedExpandedUpdatesDoNotRestartEntrance() {
        var motion = BuddyEntranceMotion()
        motion.update(expanded: true, contentVisibility: 1, elapsed: 0.09)
        let retained = motion.progress
        for visibility in [1.0, 0.8, 0.3, 0, 1] {
            motion.update(expanded: true, contentVisibility: visibility)
            #expect(motion.progress == retained)
            #expect(motion.isActive)
        }
        motion.update(expanded: true, contentVisibility: 1, elapsed: 0.04)
        #expect(motion.progress > retained && motion.progress < 1)
    }

    @Test func invalidElapsedIsIgnoredAndDelayedFramesCatchUp() {
        var motion = BuddyEntranceMotion()
        motion.update(expanded: true, contentVisibility: 1, elapsed: 0.09)
        let retained = motion.progress
        for elapsed in [0.0, -0.1, Double.nan, Double.infinity, -Double.infinity] {
            motion.update(expanded: true, contentVisibility: 1, elapsed: elapsed)
            #expect(motion.progress == retained)
            #expect(motion.isActive)
        }
        motion.update(expanded: true, contentVisibility: 1, elapsed: 0.04)
        #expect(motion.progress > retained && motion.progress < 1)
        for elapsed in [1.0, 10.0, Double.greatestFiniteMagnitude] {
            var delayed = motion
            delayed.update(expanded: true, contentVisibility: 1, elapsed: elapsed)
            #expect(delayed.progress == 1)
            #expect(!delayed.isActive)
        }
    }

    @Test func entranceOverlapsPanelRevealAndFinishesLater() {
        let geometry = IslandGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1800, height: 1169), notchHeight: 38
        )
        let target = geometry.expandedLayout(composerHeight: 40, naturalTranscriptHeight: 0)
        var initial = target
        initial.size = geometry.collapsedSize
        var panel = IslandMotion(layout: initial)
        var entrance = BuddyEntranceMotion()
        panel.retarget(to: target, expanded: true)
        let interval = 1.0 / 120
        var overlappedReveal = false
        var reachedFullReveal = false
        for _ in 0..<120 {
            panel.advance(by: interval)
            let expansion = (panel.layout.size.width - geometry.collapsedSize.width)
                / (target.size.width - geometry.collapsedSize.width)
            let visibility = IslandMotion.contentVisibility(
                surfaceSize: panel.layout.size, expandedSize: target.size, expansionProgress: expansion
            )
            entrance.update(expanded: true, contentVisibility: visibility, elapsed: interval)
            if visibility == 0 { #expect(entrance.progress == 0) }
            if visibility > 0 && visibility < 1 && entrance.progress > 0 {
                overlappedReveal = true
            }
            if !reachedFullReveal, visibility == 1 {
                #expect(overlappedReveal)
                #expect(entrance.progress > 0 && entrance.progress < 1)
                reachedFullReveal = true
            }
        }
        #expect(reachedFullReveal)
        #expect(entrance.progress == 1)
        #expect(!entrance.isActive)
    }
}
