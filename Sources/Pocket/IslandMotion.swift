import SwiftUI

struct IslandLayout: Equatable {
    var size: CGSize
    var composerHeight: CGFloat
    var editorHeight: CGFloat
    var transcriptHeight: CGFloat
    var transcriptGap: CGFloat
    /// Entire suggestion allocation, including bottom spacing; independent of transcript.
    var commandHeight: CGFloat

    init(size: CGSize, composerHeight: CGFloat = 0, editorHeight: CGFloat = 0,
         transcriptHeight: CGFloat = 0, transcriptGap: CGFloat = 0, commandHeight: CGFloat = 0) {
        self.size = size
        self.composerHeight = composerHeight
        self.editorHeight = editorHeight
        self.transcriptHeight = transcriptHeight
        self.transcriptGap = transcriptGap
        self.commandHeight = commandHeight
    }

    fileprivate var isValid: Bool {
        [size.width, size.height, composerHeight, editorHeight, transcriptHeight, transcriptGap, commandHeight]
            .allSatisfy { $0.isFinite && $0 >= 0 }
    }
}

/// Two native springs share one clock. Retargeting preserves every point value and velocity.
struct IslandMotion {
    private var width: Double
    private var heights: HeightVector
    private var widthVelocity = 0.0
    private var heightVelocity = HeightVector.zero
    private(set) var targetLayout: IslandLayout
    private var widthSpring = Spring(duration: 0.42, bounce: 0.20)
    private var heightSpring = Spring(duration: 0.48, bounce: 0.16)

    init(layout: IslandLayout = IslandLayout(size: .zero)) {
        let initial = layout.isValid ? layout : IslandLayout(size: .zero)
        targetLayout = initial
        width = Double(initial.size.width)
        heights = Self.heightVector(for: initial)
    }

    var layout: IslandLayout { Self.layout(width: width, heights: heights) }
    /// Points per second, including the internal viewport allocations.
    var velocity: IslandLayout { Self.layout(width: widthVelocity, heights: heightVelocity) }

    var isSettled: Bool {
        layout == targetLayout && widthVelocity == 0 && heightVelocity == .zero
    }

    mutating func retarget(to layout: IslandLayout, expanded: Bool, animated: Bool = true) {
        guard layout.isValid else { return }
        targetLayout = layout
        widthSpring = Spring(duration: expanded ? 0.42 : 0.34, bounce: expanded ? 0.20 : 0.18)
        heightSpring = Spring(duration: expanded ? 0.48 : 0.38, bounce: expanded ? 0.16 : 0.14)
        if !animated { settle() }
    }

    mutating func advance(by deltaTime: TimeInterval) {
        guard !isSettled, deltaTime.isFinite, deltaTime > 0 else { return }
        let targetHeights = Self.heightVector(for: targetLayout)
        // A single vector keeps outer height and viewport sums on the same trajectory,
        // even when content redistributes without changing the total surface height.
        widthSpring.update(value: &width, velocity: &widthVelocity,
                           target: Double(targetLayout.size.width), deltaTime: deltaTime)
        heightSpring.update(value: &heights, velocity: &heightVelocity,
                            target: targetHeights, deltaTime: deltaTime)
        // Huge finite intervals can overflow the native phase calculation; physically
        // they mean rest. Otherwise leave elastic values (including overshoot) intact.
        guard width.isFinite, widthVelocity.isFinite,
              (0..<6).allSatisfy({ heights.values[$0].isFinite && heightVelocity.values[$0].isFinite }) else {
            settle()
            return
        }
        if abs(width - Double(targetLayout.size.width)) < 0.001, abs(widthVelocity) < 0.01,
           (0..<6).allSatisfy({ abs(heights.values[$0] - targetHeights.values[$0]) < 0.001
               && abs(heightVelocity.values[$0]) < 0.01 }) {
            settle()
        }
    }

    static func contentVisibility(surfaceSize: CGSize, expandedSize: CGSize,
                                  expansionProgress: Double = 1) -> Double {
        // Ignore height: content-driven height changes must not blur already-open
        // content. Animated native viewport allocations keep the body fitted instead.
        let widthFraction = (surfaceSize.width - (expandedSize.width - 96)) / 96
        let fraction = Double(min(1, max(0, widthFraction)))
        return fraction * fraction * (3 - 2 * fraction) * min(1, max(0, expansionProgress * 4))
    }

    private mutating func settle() {
        width = Double(targetLayout.size.width)
        heights = Self.heightVector(for: targetLayout)
        widthVelocity = 0
        heightVelocity = .zero
    }

    private static func heightVector(for layout: IslandLayout) -> HeightVector {
        HeightVector(values: SIMD8(Double(layout.size.height), Double(layout.composerHeight),
                                   Double(layout.editorHeight), Double(layout.transcriptHeight),
                                   Double(layout.transcriptGap), Double(layout.commandHeight), 0, 0))
    }

    private static func layout(width: Double, heights: HeightVector) -> IslandLayout {
        IslandLayout(size: CGSize(width: width, height: heights.values[0]),
                     composerHeight: CGFloat(heights.values[1]),
                     editorHeight: CGFloat(heights.values[2]),
                     transcriptHeight: CGFloat(heights.values[3]),
                     transcriptGap: CGFloat(heights.values[4]),
                     commandHeight: CGFloat(heights.values[5]))
    }
}

private struct HeightVector: VectorArithmetic {
    var values: SIMD8<Double>
    static var zero: Self { Self(values: .zero) }

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(values: lhs.values + rhs.values)
    }

    static func - (lhs: Self, rhs: Self) -> Self {
        Self(values: lhs.values - rhs.values)
    }

    mutating func scale(by rhs: Double) { values *= rhs }

    var magnitudeSquared: Double {
        let squares = values * values
        return squares[0] + squares[1] + squares[2] + squares[3] + squares[4] + squares[5]
    }
}
