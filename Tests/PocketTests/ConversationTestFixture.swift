import Foundation
import Testing
@testable import Pocket

@MainActor
func withConversationFixture(
    backend: ControlledAssistantBackend? = nil,
    _ body: @MainActor (ConversationSession, ControlledAssistantBackend, UserDefaults) async throws -> Void
) async throws {
    let name = "ConversationTestFixture.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let backend = backend ?? ControlledAssistantBackend()
    let session = ConversationSession(backend: backend, defaults: defaults)
    let result: Result<Void, any Error>
    do {
        try await body(session, backend, defaults)
        result = .success(())
    } catch {
        result = .failure(error)
    }
    session.stopReply()
    try await backend.drain()
    try result.get()
}
