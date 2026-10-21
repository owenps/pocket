import AppKit
import PocketTestSupport
import Testing
@testable import Pocket

@Suite(.enabled(if: ProcessInfo.processInfo.environment["POCKET_DESKTOP_TESTS"] == "1",
                "Opens visible windows; opt in with POCKET_DESKTOP_TESTS=1."))
@MainActor
struct PanelLifecycleTests {
    @Test func openingRevealsBuddyAndOnlyAFullCollapseRearmsHisEntrance() async throws {
        try await NativeUITestSupport.withDesktop {
            let app = NSApplication.shared
            let policy = app.activationPolicy()
            app.setActivationPolicy(.accessory)
            defer { app.setActivationPolicy(policy) }
            let name = "PanelLifecycleTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            let conversation = ConversationSession(backend: DemoAssistantBackend(), defaults: defaults)
            let state = PanelState(conversation: conversation, defaults: defaults)
            state.conversation.draft = "Ready to edit"
            let existingWindows = Set(app.windows.map(ObjectIdentifier.init))
            let controller = PanelController(state: state)
            controller.start()
            let window = try #require(app.windows.first { !existingWindows.contains(ObjectIdentifier($0)) })
            let host = try #require(window.contentView)
            defer {
                controller.collapse()
                controller.stop()
                window.orderOut(nil)
                window.contentView = nil
                window.close()
            }

            #expect(!state.isExpanded)
            controller.show()
            #expect(state.isExpanded)
            #expect(state.buddyEntranceProgress == 0)
            try NativeUITestSupport.wait {
                host.layoutSubtreeIfNeeded()
                return window.firstResponder is DraftTextView
            }
            let editor = try #require(window.firstResponder as? DraftTextView)
            editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
            editor.insertText(" immediately", replacementRange: editor.selectedRange())
            #expect(conversation.draft == "Ready to edit immediately")
            try NativeUITestSupport.wait {
                state.buddyEntranceProgress == 1 && self.buddyIsPainted(in: host, state: state)
            }
            #expect(window.firstResponder === editor)

            controller.show()
            controller.resetConversation()
            #expect(state.buddyEntranceProgress == 1)
            #expect(conversation.draft == "Ready to edit immediately")

            controller.collapse()
            try NativeUITestSupport.wait { state.buddyEntranceProgress == 0 }
            controller.show()
            #expect(state.buddyEntranceProgress == 0)
            try NativeUITestSupport.wait {
                state.buddyEntranceProgress == 1 && self.buddyIsPainted(in: host, state: state)
            }
            #expect(self.draftEditor(in: host) === editor)
            #expect(conversation.draft == "Ready to edit immediately")
        }
    }

    @Test(arguments: [false, true])
    func shortcutOpensRefocusesAndClosesWhileFocusLossHonorsPreference(keepOpen: Bool) async throws {
        try await NativeUITestSupport.withDesktop {
            let app = NSApplication.shared
            let policy = app.activationPolicy()
            app.setActivationPolicy(.accessory)
            defer { app.setActivationPolicy(policy) }
            let name = "PanelFocusTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            let state = PanelState(
                conversation: ConversationSession(backend: DemoAssistantBackend(), defaults: defaults),
                defaults: defaults
            )
            state.keepOpenWhenUnfocused = keepOpen
            state.conversation.draft = "Keep this draft"
            let existingWindows = Set(app.windows.map(ObjectIdentifier.init))
            let controller = PanelController(state: state)
            controller.start()
            let window = try #require(app.windows.first { !existingWindows.contains(ObjectIdentifier($0)) })
            // Transfer real key focus without requiring the test process to activate.
            let other = NSPanel(
                contentRect: CGRect(x: 100, y: 100, width: 200, height: 100),
                styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false
            )
            other.becomesKeyOnlyIfNeeded = false
            other.hidesOnDeactivate = false
            other.isReleasedWhenClosed = false
            defer {
                controller.collapse()
                controller.stop()
                window.orderOut(nil)
                window.contentView = nil
                window.close()
                other.close()
            }

            @MainActor func waitForFocus(_ phase: String, until condition: () -> Bool) throws {
                do {
                    try NativeUITestSupport.wait(until: condition)
                } catch {
                    let responder = window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
                    throw FocusTransitionFailure(description:
                        "\(phase) (keepOpen=\(keepOpen)): \(error) " +
                        "policy=\(app.activationPolicy().rawValue), active=\(app.isActive), " +
                        "expanded=\(state.isExpanded), panelKey=\(window.isKeyWindow), " +
                        "otherKey=\(other.isKeyWindow), responder=\(responder)"
                    )
                }
            }

            controller.toggle()
            try waitForFocus("shortcut opens panel") { state.isExpanded && window.isKeyWindow }
            other.makeKeyAndOrderFront(nil)
            try waitForFocus("transfer focus away") { other.isKeyWindow && !window.isKeyWindow }
            #expect(state.isExpanded == keepOpen)
            #expect(window.isVisible)
            #expect(state.conversation.draft == "Keep this draft")

            controller.toggle()
            try waitForFocus("shortcut reopens/refocuses panel") {
                state.isExpanded && window.isKeyWindow && window.firstResponder is DraftTextView
            }
            #expect(state.conversation.draft == "Keep this draft")
            controller.toggle()
            #expect(!state.isExpanded)

            controller.toggle()
            try waitForFocus("shortcut opens before Escape") { state.isExpanded && window.isKeyWindow }
            window.cancelOperation(nil)
            #expect(!state.isExpanded)
            #expect(state.conversation.draft == "Keep this draft")
        }
    }

    private struct FocusTransitionFailure: Error, CustomStringConvertible {
        let description: String
    }

    private func draftEditor(in view: NSView) -> DraftTextView? {
        if let editor = view as? DraftTextView { return editor }
        return view.subviews.lazy.compactMap { draftEditor(in: $0) }.first
    }

    private func buddyIsPainted(in host: NSView, state: PanelState) -> Bool {
        host.layoutSubtreeIfNeeded()
        let size = state.avatar.size.points
        let top = state.notchHeight + 12
        let rect = CGRect(x: 24, y: host.isFlipped ? top : host.bounds.height - top - size,
                          width: size, height: size)
        guard host.bounds.contains(rect), let image = host.bitmapImageRepForCachingDisplay(in: rect) else { return false }
        host.cacheDisplay(in: rect, to: image)
        // Only Buddy occupies this crop. A completed scalar is insufficient if
        // the controller/view wiring still leaves the actual artwork invisible.
        for y in 0..<image.pixelsHigh {
            for x in 0..<image.pixelsWide {
                if let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                   color.alphaComponent > 0.5,
                   max(color.redComponent, color.greenComponent, color.blueComponent) > 0.2 { return true }
            }
        }
        return false
    }
}
