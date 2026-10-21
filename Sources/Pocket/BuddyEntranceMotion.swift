import Foundation
import SwiftUI

/// Opening-only pop, advanced by the island's display clock.
struct BuddyEntranceMotion {
    private(set) var progress = 0.0
    private var expanded = false
    private var revealed = false
    private var elapsedTime: TimeInterval = 0
    private let duration: TimeInterval = 0.4

    var isActive: Bool { expanded && progress < 1 }

    struct Pose: Equatable {
        var opacity: Double
        var scale: Double
        var offsetY: Double
    }

    private static let arrival = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.16, y: 1), endControlPoint: UnitPoint(x: 0.3, y: 1)
    )
    private static let settle = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.4, y: 0), endControlPoint: UnitPoint(x: 0.2, y: 1)
    )

    static func pose(at progress: Double, reduceMotion: Bool = false) -> Pose {
        let progress = min(1, max(0, progress))
        if reduceMotion {
            // Keep the prototype's 180ms fade, without scale or travel.
            return Pose(opacity: min(1, progress / 0.45), scale: 1, offsetY: 0)
        }
        if progress < 0.55 {
            let arrival = arrival.value(at: progress / 0.55)
            return Pose(opacity: arrival, scale: 0.72 + 0.38 * arrival, offsetY: 6 * (1 - arrival))
        }
        let settle = settle.value(at: (progress - 0.55) / 0.45)
        return Pose(opacity: 1, scale: 1 + 0.1 * (1 - settle), offsetY: 0)
    }

    mutating func update(expanded: Bool, contentVisibility: Double, elapsed: TimeInterval = 0) {
        self.expanded = expanded
        guard expanded else {
            // Keep the presented pose through a partial close/reopen. Only fully
            // hidden content can rearm the entrance without a visible jump.
            if contentVisibility <= 0 {
                progress = 0
                elapsedTime = 0
                revealed = false
            }
            return
        }
        // Join the reveal once Buddy can emerge, rather than waiting for a
        // separate entrance after the panel opens.
        revealed = revealed || contentVisibility >= 0.5
        guard revealed, progress < 1, elapsed.isFinite, elapsed > 0 else { return }
        elapsedTime = min(duration, elapsedTime + elapsed)
        progress = elapsedTime / duration
    }
}
