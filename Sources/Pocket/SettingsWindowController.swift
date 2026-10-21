import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private let loginItem: LoginItemSettings

    init(
        state: PanelState,
        loginItem: LoginItemSettings,
        changeShortcut: @escaping (ShortcutChoice) -> Void,
        recordingChanged: @escaping (Bool) -> Void
    ) {
        self.loginItem = loginItem
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 520, height: 720),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentMinSize = CGSize(width: 480, height: 460)
        window.title = "Pocket Settings"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(
            state: state, loginItem: loginItem,
            changeShortcut: changeShortcut, recordingChanged: recordingChanged
        ))
        window.center()
        window.setFrameAutosaveName("PocketSettings")
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(state:loginItem:changeShortcut:recordingChanged:)") }

    func show() {
        loginItem.refresh()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
