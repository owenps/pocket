import AppKit
import PocketTestSupport
import QuartzCore
import SwiftUI
import Testing
@testable import Pocket

@MainActor
struct AvatarSettingsPreviewTests {
    @Test func previewRunsNativeClockThenRestsWithoutRearming() throws {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        try withAvatar { host, window in
            let rest = try snapshot(host)
            let frame = host.frame
            let responder = window.firstResponder
            update(host)
            #expect(try snapshot(host) != rest)
            try NativeUITestSupport.wait { window.clockStarts == 1 && window.clockCallbacks > 0 }
            try NativeUITestSupport.wait(timeout: 3) { try snapshot(host) == rest }
            #expect(host.frame == frame)
            #expect(window.firstResponder === responder)
            let callbacks = window.clockCallbacks
            let starts = window.clockStarts
            let deadline = Date(timeIntervalSinceNow: 0.25)
            repeat {
                // Neither identical updates, layout, nor timing configuration is a request.
                update(host, interval: 0.01...0.01)
                host.needsLayout = true
                #expect(try snapshot(host) == rest)
                pump(0.01)
            } while Date() < deadline
            host.isHidden = true
            host.isHidden = false
            try assertDrawing(host, equals: rest, for: 0.2)
            #expect(window.clockCallbacks == callbacks)
            #expect(window.clockStarts == starts)
        }
    }

    @Test func sizeChangeReplacesActivePreviewDespiteSharingRasterCache() throws {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        try withAvatar { host, window in
            update(host)
            _ = try snapshot(host)
            try NativeUITestSupport.wait { window.clockStarts == 1 && window.clockCallbacks > 0 }
            var changed = AvatarAppearance()
            changed.size = .large
            let rest = try reference(changed, frame: host.frame)
            update(host, appearance: changed)
            #expect(try snapshot(host) != rest)
            try NativeUITestSupport.wait { window.clockStarts == 2 }
            try NativeUITestSupport.wait(timeout: 3) { try snapshot(host) == rest }
            let callbacks = window.clockCallbacks
            update(host, appearance: changed)
            try assertDrawing(host, equals: rest, for: 0.25)
            #expect(window.clockStarts == 2)
            #expect(window.clockCallbacks == callbacks)
        }
    }

    private enum Gate: CaseIterable { case hidden, occluded, invisible, detached, clipped, closed }

    @Test(arguments: Gate.allCases)
    private func visibilityLossCancelsWithoutReplayingOrQueuingChanges(gate: Gate) throws {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        try withAvatar { host, window in
            update(host)
            _ = try snapshot(host)
            // Exercise both phases without multiplying every native visibility gate.
            if gate == .occluded || gate == .detached {
                try NativeUITestSupport.wait { window.clockStarts == 1 && window.clockCallbacks > 0 }
            }
            let originalFrame = host.frame
            switch gate {
            case .hidden: host.isHidden = true
            case .occluded:
                window.occluded = true
                notifyVisibility(window)
            case .invisible:
                window.simulatedVisible = false
                notifyVisibility(window)
            case .detached: window.contentView = nil
            case .clipped:
                host.frame.origin.x = 1000
                try #require(host.visibleRect.intersection(host.bounds).isEmpty)
            case .closed:
                NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
            }
            var changed = AvatarAppearance()
            changed.palette = .glacier
            update(host, appearance: changed)
            _ = try snapshot(host) // Deliver the changed request while gated.
            let starts = window.clockStarts
            let callbacks = window.clockCallbacks
            pump(0.16)
            #expect(window.clockStarts == starts)
            #expect(window.clockCallbacks == callbacks)
            switch gate {
            case .hidden: host.isHidden = false
            case .occluded:
                window.occluded = false
                notifyVisibility(window)
            case .invisible:
                window.simulatedVisible = true
                notifyVisibility(window)
            case .detached: window.contentView = host
            case .clipped: host.frame = originalFrame
            case .closed: notifyVisibility(window)
            }
            let rest = try reference(changed, frame: host.frame)
            update(host, appearance: changed)
            try assertDrawing(host, equals: rest, for: 0.25)
            #expect(window.clockStarts == starts)
            #expect(window.clockCallbacks == callbacks)
            if gate != .closed {
                changed.size = .large
                update(host, appearance: changed)
                #expect(try snapshot(host) != rest)
            }
        }
    }

    @Test func reopeningAllowsFreshChangesWithoutReplayingThePreviousPreview() throws {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        try withAvatar { host, window in
            let rest = try snapshot(host)
            update(host)
            _ = try snapshot(host)
            NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
            try assertDrawing(host, equals: rest, for: 0.15)

            NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
            update(host)
            try assertDrawing(host, equals: rest, for: 0.2)
            let starts = window.clockStarts
            var changed = AvatarAppearance()
            changed.palette = .glacier
            let changedRest = try reference(changed, frame: host.frame)
            update(host, appearance: changed)
            #expect(try snapshot(host) != changedRest)
            try NativeUITestSupport.wait { window.clockStarts == starts + 1 }
            try NativeUITestSupport.wait(timeout: 3) { try snapshot(host) == changedRest }
            try assertDrawing(host, equals: changedRest, for: 0.2)
        }
    }

    @Test func inactiveCancelsPreviewAndDefaultRemainsStatic() throws {
        try withAvatar { host, window in
            let rest = try snapshot(host)
            try assertDrawing(host, equals: rest, for: 0.2)
            update(host)
            _ = try snapshot(host)
            host.rootView = AvatarView(appearance: AvatarAppearance(), size: 80)
            try assertDrawing(host, equals: rest, for: 0.25)
            #expect(window.clockStarts == 0)
            #expect(window.clockCallbacks == 0)
        }
    }

    @Test func reduceMotionSuppressesPreviewRequests() throws {
        guard NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        try withAvatar { host, window in
            let rest = try snapshot(host)
            update(host)
            NSWorkspace.shared.notificationCenter.post(
                name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil
            )
            try assertDrawing(host, equals: rest, for: 0.25)
            var changed = AvatarAppearance()
            changed.palette = .glacier
            update(host, appearance: changed)
            try assertDrawing(host, equals: reference(changed, frame: host.frame), for: 0.25)
            #expect(window.clockStarts == 0)
            #expect(window.clockCallbacks == 0)
        }
    }

    private func update(_ host: NSHostingView<AvatarView>, appearance: AvatarAppearance = AvatarAppearance(),
                        interval: ClosedRange<TimeInterval> = 0.05...0.05) {
        host.rootView = AvatarView(appearance: appearance, size: 80, behavior: .preview,
                                   idleBlinkInterval: interval)
    }

    private func reference(_ appearance: AvatarAppearance, frame: CGRect) throws -> Data {
        let host = NSHostingView(rootView: AvatarView(appearance: appearance, size: 80))
        host.sizingOptions = []
        host.frame = CGRect(origin: .zero, size: frame.size)
        return try snapshot(host)
    }

    private func withAvatar(_ body: (NSHostingView<AvatarView>, PreviewTestWindow) throws -> Void) rethrows {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: AvatarView(appearance: AvatarAppearance(), size: 80))
        host.sizingOptions = []
        let window = PreviewTestWindow(
            contentRect: CGRect(x: 0, y: 0, width: 80, height: 80),
            styleMask: .borderless, backing: .buffered, defer: true
        )
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 80, height: 80))
        container.clipsToBounds = true
        host.frame = container.bounds
        container.addSubview(host)
        window.contentView = container
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        try body(host, window)
    }

    private func notifyVisibility(_ window: NSWindow) {
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
    }

    private func pump(_ duration: TimeInterval) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: duration))
    }

    private func assertDrawing(_ view: NSView, equals expected: Data, for duration: TimeInterval) throws {
        let deadline = Date(timeIntervalSinceNow: duration)
        repeat {
            #expect(try snapshot(view) == expected)
            pump(0.01)
        } while Date() < deadline
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
}

@MainActor
private final class PreviewTestWindow: NSWindow {
    var simulatedVisible = true
    var occluded = false
    var clockStarts = 0
    var clockCallbacks = 0
    override var isVisible: Bool { simulatedVisible }
    override var occlusionState: NSWindow.OcclusionState { occluded ? [] : [.visible] }

    override func displayLink(target: Any, selector: Selector) -> CADisplayLink {
        clockStarts += 1
        let observer = ClockObserver(target: target, selector: selector, window: self)
        return super.displayLink(target: observer, selector: #selector(ClockObserver.advance(_:)))
    }

    @MainActor private final class ClockObserver: NSObject {
        private let target: AnyObject
        private let selector: Selector
        private weak var window: PreviewTestWindow?

        init(target: Any, selector: Selector, window: PreviewTestWindow) {
            self.target = target as AnyObject
            self.selector = selector
            self.window = window
        }

        @objc func advance(_ link: CADisplayLink) {
            window?.clockCallbacks += 1
            _ = target.perform(selector, with: link)
        }
    }
}
