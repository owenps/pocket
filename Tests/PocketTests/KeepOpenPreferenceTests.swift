import Testing
@testable import Pocket

@MainActor
struct KeepOpenPreferenceTests {
    @Test func defaultsOffAndPersistsBothChoices() throws {
        try withTestDefaults { defaults in
            @MainActor func makeState() -> PanelState {
                PanelState(
                    conversation: ConversationSession(backend: ControlledAssistantBackend(), defaults: defaults),
                    defaults: defaults
                )
            }

            let state = makeState()
            #expect(!state.keepOpenWhenUnfocused)
            state.keepOpenWhenUnfocused = true
            #expect(makeState().keepOpenWhenUnfocused)
            state.keepOpenWhenUnfocused = false
            #expect(!makeState().keepOpenWhenUnfocused)
        }
    }
}
