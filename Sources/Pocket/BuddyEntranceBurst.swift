import SwiftUI

struct BuddyEntranceBurst: View {
    let palette: AvatarAppearance.Palette
    let progress: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let burst = BuddyEntranceMotion.burst(at: progress, reduceMotion: reduceMotion)
        GeometryReader { geometry in
            let size = geometry.size
            let drift = 2 * burst.travel
            Path { path in
                let rays: [(CGPoint, CGVector)] = [
                    (CGPoint(x: size.width * 0.12, y: size.height * 0.13), CGVector(dx: -0.8, dy: -0.6)),
                    (CGPoint(x: size.width * 0.5, y: 1), CGVector(dx: 0, dy: -1)),
                    (CGPoint(x: size.width * 0.88, y: size.height * 0.13), CGVector(dx: 0.8, dy: -0.6)),
                ]
                for (origin, direction) in rays {
                    path.move(to: CGPoint(x: origin.x + direction.dx * drift,
                                          y: origin.y + direction.dy * drift))
                    path.addLine(to: CGPoint(x: origin.x + direction.dx * (drift + 3),
                                             y: origin.y + direction.dy * (drift + 3)))
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        .opacity(burst.opacity)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var color: Color {
        let light = palette.colors.light
        return Color(.sRGB, red: Double((light >> 16) & 0xff) / 255,
                     green: Double((light >> 8) & 0xff) / 255, blue: Double(light & 0xff) / 255, opacity: 1)
    }
}
