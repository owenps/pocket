import AppKit
import SwiftUI
import Testing
@testable import Pocket

@MainActor
struct AvatarIdleBlinkTests {
    private let interval: ClosedRange<TimeInterval> = 0.22...0.22

    @Test func idleBlinksAndRestoresDespiteRepeatedUpdatesAndLayout() throws {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        try withAvatar { host, _ in
            let rest = try snapshot(host)
            let frame = host.frame
            enableIdle(host)
            #expect(try snapshot(host) == rest)
            try wait {
                enableIdle(host)
                host.needsLayout = true
                return try snapshot(host) != rest
            }
            let blink = try snapshot(host)
            try expectOnlyEyesChanged(rest, blink)
            try wait {
                enableIdle(host)
                host.needsLayout = true
                return try snapshot(host) == rest
            }
            #expect(host.frame == frame)
        }
    }

    @Test func closedWindowStaysStillUntilItIsReopened() throws {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        try withAvatar { host, window in
            let rest = try snapshot(host)
            enableIdle(host)
            try wait { try snapshot(host) != rest }
            NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
            #expect(try snapshot(host) == rest)
            // No idle clock may survive while the window remains closed.
            try assertDrawing(host, equals: rest, for: 0.28)
            NotificationCenter.default.post(name: NSWindow.didExposeNotification, object: window)
            try assertDrawing(host, equals: rest, for: 0.28)
            NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
            #expect(try snapshot(host) == rest)
            try wait { try snapshot(host) != rest }
            try wait { try snapshot(host) == rest }
        }
    }

    @Test func reduceMotionRemainsStaticWhenEnabled() throws {
        guard NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        try withAvatar { host, _ in
            let rest = try snapshot(host)
            enableIdle(host)
            try assertDrawing(host, equals: rest, for: 0.28)
        }
    }

    private func enableIdle(_ host: NSHostingView<AvatarView>) {
        host.rootView = AvatarView(appearance: AvatarAppearance(), size: 80,
                                   behavior: .idle, idleBlinkInterval: interval)
    }

    private func pump(_ duration: TimeInterval) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: duration))
    }

    private func wait(timeout: TimeInterval = 2, until condition: () throws -> Bool) throws {
        let deadline = Date(timeIntervalSinceNow: timeout)
        repeat {
            pump(0.005)
            if try condition() { return }
        } while Date() < deadline
        try #require(try condition(), "Expected avatar drawing before timeout")
    }

    private func assertDrawing(_ host: NSView, equals expected: Data, for duration: TimeInterval) throws {
        let deadline = Date(timeIntervalSinceNow: duration)
        repeat {
            #expect(try snapshot(host) == expected)
            pump(0.01)
        } while Date() < deadline
    }

    private func expectOnlyEyesChanged(_ rest: Data, _ blink: Data) throws {
        let natural = try #require(NSBitmapImageRep(data: rest))
        let closed = try #require(NSBitmapImageRep(data: blink))
        #expect(rest != blink)
        let eyes = CGRect(x: 0.24, y: 0.48, width: 0.52, height: 0.22)
        var changedOutsideEyes = false
        var changedAlpha = false
        for y in 0..<natural.pixelsHigh {
            for x in 0..<natural.pixelsWide {
                let before = try #require(natural.colorAt(x: x, y: y))
                let after = try #require(closed.colorAt(x: x, y: y))
                changedAlpha = changedAlpha || before.alphaComponent != after.alphaComponent
                let point = CGPoint(x: CGFloat(x) / CGFloat(natural.pixelsWide),
                                    y: CGFloat(y) / CGFloat(natural.pixelsHigh))
                if before != after && !eyes.contains(point) { changedOutsideEyes = true }
            }
        }
        #expect(!changedAlpha)
        #expect(!changedOutsideEyes)
    }

    private func snapshot(_ view: NSView) throws -> Data {
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 160, pixelsHigh: 160,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        bitmap.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    private func withAvatar(_ body: (NSHostingView<AvatarView>, IdleBlinkTestWindow) throws -> Void) rethrows {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: AvatarView(appearance: AvatarAppearance(), size: 80))
        host.sizingOptions = []
        let window = IdleBlinkTestWindow(
            contentRect: CGRect(x: 0, y: 0, width: 80, height: 80),
            styleMask: .borderless, backing: .buffered, defer: true
        )
        window.contentView = host
        defer { window.contentView = nil }
        try body(host, window)
    }
}

@MainActor
private final class IdleBlinkTestWindow: NSWindow {
    override var isVisible: Bool { true }
    override var occlusionState: NSWindow.OcclusionState { [.visible] }
}
