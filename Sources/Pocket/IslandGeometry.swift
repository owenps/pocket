import CoreGraphics
import Foundation

/// Screen-space points, never backing pixels. Expansion preserves the top anchor.
struct IslandGeometry {
    static let preferredExpandedWidth: CGFloat = 460
    static let maximumEditorHeight: CGFloat = 140
    private static let maximumTranscriptHeight: CGFloat = 112
    private static let maximumTranscriptGap: CGFloat = 10

    struct BodyLayout {
        let horizontalInset: CGFloat
        let topInset: CGFloat
        let bottomInset: CGFloat
        let maskTopInset: CGFloat
        let errorHeight: CGFloat
        let errorTopGap: CGFloat
        let editorHeight: CGFloat
        let composerHeight: CGFloat
        let transcriptHeight: CGFloat
        let transcriptGap: CGFloat

        var editorFrameHeight: CGFloat { min(editorHeight, composerHeight) }
        var height: CGFloat {
            topInset + bottomInset + errorHeight + errorTopGap
                + composerHeight + transcriptHeight + transcriptGap
        }

        fileprivate init(
            composerHeight: CGFloat, editorHeight: CGFloat = 0,
            transcriptHeight: CGFloat = 0, transcriptGap: CGFloat = 0,
            notchHeight: CGFloat, includesError: Bool
        ) {
            horizontalInset = 24
            topInset = notchHeight + 12
            bottomInset = 16
            maskTopInset = notchHeight + 8
            errorHeight = includesError ? 38 : 0
            errorTopGap = includesError ? 10 : 0
            self.editorHeight = editorHeight
            self.composerHeight = composerHeight
            self.transcriptHeight = transcriptHeight
            self.transcriptGap = transcriptGap
        }
    }

    static func editorViewportHeight(_ height: CGFloat) -> CGFloat {
        min(maximumEditorHeight, max(0, height))
    }

    /// Resolve sampled allocations without changing the spring or its outer size.
    static func bodyLayout(
        sample: IslandLayout, notchHeight: CGFloat = 0, includesError: Bool = false
    ) -> BodyLayout {
        BodyLayout(
            composerHeight: max(0, sample.composerHeight),
            editorHeight: editorViewportHeight(sample.editorHeight),
            transcriptHeight: min(maximumTranscriptHeight, max(0, sample.transcriptHeight)),
            transcriptGap: min(maximumTranscriptGap, max(0, sample.transcriptGap)),
            notchHeight: notchHeight, includesError: includesError
        )
    }

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
        // Explicit transcript allocations remain uncapped for existing frame callers.
        let body = BodyLayout(
            composerHeight: composerHeight,
            transcriptHeight: transcriptHeight > 0 ? transcriptHeight : 0,
            transcriptGap: transcriptHeight > 0 ? Self.maximumTranscriptGap : 0,
            notchHeight: notchHeight, includesError: includesError
        )
        return CGSize(
            width: min(max(Self.preferredExpandedWidth, collapsedSize.width), screenFrame.width),
            height: min(body.height, screenFrame.height)
        )
    }

    func expandedLayout(
        composerHeight: CGFloat, editorHeight: CGFloat = 0,
        naturalTranscriptHeight: CGFloat = 0, includesError: Bool = false
    ) -> IslandLayout {
        let composer = composerHeight.isFinite ? max(0, composerHeight) : 0
        let editor = editorHeight.isFinite ? Self.editorViewportHeight(editorHeight) : 0
        let natural = naturalTranscriptHeight.isFinite ? max(0, naturalTranscriptHeight) : 0
        let baseHeight = expandedSize(composerHeight: composer, includesError: includesError).height
        let transcript = min(
            Self.maximumTranscriptHeight, natural,
            max(0, screenFrame.height - baseHeight - Self.maximumTranscriptGap)
        )
        return IslandLayout(
            size: expandedSize(composerHeight: composer, transcriptHeight: transcript, includesError: includesError),
            composerHeight: composer, editorHeight: editor, transcriptHeight: transcript,
            transcriptGap: transcript > 0 ? Self.maximumTranscriptGap : 0
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
