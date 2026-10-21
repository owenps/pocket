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

    @Test func invalidMeasurementsCannotCreateNonfiniteFrames() {
        for height in [CGFloat.nan, .infinity, -.infinity, -10] {
            let layout = geometry.expandedLayout(composerHeight: height, naturalTranscriptHeight: height)
            #expect(layout == geometry.expandedLayout(composerHeight: 0))
            #expect(layout.composerHeight == 0)
            #expect(layout.transcriptHeight == 0)
        }
    }
}
