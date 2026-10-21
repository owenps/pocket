import CoreGraphics
import Testing
@testable import Pocket

struct IslandLayoutTests {
    private let geometry = IslandGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), notchHeight: 32
    )

    @Test func shortReplyUsesItsContentHeightRatherThanTheCap() {
        let layout = geometry.expandedLayout(composerHeight: 60, naturalTranscriptHeight: 20)
        #expect(layout.transcriptHeight == 20)
        #expect(layout.transcriptGap == 10)
        #expect(layout.size == CGSize(width: 460, height: 150))
    }

    @Test func emptyConversationDoesNotReserveSpaceOrGap() {
        let layout = geometry.expandedLayout(composerHeight: 60)
        #expect(layout.transcriptHeight == 0)
        #expect(layout.transcriptGap == 0)
        #expect(layout.size == CGSize(width: 460, height: 120))
    }

    @Test func longConversationCapsTheViewportWithoutLimitingTheDocument() {
        let layout = geometry.expandedLayout(composerHeight: 60, naturalTranscriptHeight: 2_000)
        #expect(layout.transcriptHeight == 112)
        #expect(layout.size == CGSize(width: 460, height: 242))
        #expect(geometry.expandedSize(composerHeight: 60, transcriptHeight: 200).height == 330)
    }

    @Test func viewportSharesAvailableScreenSpaceWithTheComposer() {
        let small = IslandGeometry(screenFrame: CGRect(x: 0, y: 0, width: 320, height: 150), notchHeight: 32)
        let layout = small.expandedLayout(composerHeight: 60, naturalTranscriptHeight: 200)
        #expect(layout.transcriptHeight == 20)
        #expect(layout.size == CGSize(width: 320, height: 150))
        let composerGrows = small.expandedLayout(composerHeight: 100, naturalTranscriptHeight: 200)
        #expect(composerGrows.transcriptHeight == 0)
        #expect(composerGrows.transcriptGap == 0)
        #expect(composerGrows.size.height == 150)
    }

    @Test(arguments: [CGFloat(20), 48])
    func compactComposerUsesFinalRowHeightWithoutAMinimum(composerHeight: CGFloat) {
        let layout = geometry.expandedLayout(composerHeight: composerHeight)
        #expect(layout.composerHeight == composerHeight)
        #expect(layout.size == CGSize(width: 460, height: composerHeight + 28 + 32))
        #expect(layout.transcriptHeight == 0)
        #expect(layout.transcriptGap == 0)
        #expect(geometry.expandedSize(composerHeight: composerHeight) == layout.size)
        #expect(geometry.frame(expanded: true, composerHeight: composerHeight).maxY == 982)

        let external = IslandGeometry(screenFrame: geometry.screenFrame)
        #expect(external.expandedSize(composerHeight: composerHeight).height == composerHeight + 28)
    }

    @Test func errorAndComposerShareTheRemainingTranscriptBudget() {
        let small = IslandGeometry(screenFrame: CGRect(x: 0, y: 0, width: 320, height: 150), notchHeight: 32)
        let compact = small.expandedLayout(composerHeight: 20, naturalTranscriptHeight: 200)
        let withError = small.expandedLayout(
            composerHeight: 20, naturalTranscriptHeight: 200, includesError: true
        )
        let exhausted = small.expandedLayout(
            composerHeight: 48, naturalTranscriptHeight: 200, includesError: true
        )
        #expect(compact.composerHeight == 20 && withError.composerHeight == 20)
        #expect(compact.transcriptHeight > withError.transcriptHeight)
        #expect(withError.transcriptHeight > 0 && withError.transcriptGap > 0)
        #expect(exhausted.composerHeight == 48)
        #expect(exhausted.transcriptHeight == 0 && exhausted.transcriptGap == 0)
        for layout in [compact, withError, exhausted] {
            #expect(layout.size.height <= small.screenFrame.height)
        }
    }

    @Test(arguments: [false, true])
    func expandedTargetAndResolvedBodyShareTheirBudget(includesError: Bool) {
        let layout = geometry.expandedLayout(
            composerHeight: 60, editorHeight: 28,
            naturalTranscriptHeight: 20, includesError: includesError
        )
        let body = IslandGeometry.bodyLayout(sample: layout, notchHeight: 32, includesError: includesError)
        #expect(layout.size.width == IslandGeometry.preferredExpandedWidth)
        #expect(layout.editorHeight == 28)
        #expect(body.height == layout.size.height)
        #expect(body.horizontalInset == 24)
        #expect(body.topInset == 44 && body.bottomInset == 16)
        #expect(body.maskTopInset == 40)
        #expect(body.errorHeight == (includesError ? 38 : 0))
        #expect(body.errorTopGap == (includesError ? 10 : 0))
        #expect(body.height == (includesError ? 198 : 150))
    }

    @Test func tinyScreensCapOnlyTheOuterSizeAndCollapsePreservesBodyAllocations() {
        let small = IslandGeometry(screenFrame: CGRect(x: 0, y: 0, width: 320, height: 100), notchHeight: 32)
        let layout = small.expandedLayout(
            composerHeight: 180, editorHeight: 140, naturalTranscriptHeight: 200, includesError: true
        )
        let body = IslandGeometry.bodyLayout(sample: layout, notchHeight: 32, includesError: true)
        #expect(layout.size == CGSize(width: 320, height: 100))
        #expect(body.composerHeight == 180 && body.editorHeight == 140)
        #expect(body.transcriptHeight == 0 && body.transcriptGap == 0)
        #expect(body.height == 288)

        var collapsed = layout
        collapsed.size = small.collapsedSize
        let frozen = IslandGeometry.bodyLayout(sample: collapsed, notchHeight: 32, includesError: true)
        #expect(frozen.height == body.height)
        #expect(frozen.editorFrameHeight == body.editorFrameHeight)
        // Errors remain live even when the allocations were cached for collapse.
        #expect(IslandGeometry.bodyLayout(sample: collapsed, notchHeight: 32).height == 240)
    }

    @Test func sampledOvershootClampsEachAllocationIndependently() {
        let overshoot = IslandLayout(
            size: CGSize(width: 500, height: 600), composerHeight: -20, editorHeight: 180,
            transcriptHeight: 150, transcriptGap: 14
        )
        let body = IslandGeometry.bodyLayout(sample: overshoot)
        #expect(body.composerHeight == 0)
        #expect(body.editorHeight == 140 && body.editorFrameHeight == 0)
        #expect(body.transcriptHeight == 112 && body.transcriptGap == 10)

        let residual = IslandLayout(
            size: .zero, composerHeight: 26, editorHeight: -4, transcriptHeight: -8, transcriptGap: 6
        )
        let residualBody = IslandGeometry.bodyLayout(sample: residual)
        #expect(residualBody.editorHeight == 0 && residualBody.editorFrameHeight == 0)
        #expect(residualBody.transcriptHeight == 0 && residualBody.transcriptGap == 6)
        #expect(residualBody.height == 60)
        var negativeGap = residual
        negativeGap.transcriptGap = -3
        #expect(IslandGeometry.bodyLayout(sample: negativeGap).transcriptGap == 0)
    }

    @Test func editorViewportCapIsSharedByTargetsAndResolvedFrames() {
        for (height, expected) in [(CGFloat(-10), CGFloat(0)), (28, 28), (200, 140)] {
            #expect(IslandGeometry.editorViewportHeight(height) == expected)
            let layout = geometry.expandedLayout(composerHeight: 48, editorHeight: height)
            let body = IslandGeometry.bodyLayout(sample: layout, notchHeight: 32)
            #expect(layout.editorHeight == expected && body.editorHeight == expected)
            #expect(body.editorFrameHeight == min(expected, 48))
            #expect(body.height == 108)
        }
    }

    @Test func invalidMeasurementsCannotCreateNonfiniteFrames() {
        for height in [CGFloat.nan, .infinity, -.infinity, -10] {
            let layout = geometry.expandedLayout(composerHeight: height, editorHeight: height, naturalTranscriptHeight: height)
            #expect(layout == geometry.expandedLayout(composerHeight: 0))
            #expect(layout.composerHeight == 0)
            #expect(layout.transcriptHeight == 0)
        }
    }
}
