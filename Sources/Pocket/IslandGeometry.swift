import CoreGraphics
import Foundation

/// Screen-space points, never backing pixels. Expansion preserves the top anchor.
struct IslandGeometry {
    let screenFrame: CGRect
    let notchHeight: CGFloat
    let notchWidth: CGFloat
    private let centerX: CGFloat

    init(
        screenFrame: CGRect,
        notchHeight: CGFloat = 0,
        topLeftArea: CGRect? = nil,
        topRightArea: CGRect? = nil
    ) {
        self.screenFrame = screenFrame
        self.notchHeight = min(max(0, notchHeight), screenFrame.height)
        if notchHeight > 0 {
            if let left = topLeftArea, let right = topRightArea, right.minX > left.maxX {
                notchWidth = right.minX - left.maxX
                centerX = (left.maxX + right.minX) / 2
            } else {
                notchWidth = min(180, screenFrame.width)
                centerX = screenFrame.midX
            }
        } else {
            notchWidth = 0
            centerX = screenFrame.midX
        }
    }

    var collapsedSize: CGSize {
        CGSize(
            width: min(notchHeight > 0 ? notchWidth + 8 : 96, screenFrame.width),
            height: min(notchHeight > 0 ? notchHeight : 24, screenFrame.height)
        )
    }

    func expandedSize(
        composerHeight: CGFloat, transcriptHeight: CGFloat = 0, includesError: Bool = false
    ) -> CGSize {
        let history = transcriptHeight > 0 ? transcriptHeight + 10 : 0
        return CGSize(
            width: min(max(460, collapsedSize.width), screenFrame.width),
            // Composer and top/bottom padding only: no titlebar or status footer.
            height: min(composerHeight + 28 + notchHeight + history + (includesError ? 48 : 0), screenFrame.height)
        )
    }

    func expandedLayout(
        composerHeight: CGFloat, naturalTranscriptHeight: CGFloat = 0, includesError: Bool = false
    ) -> IslandLayout {
        let composer = composerHeight.isFinite ? max(0, composerHeight) : 0
        let natural = naturalTranscriptHeight.isFinite ? max(0, naturalTranscriptHeight) : 0
        let baseHeight = expandedSize(composerHeight: composer, includesError: includesError).height
        let transcript = min(112, natural, max(0, screenFrame.height - baseHeight - 10))
        return IslandLayout(
            size: expandedSize(composerHeight: composer, transcriptHeight: transcript, includesError: includesError),
            composerHeight: composer, transcriptHeight: transcript, transcriptGap: transcript > 0 ? 10 : 0
        )
    }

    func frame(
        expanded: Bool, composerHeight: CGFloat, transcriptHeight: CGFloat = 0, includesError: Bool = false
    ) -> CGRect {
        frame(
            progress: expanded ? 1 : 0, composerHeight: composerHeight,
            transcriptHeight: transcriptHeight, includesError: includesError
        )
    }

    func frame(
        progress: Double, composerHeight: CGFloat, transcriptHeight: CGFloat = 0, includesError: Bool = false
    ) -> CGRect {
        let progress = min(1, max(0, progress))
        return frame(
            widthProgress: progress, heightProgress: progress, composerHeight: composerHeight,
            transcriptHeight: transcriptHeight, includesError: includesError
        )
    }

    func frame(
        widthProgress: Double, heightProgress: Double,
        composerHeight: CGFloat, transcriptHeight: CGFloat = 0, includesError: Bool = false
    ) -> CGRect {
        // Preserve the spring's small overshoot; bound interrupted/reversed motion.
        let widthProgress = widthProgress.isNaN ? 0 : min(1.06, max(-0.06, widthProgress))
        let heightProgress = heightProgress.isNaN ? 0 : min(1.06, max(-0.06, heightProgress))
        let expanded = expandedSize(
            composerHeight: composerHeight, transcriptHeight: transcriptHeight, includesError: includesError
        )
        let collapsed = collapsedSize
        let size = CGSize(
            width: min(screenFrame.width, max(
                max(notchWidth, collapsed.width * 0.75),
                collapsed.width + (expanded.width - collapsed.width) * widthProgress
            )),
            height: min(screenFrame.height, max(
                collapsed.height * 0.75,
                collapsed.height + (expanded.height - collapsed.height) * heightProgress
            ))
        )
        return frame(size: size)
    }

    /// Anchor point-valued motion without rescaling it against a moving target.
    func frame(size: CGSize) -> CGRect {
        let size = CGSize(
            width: min(screenFrame.width, max(max(notchWidth, collapsedSize.width * 0.75), size.width)),
            height: min(screenFrame.height, max(collapsedSize.height * 0.75, size.height))
        )
        let x = min(max(centerX - size.width / 2, screenFrame.minX), screenFrame.maxX - size.width)
        return CGRect(x: x, y: screenFrame.maxY - size.height, width: size.width, height: size.height)
    }
}
