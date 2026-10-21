import AppKit
import Testing
@testable import Pocket

struct IslandGeometryTests {
    @Test func expansionPreservesTopEdgeAndCenterOnExternalDisplay() {
        let screen = CGRect(x: -1920, y: 40, width: 1920, height: 1080)
        let geometry = IslandGeometry(screenFrame: screen)
        let collapsed = geometry.frame(expanded: false, composerHeight: 60)
        let expanded = geometry.frame(expanded: true, composerHeight: 60)
        #expect(collapsed.size == CGSize(width: 96, height: 24))
        #expect(collapsed.maxY == screen.maxY)
        #expect(expanded.maxY == screen.maxY)
        #expect(collapsed.midX == expanded.midX)
        #expect(expanded.midX == screen.midX)
        #expect(screen.contains(expanded))
    }

    @Test func closedIslandHasFourPointWingsAndNoLowerLip() {
        let geometry = IslandGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            notchHeight: 32,
            topLeftArea: CGRect(x: 0, y: 950, width: 660, height: 32),
            topRightArea: CGRect(x: 852, y: 950, width: 660, height: 32)
        )
        let collapsed = geometry.frame(expanded: false, composerHeight: 60)
        let expanded = geometry.frame(expanded: true, composerHeight: 60)
        #expect(geometry.notchWidth == 192)
        #expect(collapsed.size == CGSize(width: 200, height: 32))
        #expect(collapsed.minX == CGFloat(656))
        #expect(collapsed.maxX == CGFloat(856))
        #expect(collapsed.midX == 756)
        #expect(collapsed.maxY == 982)
        #expect(expanded.maxY == collapsed.maxY)
        #expect(expanded.size == CGSize(width: 460, height: 120))
    }

    @Test func notchGeometryUsesScreenCoordinatesOnOffsetDisplay() {
        let geometry = IslandGeometry(
            screenFrame: CGRect(x: -1512, y: -982, width: 1512, height: 982),
            notchHeight: 32,
            topLeftArea: CGRect(x: -1512, y: -32, width: 660, height: 32),
            topRightArea: CGRect(x: -660, y: -32, width: 660, height: 32)
        )
        #expect(geometry.frame(expanded: false, composerHeight: 60).midX == -756)
        #expect(geometry.frame(expanded: true, composerHeight: 60).maxY == 0)
    }

    @Test func safeAreaWithoutAuxiliaryRectsHasNotchFallback() {
        let geometry = IslandGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), notchHeight: 32
        )
        #expect(geometry.notchWidth == 180)
        #expect(geometry.frame(expanded: false, composerHeight: 60).midX == 756)
    }

    @Test func expandedIslandFitsSmallDisplay() {
        let screen = CGRect(x: 100, y: -300, width: 320, height: 80)
        let geometry = IslandGeometry(screenFrame: screen)
        #expect(geometry.frame(expanded: true, composerHeight: 60) == screen)
    }

    @Test func compactCaptureGrowsWithoutMovingItsTopAnchor() {
        let geometry = IslandGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), notchHeight: 32
        )
        let compact = geometry.frame(expanded: true, composerHeight: 60)
        let grown = geometry.frame(expanded: true, composerHeight: 140)
        #expect(compact.size == CGSize(width: 460, height: 120))
        #expect(grown.height == 200)
        #expect(compact.maxY == grown.maxY)
        #expect(compact.midX == grown.midX)
        #expect(compact.width == grown.width)
    }

    @Test func compactCaptureReservesSpaceForShortcutErrors() {
        let geometry = IslandGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let normal = geometry.expandedSize(composerHeight: 40)
        let withError = geometry.expandedSize(composerHeight: 40, includesError: true)
        #expect(normal.height == 68)
        #expect(withError.height - normal.height == CGFloat(48))
        #expect(geometry.expandedSize(composerHeight: 0).height == 28)
    }

    @Test func conversationAddsBoundedSpaceWithoutMovingTopAnchor() {
        let screen = CGRect(x: -1512, y: -982, width: 1512, height: 982)
        let geometry = IslandGeometry(screenFrame: screen, notchHeight: 32)
        let compact = geometry.frame(expanded: true, composerHeight: 60)
        let conversation = geometry.frame(expanded: true, composerHeight: 60, transcriptHeight: 112)
        #expect(conversation.height == 242)
        #expect(conversation.maxY == compact.maxY)
        #expect(conversation.midX == compact.midX)
        for progress in [0.0, 0.25, 0.5, 1.0] {
            let frame = geometry.frame(progress: progress, composerHeight: 60, transcriptHeight: 112)
            #expect(frame.maxY == screen.maxY)
            #expect(screen.contains(frame))
        }
        let small = IslandGeometry(screenFrame: CGRect(x: 0, y: 0, width: 320, height: 200))
        #expect(small.expandedSize(composerHeight: 60, transcriptHeight: 112).height == 200)
    }
}
