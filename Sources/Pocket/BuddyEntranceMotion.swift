import Foundation
import SwiftUI

/// Opening-only pop, advanced by the island's display clock.
struct BuddyEntranceMotion {
    private(set) var progress = 0.0
    private var expanded = false
    private var revealed = false
    private var elapsedTime: TimeInterval = 0
    private let delay: TimeInterval = 0.05
    private static let duration: TimeInterval = 0.34
    private static let arrivalDuration: TimeInterval = 0.14

    var isActive: Bool { expanded && progress < 1 }

    struct Pose: Equatable {
        var opacity: Double
        var scale: Double
        var offsetY: Double
    }

    struct Burst: Equatable {
        var opacity: Double
        var travel: Double
    }

    private static let arrival = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.16, y: 1), endControlPoint: UnitPoint(x: 0.3, y: 1)
    )
    private static let settle = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.4, y: 0), endControlPoint: UnitPoint(x: 0.2, y: 1)
    )

    static func pose(at progress: Double, reduceMotion: Bool = false) -> Pose {
        let progress = min(1, max(0, progress))
        let elapsed = progress * duration
        if reduceMotion {
            // Keep the prototype's 180ms fade, without scale or travel.
            return Pose(opacity: min(1, elapsed / 0.18), scale: 1, offsetY: 0)
        }
        if elapsed < arrivalDuration {
            let arrival = arrival.value(at: elapsed / arrivalDuration)
            return Pose(opacity: min(1, elapsed / 0.05), scale: 0.6 + 0.54 * arrival,
                        offsetY: 6 * (1 - arrival))
        }
        let settle = settle.value(at: (elapsed - arrivalDuration) / (duration - arrivalDuration))
        return Pose(opacity: 1, scale: 1 + 0.14 * (1 - settle), offsetY: 0)
    }

    static func burst(at progress: Double, reduceMotion: Bool = false) -> Burst {
        let elapsed = min(1, max(0, progress)) * duration - arrivalDuration
        guard !reduceMotion, elapsed >= 0, elapsed < 0.15 else {
            return Burst(opacity: 0, travel: 0)
        }
        let travel = elapsed / 0.15
        return Burst(opacity: 1 - travel, travel: travel)
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
        elapsedTime = min(delay + Self.duration, elapsedTime + elapsed)
        progress = min(1, max(0, (elapsedTime - delay) / Self.duration))
    }
}
