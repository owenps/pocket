import AppKit

@main
@MainActor
enum PocketApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let conversation = ConversationSession(backend: DemoAssistantBackend())
    private lazy var state = PanelState(
        conversation: conversation,
        openSettings: { [weak self] in self?.openSettings() }
    )
    private lazy var panel = PanelController(state: state)
    private let loginItem = LoginItemSettings()
    private lazy var settings = SettingsWindowController(
        state: state,
        loginItem: loginItem,
        changeShortcut: { [weak self] choice in self?.applyShortcut(choice) },
        recordingChanged: { [weak self] recording in self?.shortcutRecordingChanged(recording) }
    )
    private var menuBarStatus: MenuBarStatus?
    private var statusItem: NSStatusItem?
    private var shortcut: GlobalShortcut?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem
        menuBarStatus = MenuBarStatus(state: state) { [weak button = statusItem.button] status in
            guard let button, button.image !== status.image else { return }
            button.image = status.image
            button.toolTip = status.toolTip
            button.setAccessibilityLabel(status.accessibilityLabel)
        }

        let menu = NSMenu()
        let openItem = NSMenuItem(title: "Open Pocket", action: #selector(openPanel), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(NSMenuItem(title: "Local simulation · no network", action: nil, keyEquivalent: ""))
        let stopItem = NSMenuItem(title: "Stop simulated reply", action: #selector(stopDemoReply), keyEquivalent: ".")
        stopItem.target = self
        menu.addItem(stopItem)
        let resetItem = NSMenuItem(title: "Reset demo conversation", action: #selector(resetDemoConversation), keyEquivalent: "")
        resetItem.target = self
        menu.addItem(resetItem)
        menu.addItem(.separator())

        menu.addItem(settingsMenuItem())
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Pocket", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu

        applyShortcut(state.shortcut)
        panel.start()
        if state.shortcutError != nil { panel.show() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        conversation.stopReply()
        panel.stop()
        shortcut?.stop()
    }

    @objc private func openPanel() {
        panel.show()
    }

    @objc private func openSettings() {
        panel.collapse()
        settings.show()
    }

    @objc private func stopDemoReply() {
        conversation.stopReply()
    }

    @objc private func resetDemoConversation() {
        panel.resetConversation()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(stopDemoReply) { return conversation.isBusy }
        if menuItem.action == #selector(resetDemoConversation) { return !conversation.messages.isEmpty }
        return true
    }

    private func applyShortcut(_ choice: ShortcutChoice) {
        state.changeShortcut(to: choice) { choice in
            if shortcut == nil {
                shortcut = try GlobalShortcut { [weak self] in self?.panel.toggle() }
            }
            try shortcut?.register(choice)
        }
    }

    private func shortcutRecordingChanged(_ recording: Bool) {
        if recording {
            shortcut?.suspend()
        } else {
            do {
                try shortcut?.register(state.shortcut)
            } catch {
                state.shortcutError = error.localizedDescription
            }
        }
    }

    private func settingsMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        item.target = self
        return item
    }

    private func configureMainMenu() {
        // Even an accessory app needs an Edit menu to route standard text shortcuts.
        let mainMenu = NSMenu()
        let appMenu = NSMenu(title: "Pocket")
        appMenu.addItem(settingsMenuItem())
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Pocket", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(NSMenuItem(
            title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"
        ))
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let editMenu = NSMenu(title: "Edit")
        let actions: [(String, Selector, String)] = [
            ("Undo", Selector(("undo:")), "z"),
            ("Redo", Selector(("redo:")), "Z"),
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSText.selectAll(_:)), "a"),
        ]
        for (title, action, key) in actions {
            editMenu.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key))
        }
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
