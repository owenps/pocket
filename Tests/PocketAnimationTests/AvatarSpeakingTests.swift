import AppKit
import SwiftUI
import Testing
@testable import Pocket

@MainActor
struct AvatarSpeakingTests {
    @Test func defaultPreviewAndOffscreenSpeakingRemainAtRest() throws {
        _ = NSApplication.shared
        let appearance = AvatarAppearance()
        let host = NSHostingView(rootView: AvatarView(appearance: appearance, size: 80))
        host.sizingOptions = []
        host.frame = CGRect(x: 0, y: 0, width: 80, height: 80)
        let resting = try snapshot(host)

        // No window is opened: requesting speech offscreen cannot start visible motion.
        host.rootView = AvatarView(appearance: appearance, size: 80, behavior: .speaking)
        let speaking = try snapshot(host)
        try assertQuiescent(host, equals: speaking)
        #expect(speaking == resting)

        host.rootView = AvatarView(appearance: appearance, size: 80, behavior: .inactive)
        #expect(try snapshot(host) == resting)
    }

    @Test func speakingAdvancesAndResetsWhenStoppedOccludedHiddenOrDetached() throws {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        var appearance = AvatarAppearance()
        appearance.headwear = .sprout
        try withHostedAvatar(appearance: appearance) { host, window in
            let rest = try snapshot(host)
            let frame = host.frame
            let responder = window.firstResponder
            host.rootView = AvatarView(appearance: appearance, size: 80, behavior: .speaking)
            let starting = try snapshot(host)
            #expect(starting != rest)
            try waitForDrawing(host) { try snapshot(host) != starting }
            #expect(host.frame == frame)
            #expect(window.firstResponder === responder)

            window.occluded = true
            NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
            try assertQuiescent(host, equals: rest)
            window.occluded = false
            NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
            #expect(try snapshot(host) == starting)
            try waitForDrawing(host) { try snapshot(host) != starting }

            host.rootView = AvatarView(appearance: appearance, size: 80, behavior: .inactive)
            try assertQuiescent(host, equals: rest)
            host.rootView = AvatarView(appearance: appearance, size: 80, behavior: .speaking)
            #expect(try snapshot(host) == starting)
            try waitForDrawing(host) { try snapshot(host) != starting }
            host.isHidden = true
            host.isHidden = false
            #expect(try snapshot(host) == starting)
            try waitForDrawing(host) { try snapshot(host) != starting }
            window.contentView = nil
            try assertQuiescent(host, equals: rest)
            #expect(host.frame == frame)
            #expect(window.firstResponder === responder)
        }
    }

    @Test func reduceMotionKeepsSpeakingAtRestAfterAccessibilityNotification() throws {
        guard NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let appearance = AvatarAppearance()
        try withHostedAvatar(appearance: appearance) { host, _ in
            let rest = try snapshot(host)
            host.rootView = AvatarView(appearance: appearance, size: 80, behavior: .speaking)
            NSWorkspace.shared.notificationCenter.post(
                name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil
            )
            try assertQuiescent(host, equals: rest)
        }
    }

    private func assertQuiescent(_ host: NSView, equals expected: Data) throws {
        // Cross one nominal display-link frame to catch a clock left running.
        let deadline = Date(timeIntervalSinceNow: 0.16)
        repeat {
            #expect(try snapshot(host) == expected)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        } while Date() < deadline
        #expect(try snapshot(host) == expected)
    }

    private func waitForDrawing(_ host: NSView, until condition: () throws -> Bool) throws {
        let deadline = Date(timeIntervalSinceNow: 2)
        repeat {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            if try condition() { return }
        } while Date() < deadline
        try #require(try condition(), "Buddy did not advance before timeout")
    }

    private func snapshot(_ view: NSView) throws -> Data {
        view.layoutSubtreeIfNeeded()
        // Keep resolution constant when detaching from a Retina window.
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2), pixelsHigh: Int(view.bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        bitmap.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: bitmap)
        #expect((bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.alphaComponent ?? 0) > 0)
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }
}

@MainActor
private func withHostedAvatar(
    appearance: AvatarAppearance, size: CGFloat = 80,
    body: (NSHostingView<AvatarView>, SpeakingTestWindow) throws -> Void
) rethrows {
    _ = NSApplication.shared
    let host = NSHostingView(rootView: AvatarView(appearance: appearance, size: size))
    host.sizingOptions = []
    let window = SpeakingTestWindow(
        contentRect: CGRect(x: 0, y: 0, width: size, height: size),
        styleMask: .borderless, backing: .buffered, defer: true
    )
    window.contentView = host
    // Simulate visibility without ordering the window onscreen. Display links and
    // snapshots still exercise animation without interrupting the desktop.
    defer { window.contentView = nil }
    try body(host, window)
}

@MainActor
private final class SpeakingTestWindow: NSWindow {
    var occluded = false
    override var isVisible: Bool { true }
    override var occlusionState: NSWindow.OcclusionState { occluded ? [] : [.visible] }
}
