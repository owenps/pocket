import AppKit
import PocketTestSupport
import Testing
@testable import Pocket

@Suite(.enabled(if: ProcessInfo.processInfo.environment["POCKET_DESKTOP_TESTS"] == "1",
                "Opens visible windows; opt in with POCKET_DESKTOP_TESTS=1."))
@MainActor
struct SettingsLifecycleTests {
    @Test func closingAndReopeningPreservesWorkingPreferences() async throws {
        try await NativeUITestSupport.withDesktop {
            let app = NSApplication.shared
            let policy = app.activationPolicy()
            app.setActivationPolicy(.accessory)
            defer { app.setActivationPolicy(policy) }
            let name = "SettingsLifecycleTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            let state = PanelState(
                conversation: ConversationSession(backend: DemoAssistantBackend(), defaults: defaults), defaults: defaults
            )
            let loginItem = LoginItemSettings(status: { .notRegistered }, register: {}, unregister: {}, openSettings: {})
            let controller = SettingsWindowController(
                state: state, loginItem: loginItem,
                changeShortcut: { state.changeShortcut(to: $0) { _ in } },
                recordingChanged: { _ in }
            )
            let window = try #require(controller.window)
            let host = try #require(window.contentView)
            defer {
                window.close()
                window.contentView = nil
            }
            controller.show()
            try NativeUITestSupport.wait {
                host.layoutSubtreeIfNeeded()
                return window.isVisible && self.nameField(in: host) != nil
            }
            try enterName("Owen", in: window, host: host)
            try NativeUITestSupport.wait { state.userName == "Owen" }
            window.performClose(nil)
            try NativeUITestSupport.wait { !window.isVisible }
            controller.show()
            try NativeUITestSupport.wait {
                host.layoutSubtreeIfNeeded()
                return window.isVisible && self.nameField(in: host)?.stringValue == "Owen"
            }
            try enterName("Alex", in: window, host: host)
            try NativeUITestSupport.wait { state.userName == "Alex" }
            try checkShortcutMenuRouting(window: window, host: host, state: state)
        }
    }

    private func checkShortcutMenuRouting(window: NSWindow, host: NSView, state: PanelState) throws {
        let previousMenu = NSApp.mainMenu
        let commands = ShortcutMenuCommands()
        let menu = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        menu.addItem(appItem)
        for key in ["q", "w", ","] {
            let item = NSMenuItem(title: key, action: #selector(ShortcutMenuCommands.invoke(_:)), keyEquivalent: key)
            item.target = commands
            appItem.submenu?.addItem(item)
        }
        NSApp.mainMenu = menu
        defer { NSApp.mainMenu = previousMenu }
        let button = try #require(recorder(in: host))
        for (code, key): (UInt16, String) in [(12, "q"), (13, "w"), (43, ",")] {
            button.performClick(nil)
            let event = try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: key,
                charactersIgnoringModifiers: key, isARepeat: false, keyCode: code
            ))
            #expect(window.performKeyEquivalent(with: event))
            #expect(!commands.wasInvoked)
            #expect(state.shortcut == ShortcutChoice(keyCode: code, modifiers: .command))
        }
    }

    private func recorder(in view: NSView) -> ShortcutRecorderButton? {
        if let recorder = view as? ShortcutRecorderButton { return recorder }
        return view.subviews.lazy.compactMap { recorder(in: $0) }.first
    }

    private func enterName(_ name: String, in window: NSWindow, host: NSView) throws {
        let field = try #require(nameField(in: host))
        #expect(window.makeFirstResponder(field))
        let editor = try #require(window.fieldEditor(false, for: field) as? NSTextView)
        editor.selectAll(nil)
        editor.insertText(name, replacementRange: editor.selectedRange())
    }

    private func nameField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        return view.subviews.lazy.compactMap { nameField(in: $0) }.first
    }
}

@MainActor
private final class ShortcutMenuCommands: NSObject {
    var wasInvoked = false
    @objc func invoke(_ sender: Any?) { wasInvoked = true }
}
