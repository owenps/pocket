import Foundation
import Testing
@testable import Pocket

@MainActor
struct ShortcutPreferenceTests {
    @Test(arguments: ["controlSpace", "40:1048576"])
    func successfulChangeRegistersBeforeUpdatingAndPersistingChoice(rawValue: String) throws {
        let replacement = try #require(ShortcutChoice(rawValue: rawValue))
        try withTestDefaults { defaults in
            defaults.set(ShortcutChoice.optionSpace.rawValue, forKey: "shortcut")
            let state = makeState(defaults: defaults)
            var registrations: [ShortcutChoice] = []

            let changed = state.changeShortcut(to: replacement) { choice in
                registrations.append(choice)
                #expect(state.shortcut == .optionSpace)
                #expect(defaults.string(forKey: "shortcut") == ShortcutChoice.optionSpace.rawValue)
                #expect(makeState(defaults: defaults).shortcut == .optionSpace)
            }

            #expect(changed)
            #expect(registrations == [replacement])
            #expect(state.shortcut == replacement)
            #expect(defaults.string(forKey: "shortcut") == replacement.rawValue)
            #expect(makeState(defaults: defaults).shortcut == replacement)
            #expect(state.shortcutError == nil)
        }
    }

    @Test(arguments: [false, true])
    func failedRegistrationPreservesChoiceAndDefaults(hasSavedChoice: Bool) throws {
        try withTestDefaults { defaults in
            if hasSavedChoice {
                defaults.set(ShortcutChoice.optionSpace.rawValue, forKey: "shortcut")
            }
            let state = makeState(defaults: defaults)
            let previousChoice = state.shortcut
            let previousDefault = defaults.string(forKey: "shortcut")
            var registrations: [ShortcutChoice] = []

            let changed = state.changeShortcut(to: .commandShiftSpace) { choice in
                registrations.append(choice)
                #expect(state.shortcut == previousChoice)
                #expect(defaults.string(forKey: "shortcut") == previousDefault)
                throw ShortcutUnavailable()
            }

            #expect(!changed)
            #expect(registrations == [.commandShiftSpace])
            #expect(state.shortcut == previousChoice)
            #expect(defaults.string(forKey: "shortcut") == previousDefault)
            #expect(makeState(defaults: defaults).shortcut == previousChoice)
            #expect(state.shortcutError == ShortcutUnavailable().localizedDescription)
        }
    }

    @Test func successfulRetryPersistsChoiceAndClearsRegistrationError() throws {
        try withTestDefaults { defaults in
            let state = makeState(defaults: defaults)
            #expect(!state.changeShortcut(to: .optionSpace) { _ in throw ShortcutUnavailable() })
            try #require(state.shortcutError != nil)
            var registrations: [ShortcutChoice] = []

            let changed = state.changeShortcut(to: .optionSpace) { choice in
                registrations.append(choice)
                #expect(state.shortcut == .controlSpace)
                #expect(defaults.string(forKey: "shortcut") == nil)
            }

            #expect(changed)
            #expect(registrations == [.optionSpace])
            #expect(state.shortcut == .optionSpace)
            #expect(defaults.string(forKey: "shortcut") == ShortcutChoice.optionSpace.rawValue)
            #expect(state.shortcutError == nil)
            let restored = makeState(defaults: defaults)
            #expect(restored.shortcut == .optionSpace)
            #expect(restored.shortcutError == nil)
        }
    }

    private func makeState(defaults: UserDefaults) -> PanelState {
        PanelState(
            conversation: ConversationSession(backend: ControlledAssistantBackend(), defaults: defaults),
            defaults: defaults
        )
    }
}

private struct ShortcutUnavailable: LocalizedError {
    var errorDescription: String? { "That shortcut is already in use. Choose another shortcut." }
}
