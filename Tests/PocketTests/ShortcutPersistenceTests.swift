import Foundation
import Testing
@testable import Pocket

@MainActor
struct ShortcutPersistenceTests {
    @Test(arguments: [nil, "removed-shortcut"] as [String?])
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
