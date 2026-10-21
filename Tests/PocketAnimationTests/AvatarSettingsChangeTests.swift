import AppKit
import Observation
import PocketTestSupport
import SwiftUI
import Testing
@testable import Pocket

@MainActor
struct AvatarSettingsChangeTests {
    @Test func appearanceBindingRequestsPreviewThenReturnsToRest() throws {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let values = SettingsValues()
        try withSettings(values) { host in
            let initial = try snapshot(host)
            try assertDrawing(host, equals: initial, for: 0.15)

            var changed = values.appearance
            changed.palette = .glacier
            let rest = try reference(changed)
            values.appearance = changed
            try wait {
                guard self.selectedPalette(.glacier, in: host) else { return false }
                return try self.snapshot(host) != rest
            }
            try wait(timeout: 3) { try snapshot(host) == rest }
            try assertDrawing(host, equals: rest, for: 0.15)
        }
    }

    @Test func reduceMotionEnvironmentKeepsActualSettingsChangesStatic() throws {
        let values = SettingsValues()
        try withSettings(values, reduceMotion: true) { host in
            var changed = values.appearance
            changed.palette = .glacier
            let rest = try reference(changed, reduceMotion: true)
            values.appearance = changed
            try wait { self.selectedPalette(.glacier, in: host) }
            // Force the SwiftUI environment, independent of the machine's accessibility setting.
            try assertDrawing(host, equals: rest, for: 0.15)
        }
    }

    private func reference(_ appearance: AvatarAppearance, reduceMotion: Bool = false) throws -> Data {
        let values = SettingsValues()
        values.appearance = appearance
        return try withSettings(values, reduceMotion: reduceMotion) { try snapshot($0) }
    }

    private func withSettings<Result>(
        _ values: SettingsValues, reduceMotion: Bool = false,
        body: (NSView) throws -> Result
    ) throws -> Result {
        _ = NSApplication.shared
        // macOS's writable reduce-motion environment property has an underscored spelling.
        let host = NSHostingView(rootView: Form {
            AvatarSettingsView(
                appearance: Binding(get: { values.appearance }, set: { values.appearance = $0 }),
                showBuddy: Binding(get: { values.showBuddy }, set: { values.showBuddy = $0 })
            )
        }.formStyle(.grouped).environment(\._accessibilityReduceMotion, reduceMotion))
        host.sizingOptions = []
        let window = SettingsChangeTestWindow(
            contentRect: CGRect(x: 0, y: 0, width: 520, height: 720),
            styleMask: [.titled, .closable], backing: .buffered, defer: true
        )
        window.contentView = host
        defer { window.contentView = nil }
        try wait { self.selectedPalette(values.appearance.palette, in: host) }
        pump(0.04)
        return try body(host)
    }

    private func selectedPalette(_ palette: AvatarAppearance.Palette, in view: NSView) -> Bool {
        if let button = view as? NSButton,
           button.accessibilityLabel() == "\(palette.title) palette", button.state == .on {
            return true
        }
        return view.subviews.contains { selectedPalette(palette, in: $0) }
    }

    private func snapshot(_ view: NSView) throws -> Data {
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    private func assertDrawing(_ view: NSView, equals expected: Data, for duration: TimeInterval) throws {
        let deadline = Date(timeIntervalSinceNow: duration)
        repeat {
            #expect(try snapshot(view) == expected)
            pump(0.025)
        } while Date() < deadline
    }

    private func wait(timeout: TimeInterval = 2, until condition: () throws -> Bool) throws {
        try NativeUITestSupport.wait(timeout: timeout, until: condition)
    }

    private func pump(_ duration: TimeInterval) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: duration))
    }
}

@MainActor @Observable
private final class SettingsValues {
    var appearance = AvatarAppearance()
    var showBuddy = true
}

@MainActor
private final class SettingsChangeTestWindow: NSWindow {
    override var isVisible: Bool { true }
    override var isKeyWindow: Bool { true }
    override var occlusionState: NSWindow.OcclusionState { [.visible] }
}
