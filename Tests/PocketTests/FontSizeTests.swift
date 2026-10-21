import AppKit
import Testing
@testable import Pocket

@MainActor
struct FontSizeTests {
    @Test func preferenceDefaultsToNativeBodyAndSurvivesRecreation() throws {
        try withTestDefaults { defaults in
            let state = makeState(defaults)
            #expect(state.fontSize == Double(NSFont.preferredFont(forTextStyle: .body).pointSize))
            state.fontSize = 19.5
            #expect(defaults.double(forKey: "fontSize") == 19.5)
            #expect(makeState(defaults).fontSize == 19.5)
        }
    }

    @Test func preferenceClampsFiniteValuesAndRejectsNonfiniteChanges() throws {
        try withTestDefaults { defaults in
            let state = makeState(defaults)
            state.fontSize = 100
            #expect(state.fontSize == PanelState.fontSizeRange.upperBound)
            state.fontSize = -100
            #expect(state.fontSize == PanelState.fontSizeRange.lowerBound)
            state.fontSize = 18
            for invalid in [Double.nan, .infinity, -.infinity] {
                state.fontSize = invalid
                #expect(state.fontSize == 18)
                #expect(defaults.double(forKey: "fontSize") == 18)
            }
        }
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, -10, 100])
    func savedPreferenceIsValidated(value: Double) throws {
        try withTestDefaults { defaults in
            defaults.set(value, forKey: "fontSize")
            let expected = value.isFinite
                ? min(PanelState.fontSizeRange.upperBound, max(PanelState.fontSizeRange.lowerBound, value))
                : PanelState.defaultFontSize
            let state = makeState(defaults)
            #expect(state.fontSize == expected)
            #expect(state.editorHeight == DraftEditor.singleLineHeight(fontSize: expected))
            #expect(state.composerHeight == max(state.editorHeight, state.avatar.size.points))
        }
    }

    @Test func malformedSavedPreferenceUsesNativeBodySize() throws {
        try withTestDefaults { defaults in
            defaults.set("not a size", forKey: "fontSize")
            #expect(makeState(defaults).fontSize == PanelState.defaultFontSize)
        }
    }

    private func makeState(_ defaults: UserDefaults) -> PanelState {
        PanelState(conversation: ConversationSession(backend: ControlledAssistantBackend(), defaults: defaults), defaults: defaults)
    }
}
