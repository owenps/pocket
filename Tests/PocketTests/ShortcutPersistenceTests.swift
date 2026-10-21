import Foundation
import Testing
@testable import Pocket

@MainActor
struct ShortcutPersistenceTests {
    @Test(arguments: ["commandShiftSpace", "40:1048576"])
    func savedShortcutRestoresChoice(savedValue: String) throws {
        try withTestDefaults { defaults in
            defaults.set(savedValue, forKey: "shortcut")
            let session = ConversationSession(backend: ControlledAssistantBackend(), defaults: defaults)
            let state = PanelState(conversation: session, defaults: defaults)
            let expected = try #require(ShortcutChoice(rawValue: savedValue))
            #expect(state.shortcut == expected)
            #expect(state.shortcutError == nil)
        }
    }

    @Test(arguments: [nil, "removed-shortcut", "doubleTap:55"] as [String?])
    func missingOrUnknownShortcutUsesDefaultWithoutError(savedValue: String?) throws {
        try withTestDefaults { defaults in
            if let savedValue { defaults.set(savedValue, forKey: "shortcut") }
            let session = ConversationSession(backend: ControlledAssistantBackend(), defaults: defaults)
            let state = PanelState(conversation: session, defaults: defaults)
            #expect(state.shortcut == .controlSpace)
            #expect(state.shortcutError == nil)
        }
    }
}
