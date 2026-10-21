import CoreGraphics
import Foundation
import Testing
@testable import Pocket

struct IslandFrameTests {
    private let tolerance: CGFloat = 1e-9

    @Test(arguments: [CGPoint(x: 756, y: 982), CGPoint(x: -756, y: 0), CGPoint(x: -300.25, y: -40.25)])
    func paintedBottomRemainsContinuousAcrossIntegralWindowSteps(anchor: CGPoint) {
        let heights: [CGFloat] = [38.8, 38.001, 38]
        var previousBottom: CGFloat?
        var previousHeight: CGFloat?

        for height in heights {
            let surface = CGRect(x: anchor.x - 112.125, y: anchor.y - height, width: 224.25, height: height)
            let frame = IslandFrame(surface: surface)
            let host = frame.window
            let local = frame.localSurface(in: host)
            let paintedBottom = host.maxY - local.maxY

            #expect(frame.surface == surface)
            #expect(host == surface.integral)
            #expect(host.contains(surface))
            #expect(local.size == surface.size)
            #expect(abs(paintedBottom - surface.minY) < tolerance)
            #expect(abs(host.maxY - local.minY - anchor.y) < tolerance)
            #expect(abs(host.minX + local.midX - anchor.x) < tolerance)
            expectTightMargins(local, inside: host.size)

            if anchor.y.rounded() == anchor.y {
                #expect(host.height == (height > 38 ? 39 : 38))
            }
            if let previousBottom, let previousHeight {
                #expect(abs((paintedBottom - previousBottom) - (previousHeight - height)) < tolerance)
            }
            previousBottom = paintedBottom
            previousHeight = height
        }
    }

    @Test func layoutUsesActualAcceptedWindowRatherThanRequestedWindow() {
        let surface = CGRect(x: -1200.25, y: -38.001, width: 224.5, height: 38.001)
        let frame = IslandFrame(surface: surface)
        // Model a native window accepting different bounds. No window ordering needed.
        let actual = frame.window.insetBy(dx: -1, dy: -2).offsetBy(dx: -0.25, dy: 0.5)
        let local = frame.localSurface(in: actual)

        #expect(local.size == surface.size)
        #expect(abs(actual.minX + local.minX - surface.minX) < tolerance)
        #expect(abs(actual.maxY - local.minY - surface.maxY) < tolerance)
        #expect(abs(actual.maxY - local.maxY - surface.minY) < tolerance)
    }

    @Test func integralHostingUsesPointsWithoutRetinaPixelSnapping() {
        let surface = CGRect(x: -10.125, y: -38.001, width: 224.25, height: 38.001)
        let frame = IslandFrame(surface: surface)
        let local = frame.localSurface(in: frame.window)

        #expect(frame.window == CGRect(x: -11, y: -39, width: 226, height: 39))
        #expect(local.width == 224.25)
        #expect(local.height == 38.001)
        #expect(local.minX == 0.875)
        #expect(local.minY == 0)
        expectTightMargins(local, inside: frame.window.size)
    }

    @Test func independentAxesDoNotDriveEachOther() {
        let geometry = notchedGeometry
        let collapsed = geometry.frame(expanded: false, composerHeight: 60)
        let expanded = geometry.frame(expanded: true, composerHeight: 60)
        let wide = geometry.frame(widthProgress: 1, heightProgress: 0, composerHeight: 60)
        let tall = geometry.frame(widthProgress: 0, heightProgress: 1, composerHeight: 60)
        let mixed = geometry.frame(widthProgress: 0.7, heightProgress: 0.3, composerHeight: 60)

        #expect(wide.size == CGSize(width: expanded.width, height: collapsed.height))
        #expect(tall.size == CGSize(width: collapsed.width, height: expanded.height))
        #expect(mixed.width == geometry.frame(progress: 0.7, composerHeight: 60).width)
        #expect(mixed.height == geometry.frame(progress: 0.3, composerHeight: 60).height)
        for frame in [wide, tall, mixed] {
            #expect(frame.maxY == collapsed.maxY)
            #expect(frame.midX == collapsed.midX)
        }
    }

    @Test(arguments: [false, true])
    func twoAxisEndpointsAgreeWithBooleanAndUniformFrames(includesError: Bool) {
        let geometry = notchedGeometry
        for progress in [0.0, 0.5, 1.0] {
            let independent = geometry.frame(
                widthProgress: progress, heightProgress: progress,
                composerHeight: 140, transcriptHeight: 112, includesError: includesError
            )
            #expect(independent == geometry.frame(
                progress: progress, composerHeight: 140, transcriptHeight: 112, includesError: includesError
            ))
            if progress == 0 || progress == 1 {
                #expect(independent == geometry.frame(
                    expanded: progress == 1, composerHeight: 140,
                    transcriptHeight: 112, includesError: includesError
                ))
            }
        }
        #expect(geometry.frame(progress: -0.025, composerHeight: 60) == geometry.frame(expanded: false, composerHeight: 60))
        #expect(geometry.frame(progress: 1.025, composerHeight: 60) == geometry.frame(expanded: true, composerHeight: 60))
    }

    @Test func springCanOvershootBothEndpointsWithoutLosingAnchor() {
        let geometry = notchedGeometry
        let collapsed = geometry.frame(expanded: false, composerHeight: 60)
        let expanded = geometry.frame(expanded: true, composerHeight: 60)
        let opening = geometry.frame(widthProgress: 1.025, heightProgress: 1.025, composerHeight: 60)
        let closing = geometry.frame(widthProgress: -0.025, heightProgress: -0.025, composerHeight: 60)

        #expect(opening.width > expanded.width)
        #expect(opening.height > expanded.height)
        #expect(closing.width < collapsed.width)
        #expect(closing.height < collapsed.height)
        #expect(closing.width >= geometry.notchWidth)
        for frame in [opening, closing] {
            #expect(frame.maxY == collapsed.maxY)
            #expect(frame.midX == collapsed.midX)
            #expect(geometry.screenFrame.contains(frame))
        }
    }

    @Test func interruptedSpringExcursionsStayFiniteAndInsideSelectedScreen() {
        let geometries = [
            notchedGeometry,
            IslandGeometry(screenFrame: CGRect(x: -1920, y: 40, width: 1920, height: 1080)),
            IslandGeometry(screenFrame: CGRect(x: 100, y: -300, width: 320, height: 80)),
            IslandGeometry(screenFrame: CGRect(x: 50, y: 80, width: 120, height: 24), notchHeight: 32),
        ]
        var excursions: [(Double, Double)] = [
            (0, 0), (1, 1), (-0.05, 1.05), (1.05, -0.05), (-100, 100), (100, -100),
        ]
        for invalid in [Double.nan, .infinity, -.infinity] {
            excursions.append((invalid, 0.5))
            excursions.append((0.5, invalid))
        }
        for geometry in geometries {
            for (width, height) in excursions {
                let frame = geometry.frame(
                    widthProgress: width, heightProgress: height,
                    composerHeight: 140, transcriptHeight: 10_000, includesError: true
                )
                #expect(frame.width.isFinite && frame.height.isFinite)
                #expect(frame.width > 0 && frame.height > 0)
                #expect(frame.width >= min(geometry.notchWidth, geometry.screenFrame.width))
                #expect(geometry.screenFrame.contains(frame))
                #expect(frame.maxY == geometry.screenFrame.maxY)
                #expect(abs(frame.midX - geometry.screenFrame.midX) < 1e-8)
            }
        }
    }

    private var notchedGeometry: IslandGeometry {
        IslandGeometry(
            screenFrame: CGRect(x: -1512, y: -982, width: 1512, height: 982),
            notchHeight: 32,
            topLeftArea: CGRect(x: -1512, y: -32, width: 660, height: 32),
            topRightArea: CGRect(x: -660, y: -32, width: 660, height: 32)
        )
    }

    private func expectTightMargins(_ surface: CGRect, inside host: CGSize) {
        let margins = [surface.minX, surface.minY, host.width - surface.maxX, host.height - surface.maxY]
        for margin in margins {
            #expect(margin >= 0)
            #expect(margin < 1)
        }
    }
}
