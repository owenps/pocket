import CoreGraphics
import Foundation

/// Continuous screen-space paint bounds inside a tightly fitted native window.
struct IslandFrame: Equatable {
    let surface: CGRect

    init(surface: CGRect) {
        self.surface = surface
    }

    var window: CGRect { surface.integral }

    /// Top-left-relative view coordinates, using the frame AppKit actually accepted.
    func localSurface(in actualWindow: CGRect) -> CGRect {
        CGRect(
            x: surface.minX - actualWindow.minX,
            y: actualWindow.maxY - surface.maxY,
            width: surface.width,
            height: surface.height
        )
    }
}
