import Foundation
import SwiftUI
import Testing
@testable import Pocket

@MainActor
struct IslandMotionTests {
    private let step = 1.0 / 120.0
    private let tolerance = 1e-8
    private let collapsed = IslandLayout(size: CGSize(width: 148, height: 28), composerHeight: 0)
    private let open = IslandLayout(size: CGSize(width: 500, height: 300),
                                    composerHeight: 60, editorHeight: 40, transcriptHeight: 180, transcriptGap: 12)
    private let tall = IslandLayout(size: CGSize(width: 540.25, height: 500.75),
                                    composerHeight: 140.25, editorHeight: 120.25, transcriptHeight: 300.5, transcriptGap: 12)
    private var zeroVelocity: IslandLayout { IslandLayout(size: .zero, composerHeight: 0) }

    @Test func initializesAtRequestedLayoutAndRest() {
        expectSettled(IslandMotion(), at: IslandLayout(size: .zero))
        expectSettled(IslandMotion(layout: tall), at: tall)
    }

    @Test(arguments: [CGFloat(20), 40, 48, 56])
    func compactComposerAllocationsAnimateWithoutAMinimum(composerHeight: CGFloat) {
        let geometry = IslandGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), notchHeight: 32
        )
        let initial = geometry.expandedLayout(composerHeight: 0, naturalTranscriptHeight: 40)
        let target = geometry.expandedLayout(composerHeight: composerHeight, naturalTranscriptHeight: 40)
        var motion = IslandMotion(layout: initial)
        motion.retarget(to: target, expanded: true)
        for _ in 0..<1_200 {
            motion.advance(by: step)
            expectCoherentAllocations(motion, chrome: 60)
            if motion.isSettled { break }
        }
        expectSettled(motion, at: target)
        #expect(motion.layout.composerHeight == composerHeight)
        #expect(motion.layout.size.height == composerHeight + 110)
    }

    @Test(arguments: [true, false])
    func editorViewportAnimatesWithinAnUnchangedComposer(growing: Bool) {
        let initial = IslandLayout(size: CGSize(width: 500, height: 150),
                                   composerHeight: 40, editorHeight: growing ? 20 : 36,
                                   transcriptHeight: 50, transcriptGap: 12)
        var target = initial
        target.editorHeight = growing ? 36 : 20
        var motion = IslandMotion(layout: initial)
        expectContinuousRetarget(&motion, to: target, expanded: true)
        #expect(motion.velocity.editorHeight * (growing ? 1 : -1) > 0)
        var sawIntermediate = false
        for _ in 0..<1_200 {
            motion.advance(by: step)
            expectFinite(motion)
            #expect(motion.layout.size == initial.size)
            #expect(motion.layout.composerHeight == 40)
            #expect(motion.layout.transcriptHeight == initial.transcriptHeight)
            #expect(motion.layout.transcriptGap == initial.transcriptGap)
            #expect(motion.velocity.size == .zero)
            #expect(motion.velocity.composerHeight == 0)
            #expect(motion.velocity.transcriptHeight == 0)
            #expect(motion.velocity.transcriptGap == 0)
            sawIntermediate = sawIntermediate || (motion.layout.editorHeight > 20 && motion.layout.editorHeight < 36)
            if motion.isSettled { break }
        }
        #expect(sawIntermediate)
        expectSettled(motion, at: target)

        // Reversing an in-flight editor-only resize must preserve its velocity too.
        motion.retarget(to: initial, expanded: true)
        for _ in 0..<10 { motion.advance(by: step) }
        #expect(motion.velocity.editorHeight != 0)
        expectContinuousRetarget(&motion, to: target, expanded: true)
        advanceUntilSettled(&motion)
        #expect(motion.layout.composerHeight == 40)
        expectSettled(motion, at: target)
    }

    @Test func multilineSendShrinksComposerAndEditorOnTheSameClock() {
        let initial = IslandLayout(size: CGSize(width: 500, height: 300),
                                   composerHeight: 80, editorHeight: 80,
                                   transcriptHeight: 160, transcriptGap: 12)
        let target = IslandLayout(size: CGSize(width: 500, height: 260),
                                  composerHeight: 40, editorHeight: 20,
                                  transcriptHeight: 160, transcriptGap: 12)
        var motion = IslandMotion(layout: initial)
        expectContinuousRetarget(&motion, to: target, expanded: true)
        var sawIntermediate = false
        for _ in 0..<1_200 {
            motion.advance(by: step)
            expectFinite(motion)
            expectCoherentAllocations(motion, chrome: 48)
            let layout = motion.layout
            let velocity = motion.velocity
            #expect(layout.size.width == initial.size.width && velocity.size.width == 0)
            #expect(layout.transcriptHeight == initial.transcriptHeight && velocity.transcriptHeight == 0)
            #expect(layout.transcriptGap == initial.transcriptGap && velocity.transcriptGap == 0)
            sawIntermediate = sawIntermediate || (layout.editorHeight > 20 && layout.editorHeight < 80
                && layout.composerHeight > 40 && layout.composerHeight < 80)
            if motion.isSettled { break }
        }
        #expect(sawIntermediate)
        expectSettled(motion, at: target)
    }

    @Test(arguments: [true, false])
    func bothAxesHaveIndependentBoundedElasticMotion(expanding: Bool) {
        let start = expanding ? collapsed : open
        let target = expanding ? open : collapsed
        var motion = IslandMotion(layout: start)
        motion.retarget(to: target, expanded: expanding)
        #expect(!motion.isSettled)
        var sawIndependentAxes = false
        var sawIntermediate = false
        let origins = values(start)
        let destinations = values(target)

        for _ in 0..<1_200 {
            motion.advance(by: step)
            expectFinite(motion)
            let fractions = values(motion.layout).enumerated().map { index, value in
                (value - origins[index]) / (destinations[index] - origins[index])
            }
            for index in fractions.indices {
                #expect(fractions[index] >= -0.1 && fractions[index] < 1.1)
            }
            sawIndependentAxes = sawIndependentAxes || abs(fractions[0] - fractions[1]) > 0.01
            sawIntermediate = sawIntermediate || (0 < fractions[0] && fractions[0] < 1)
            if motion.isSettled { break }
        }

        #expect(sawIndependentAxes && sawIntermediate)
        expectSettled(motion, at: target)
        let settled = motion
        motion.advance(by: step)
        expectSameState(motion, settled)
    }

    @Test(arguments: [true, false])
    func midflightResizePreservesEveryPointAndVelocity(expanding: Bool) {
        var motion = IslandMotion(layout: expanding ? collapsed : open)
        motion.retarget(to: expanding ? open : collapsed, expanded: expanding)
        for _ in 0..<10 { motion.advance(by: step) }
        #expect(values(motion.velocity).allSatisfy { abs($0) > 0 })
        expectContinuousRetarget(&motion, to: tall, expanded: true)
        advanceUntilSettled(&motion)
        expectSettled(motion, at: tall)
    }

    @Test func heightRetargetKeepsActualFrameContinuousWhileClosingAndReopening() {
        var motion = IslandMotion(layout: open)
        motion.retarget(to: collapsed, expanded: false)
        for _ in 0..<8 { motion.advance(by: step) }
        // Content changes during closing, then again during reopening. Layout is
        // already in points: no live desired-height interpolation may move the frame.
        let closingTarget = IslandLayout(size: CGSize(width: 148, height: 44.5), composerHeight: 16.5)
        expectContinuousRetarget(&motion, to: closingTarget, expanded: false)
        for _ in 0..<4 { motion.advance(by: step) }
        expectContinuousRetarget(&motion, to: tall, expanded: true)
        for _ in 0..<6 { motion.advance(by: step) }
        let resized = IslandLayout(size: CGSize(width: tall.size.width, height: 400.25),
                                   composerHeight: 96.25, transcriptHeight: 244, transcriptGap: 12)
        expectContinuousRetarget(&motion, to: resized, expanded: true)
        advanceUntilSettled(&motion)
        expectSettled(motion, at: resized)
    }

    @Test(arguments: [true, false])
    func repeatedTargetsAreEquivalentToUninterruptedMotion(expanding: Bool) {
        var uninterrupted = IslandMotion(layout: expanding ? collapsed : tall)
        let target = expanding ? tall : collapsed
        uninterrupted.retarget(to: target, expanded: expanding)
        var reasserted = uninterrupted
        for _ in 0..<1_200 {
            reasserted.retarget(to: target, expanded: expanding)
            uninterrupted.advance(by: step)
            reasserted.advance(by: step)
            expectSameState(reasserted, uninterrupted)
            if uninterrupted.isSettled { break }
        }
        expectSettled(reasserted, at: target)
    }

    @Test func rapidRetargetsPreserveContinuityAndEventuallySettle() {
        var motion = IslandMotion(layout: collapsed)
        for index in 0..<80 {
            let expanded = index.isMultiple(of: 2)
            let before = motion
            motion.retarget(to: expanded ? tall : collapsed, expanded: expanded)
            expectSameState(motion, before)
            motion.advance(by: step)
            expectFinite(motion)
        }
        motion.retarget(to: open, expanded: true)
        advanceUntilSettled(&motion)
        expectSettled(motion, at: open)
    }

    @Test func viewportRedistributionRunsEvenWithUnchangedSurfaceSize() {
        var motion = IslandMotion(layout: open)
        let redistributed = IslandLayout(size: open.size, composerHeight: 120, transcriptHeight: 132)
        motion.retarget(to: redistributed, expanded: true)
        #expect(!motion.isSettled)
        #expect(motion.layout == open)
        var sawIntermediate = false
        for _ in 0..<1_200 {
            motion.advance(by: step)
            #expect(motion.layout.size == open.size)
            #expect(motion.velocity.size == .zero)
            expectCoherentAllocations(motion, chrome: 48)
            sawIntermediate = sawIntermediate || (motion.layout.composerHeight > 60 && motion.layout.composerHeight < 120)
            if motion.isSettled { break }
        }
        #expect(sawIntermediate)
        expectSettled(motion, at: redistributed)
        motion.retarget(to: open, expanded: true)
        for _ in 0..<10 { motion.advance(by: step) }
        #expect(motion.velocity.composerHeight != 0)
        expectContinuousRetarget(&motion, to: redistributed, expanded: true)
        advanceUntilSettled(&motion)
        expectSettled(motion, at: redistributed)
    }

    @Test(arguments: ["transcript", "gap"])
    func eachInternalAllocationCanKeepTheClockActive(field: String) {
        var motion = IslandMotion(layout: open)
        var target = open
        switch field {
        case "transcript": target.transcriptHeight += 24
        default: target.transcriptGap += 24
        }
        motion.retarget(to: target, expanded: true)
        #expect(!motion.isSettled)
        motion.advance(by: step)
        #expect(motion.layout.size == open.size)
        #expect(motion.layout != open && motion.layout != target)
        #expect(motion.velocity != zeroVelocity)
        #expect(!motion.isSettled)
        advanceUntilSettled(&motion)
        expectSettled(motion, at: target)
    }

    @Test func viewportSumsTrackOuterHeightFromOpenRestThroughRetargets() {
        var motion = IslandMotion(layout: open)
        let compact = IslandLayout(size: CGSize(width: 500, height: 140),
                                   composerHeight: 72, transcriptHeight: 12, transcriptGap: 8)
        for target in [tall, compact, open] {
            motion.retarget(to: target, expanded: true)
            for _ in 0..<13 {
                motion.advance(by: step)
                expectCoherentAllocations(motion, chrome: 48)
            }
        }
        for _ in 0..<1_200 {
            if motion.isSettled { break }
            motion.advance(by: step)
            expectCoherentAllocations(motion, chrome: 48)
        }
        expectSettled(motion, at: open)
    }

    @Test(arguments: [true, false])
    func reducedMotionSnapsAllTargetsAndStops(expanded: Bool) {
        var motion = IslandMotion(layout: collapsed)
        motion.retarget(to: tall, expanded: true)
        for _ in 0..<10 { motion.advance(by: step) }
        #expect(motion.velocity != zeroVelocity)
        let target = expanded ? tall : collapsed
        motion.retarget(to: target, expanded: expanded, animated: false)
        expectSettled(motion, at: target)
        for delta in [step, 0.25, 10.0] {
            motion.advance(by: delta)
            expectSettled(motion, at: target)
        }
    }

    @Test(arguments: [true, false])
    func allFieldsSettleTogetherWithSubpixelResidual(expanding: Bool) {
        var motion = IslandMotion(layout: expanding ? collapsed : tall)
        let target = expanding ? tall : collapsed
        motion.retarget(to: target, expanded: expanding)
        for _ in 0..<1_200 {
            let before = motion
            motion.advance(by: step)
            if motion.isSettled {
                for (value, destination) in zip(values(before.layout), values(target)) {
                    #expect(abs(value - destination) < 0.01)
                }
                #expect(values(before.velocity).allSatisfy { abs($0) < 0.05 })
                break
            }
        }
        expectSettled(motion, at: target)
    }

    @Test(arguments: [2.0, 60.0, Double.greatestFiniteMagnitude])
    func longFrameReachesRestWithoutNonfiniteValues(delta: TimeInterval) {
        var motion = IslandMotion(layout: collapsed)
        for (target, expanded) in [(tall, true), (collapsed, false)] {
            motion.retarget(to: target, expanded: expanded)
            motion.advance(by: step)
            motion.advance(by: delta)
            expectFinite(motion)
            expectSettled(motion, at: target)
        }
    }

    @Test(arguments: [true, false])
    func missedFramesMatchTheSameElapsedTimeInSmallSteps(expanding: Bool) {
        var missed = IslandMotion(layout: expanding ? collapsed : tall)
        let target = expanding ? tall : collapsed
        missed.retarget(to: target, expanded: expanding)
        for _ in 0..<7 { missed.advance(by: step) }
        var sampled = missed
        missed.advance(by: step * 30)
        for _ in 0..<30 { sampled.advance(by: step) }
        for (lhs, rhs) in zip(values(missed.layout) + values(missed.velocity),
                              values(sampled.layout) + values(sampled.velocity)) {
            #expect(abs(lhs - rhs) < tolerance)
        }
        advanceUntilSettled(&missed)
        advanceUntilSettled(&sampled)
        expectSettled(missed, at: target)
        expectSettled(sampled, at: target)
    }

    @Test func invalidDurationsLeaveAllStateUntouched() {
        var motion = IslandMotion(layout: collapsed)
        motion.retarget(to: tall, expanded: true)
        motion.advance(by: step)
        let before = motion
        for delta in [0.0, -step, Double.nan, Double.infinity, -Double.infinity] {
            motion.advance(by: delta)
            expectSameState(motion, before)
            #expect(motion.targetLayout == before.targetLayout)
            #expect(motion.isSettled == before.isSettled)
        }
        advanceUntilSettled(&motion)
        expectSettled(motion, at: tall)
    }

    @Test func invalidTargetsAreRejectedWithoutChangingTrajectory() {
        var motion = IslandMotion(layout: collapsed)
        motion.retarget(to: tall, expanded: true)
        motion.advance(by: step)
        let before = motion
        for invalidValue in [-1.0, Double.nan, Double.infinity, -Double.infinity] {
            for field in 0..<6 {
                var invalid = tall
                switch field {
                case 0: invalid.size.width = CGFloat(invalidValue)
                case 1: invalid.size.height = CGFloat(invalidValue)
                case 2: invalid.composerHeight = CGFloat(invalidValue)
                case 3: invalid.editorHeight = CGFloat(invalidValue)
                case 4: invalid.transcriptHeight = CGFloat(invalidValue)
                default: invalid.transcriptGap = CGFloat(invalidValue)
                }
                motion.retarget(to: invalid, expanded: false, animated: false)
                expectSameState(motion, before)
                #expect(motion.targetLayout == before.targetLayout)
                expectSettled(IslandMotion(layout: invalid), at: IslandLayout(size: .zero))
            }
        }
        var uninterrupted = before
        motion.advance(by: step)
        uninterrupted.advance(by: step)
        expectSameState(motion, uninterrupted)
    }

    @Test func revealDependsOnlyOnHorizontalRoomAndHasSmoothBoundedEndpoints() {
        let expanded = CGSize(width: 500, height: 300)
        var previous = 0.0
        var sawPartialReveal = false
        for width in [350.0, 420, 450, 480, 500, 550] {
            let visibility = IslandMotion.contentVisibility(surfaceSize: CGSize(width: width, height: 1),
                                                            expandedSize: expanded)
            #expect(visibility >= previous && visibility <= 1)
            for (height, targetHeight) in [(0.0, 1_000.0), (1_000.0, 28.0)] {
                #expect(IslandMotion.contentVisibility(surfaceSize: CGSize(width: width, height: height),
                                                       expandedSize: CGSize(width: 500, height: targetHeight)) == visibility)
            }
            sawPartialReveal = sawPartialReveal || (visibility > 0 && visibility < 1)
            previous = visibility
        }
        func reveal(_ width: Double) -> Double {
            IslandMotion.contentVisibility(surfaceSize: CGSize(width: width, height: 1), expandedSize: expanded)
        }
        #expect(sawPartialReveal)
        #expect(reveal(350) == 0)
        #expect(reveal(500) == 1)
        #expect(abs(reveal(450.01) - reveal(450)) < 0.01)
    }

    @Test func openContentStaysVisibleThroughoutHeightResize() {
        var motion = IslandMotion(layout: open)
        let taller = IslandLayout(size: CGSize(width: open.size.width, height: tall.size.height),
                                  composerHeight: tall.composerHeight, editorHeight: tall.editorHeight,
                                  transcriptHeight: tall.transcriptHeight, transcriptGap: tall.transcriptGap)
        motion.retarget(to: taller, expanded: true)
        for _ in 0..<1_200 {
            motion.advance(by: step)
            #expect(IslandMotion.contentVisibility(surfaceSize: motion.layout.size,
                                                   expandedSize: motion.targetLayout.size) == 1)
            if motion.isSettled { break }
        }
        expectSettled(motion, at: taller)
    }

    @Test func shapeSamplesStayWithinBoundsAndContainCenter() {
        for rect in [CGRect(x: 0, y: 0, width: 148, height: 28),
                     CGRect(x: 17, y: -45, width: 500, height: 292),
                     CGRect(x: 0, y: 0, width: 8, height: 6)] {
            for progress in [-1.0, 0.0, 0.25, 0.5, 1.0, 2.0] {
                let path = IslandShape(progress: progress).path(in: rect)
                #expect(!path.isEmpty)
                #expect(path.boundingRect == rect)
                #expect(path.contains(CGPoint(x: rect.midX, y: rect.midY)))
            }
        }
    }

    @Test func shapeHasConcaveShouldersAndRoundedLowerCorners() {
        let rect = CGRect(x: 0, y: 0, width: 500, height: 300)
        let path = IslandShape(progress: 1.0).path(in: rect)
        let samples: [(CGFloat, CGFloat, Bool)] = [
            (8, 1, true), (8, 6, false),
            (20, rect.maxY - 2, false), (34, rect.maxY - 2, true),
        ]
        for (inset, y, contained) in samples {
            for x in [rect.minX + inset, rect.maxX - inset] {
                #expect(path.contains(CGPoint(x: x, y: y)) == contained)
            }
        }
    }

    @Test func shapeProgressChangesShouldersAndLowerCorners() {
        let rect = CGRect(x: 0, y: 0, width: 500, height: 300)
        let collapsed = IslandShape(progress: 0.0).path(in: rect)
        let midway = IslandShape(progress: 0.5).path(in: rect)
        let expanded = IslandShape(progress: 1.0).path(in: rect)
        #expect(collapsed != midway)
        #expect(midway != expanded)
        for path in [collapsed, midway, expanded] {
            #expect(path.boundingRect == rect)
            #expect(path.contains(CGPoint(x: rect.midX, y: rect.midY)))
        }
    }

    private func values(_ layout: IslandLayout) -> [Double] {
        [Double(layout.size.width), Double(layout.size.height), Double(layout.composerHeight),
         Double(layout.editorHeight), Double(layout.transcriptHeight), Double(layout.transcriptGap)]
    }

    private func frame(_ layout: IslandLayout) -> CGRect {
        CGRect(x: 756 - layout.size.width / 2, y: 982 - layout.size.height,
               width: layout.size.width, height: layout.size.height)
    }

    private func expectContinuousRetarget(_ motion: inout IslandMotion, to target: IslandLayout, expanded: Bool) {
        let before = motion
        let beforeFrame = frame(before.layout)
        motion.retarget(to: target, expanded: expanded)
        expectSameState(motion, before)
        #expect(motion.targetLayout == target)
        #expect(frame(motion.layout) == beforeFrame)
        #expect(!motion.isSettled)
        motion.advance(by: step)
        expectFinite(motion)
    }

    private func advanceUntilSettled(_ motion: inout IslandMotion) {
        for _ in 0..<1_200 {
            if motion.isSettled { break }
            motion.advance(by: step)
            expectFinite(motion)
        }
        #expect(motion.isSettled)
    }

    private func expectCoherentAllocations(_ motion: IslandMotion, chrome: Double) {
        let layout = motion.layout
        let velocity = motion.velocity
        #expect(abs(Double(layout.size.height - layout.composerHeight - layout.transcriptHeight - layout.transcriptGap) - chrome) < tolerance)
        #expect(abs(Double(velocity.size.height - velocity.composerHeight - velocity.transcriptHeight - velocity.transcriptGap)) < tolerance)
    }

    private func expectFinite(_ motion: IslandMotion) {
        #expect((values(motion.layout) + values(motion.velocity)).allSatisfy { $0.isFinite })
    }

    private func expectSameState(_ motion: IslandMotion, _ other: IslandMotion) {
        #expect(motion.layout == other.layout)
        #expect(motion.velocity == other.velocity)
    }

    private func expectSettled(_ motion: IslandMotion, at target: IslandLayout) {
        #expect(motion.isSettled)
        #expect(motion.layout == target)
        #expect(motion.targetLayout == target)
        #expect(motion.velocity == zeroVelocity)
    }
}
