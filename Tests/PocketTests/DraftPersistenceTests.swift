import Foundation
import Testing
@testable import Pocket

@MainActor
struct DraftPersistenceTests {
    @Test func missingDraftStartsEmpty() throws {
        try withTestDefaults { defaults in
            #expect(makeSession(defaults).draft.isEmpty)
        }
    }

    @Test(arguments: ["", " \t\n ", "  Remember to follow up\nAsk about Friday  "])
    func latestDraftSurvivesOwnerRecreationVerbatim(draft: String) throws {
        try withTestDefaults { defaults in
            let session = makeSession(defaults)
            session.draft = "Previous thought"
            session.draft = draft

            #expect(defaults.string(forKey: "draft") == draft)
            #expect(makeSession(defaults).draft == draft)
        }
    }

    private func makeSession(_ defaults: UserDefaults) -> ConversationSession {
        ConversationSession(backend: ControlledAssistantBackend(), defaults: defaults)
    }
}
