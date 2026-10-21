import AppKit
import PocketTestSupport
import SwiftUI
import Testing
@testable import Pocket

@MainActor
struct BuddyEditingTests {
    @Test func nativeTypingDoesNotMoveBuddyEyesOrLoseFocus() throws {
        _ = NSApplication.shared
        let name = "BuddyEditingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let conversation = ConversationSession(backend: DemoAssistantBackend(), defaults: defaults)
        let state = PanelState(conversation: conversation, defaults: defaults)
        state.isExpanded = true
        state.expansionProgress = 1
        state.buddyEntranceProgress = 1
        state.showBuddy = true
        state.surfaceRect = CGRect(origin: .zero, size: state.expandedSize)
        let fixture = OffscreenHost(PanelView(
            state: state, expand: {}, collapse: {}, editorHeightChanged: { _ in }, submit: { false }
        ), size: state.surfaceRect.size)
        defer { fixture.close() }
        let host = fixture.view
        let window = fixture.window
        host.layoutSubtreeIfNeeded()
        pump(0.04)
        let editor = try #require(draftEditor(in: host))
        try #require(window.makeFirstResponder(editor))
        let rest = try buddySnapshot(host, state: state)
        let started = Date()
        for input in ["A", "Typing", "Typing again"] {
            editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
            editor.insertText(input, replacementRange: editor.selectedRange())
            #expect(conversation.draft == input)
            #expect(editor.string == input)
            let deadline = Date(timeIntervalSinceNow: 0.05)
            repeat {
                #expect(try buddySnapshot(host, state: state) == rest)
                #expect(window.firstResponder === editor)
                pump(0.01)
            } while Date() < deadline
        }
        // Idle blinks remain valid, but none is due during this <8-second sample.
        #expect(Date().timeIntervalSince(started) < 8)
        #expect(conversation.messages.isEmpty)
    }

    @Test func workingBaselineStaysStaticEvenWithShortBlinkInterval() throws {
        _ = NSApplication.shared
        let fixture = OffscreenHost(AvatarView(
            appearance: AvatarAppearance(), size: 80, behavior: .resting, idleBlinkInterval: 0.05...0.05
        ), size: CGSize(width: 80, height: 80))
        defer { fixture.close() }
        let host = fixture.view
        let rest = try snapshot(host, rect: host.bounds)
        let deadline = Date(timeIntervalSinceNow: 0.30)
        repeat {
            #expect(try snapshot(host, rect: host.bounds) == rest)
            pump(0.01)
        } while Date() < deadline
    }

    private func draftEditor(in view: NSView) -> DraftTextView? {
        if let editor = view as? DraftTextView { return editor }
        return view.subviews.lazy.compactMap { draftEditor(in: $0) }.first
    }

    private func buddySnapshot(_ host: NSView, state: PanelState) throws -> Data {
        host.layoutSubtreeIfNeeded()
        let size = state.avatar.size.points
        let top = state.notchHeight + 12
        return try snapshot(host, rect: CGRect(
            x: host.bounds.minX + 24,
            y: host.isFlipped ? host.bounds.minY + top : host.bounds.maxY - top - size,
            width: size, height: size
        ))
    }

    private func snapshot(_ view: NSView, rect: CGRect) throws -> Data {
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(rect.width * 2), pixelsHigh: Int(rect.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        bitmap.size = rect.size
        view.cacheDisplay(in: rect, to: bitmap)
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    private func pump(_ duration: TimeInterval) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: duration))
    }
}
