import SwiftUI

/// Concave shoulders join the screen edge; the lower corners soften as it opens.
/// Presentation is already sampled by the display link, so no second animation.
struct IslandShape: Shape {
    var progress: Double

    func path(in rect: CGRect) -> Path {
        let progress = CGFloat(min(1.06, max(-0.06, progress)))
        let shoulder = min(4 + 10 * progress, rect.width / 4, rect.height / 2)
        let bottom = min(12 + 14 * progress, rect.height / 2, (rect.width - 2 * shoulder) / 2)
        let left = rect.minX + shoulder
        let right = rect.maxX - shoulder
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: left, y: rect.minY + shoulder),
            control: CGPoint(x: left, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: left, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: left + bottom, y: rect.maxY),
            control: CGPoint(x: left, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: right - bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: right, y: rect.maxY - bottom),
            control: CGPoint(x: right, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: right, y: rect.minY + shoulder))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: right, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}
