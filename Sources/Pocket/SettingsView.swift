import SwiftUI

struct SettingsView: View {
    @Bindable var state: PanelState
    let loginItem: LoginItemSettings
    let changeShortcut: (ShortcutChoice) -> Void
    let recordingChanged: (Bool) -> Void

    var body: some View {
        TabView {
            general
                .tabItem { Text("General") }
            Form {
                AvatarSettingsView(appearance: $state.avatar, showBuddy: $state.showBuddy)
            }
            .formStyle(.grouped)
            .tabItem { Text("Buddy") }
        }
        .frame(minWidth: 480, minHeight: 460)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
        }
    }

    private var general: some View {
        Form {
            Section {
                TextField("Name", text: $state.userName, prompt: Text(""))
                    .accessibilityIdentifier("userName")
            } footer: {
                Text("Used to personalize greetings.")
            }

            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { loginItem.isEnabled || loginItem.requiresApproval },
                    set: { loginItem.setEnabled($0) }
                ))
                .accessibilityIdentifier("launchAtLogin")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    if let message = loginItem.statusMessage {
                        Text(message)
                        Button("Open System Settings…") { loginItem.openSystemSettings() }
                    }
                    if let error = loginItem.error {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }

            Section {
                HStack {
                    Text("Show or hide Pocket")
                    Spacer()
                    ShortcutRecorder(shortcut: state.shortcut, onChange: changeShortcut,
                                     onRecordingChanged: recordingChanged)
                        .frame(width: 160)
                }
            } header: {
                Text("Keyboard Shortcut")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Click to record. Use ⌘, ⌃ or ⌥ with any key, or a function key. Escape cancels.")
                    if let error = state.shortcutError {
                        Text(error)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("shortcutError")
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Font size")
                        Spacer()
                        Text("\(state.fontSize.formatted(.number.precision(.fractionLength(0)))) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $state.fontSize, in: PanelState.fontSizeRange, step: 1) {
                        Text("Font size")
                    }
                    .labelsHidden()
                    .accessibilityValue("\(Int(state.fontSize)) points")
                    .accessibilityIdentifier("fontSize")
                }
                FontSizePreview(fontSize: state.fontSize)
            } header: {
                Text("Text")
            }
        }
        .formStyle(.grouped)
    }
}
