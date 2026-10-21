import Foundation
import Testing
@testable import Pocket

@MainActor
struct DemoAssistantBackendTests {
    @Test func emitsNonemptyTextInMultipleDeltas() async throws {
        let backend = DemoAssistantBackend(delay: { _ in })
        var deltas: [String] = []
        try await backend.reply(to: [ConversationMessage(role: .user, text: "Hello")]) {
            deltas.append($0)
        }
        #expect(deltas.count > 1)
        #expect(deltas.allSatisfy { !$0.isEmpty })
        #expect(!deltas.joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test func cancelledReplyThrowsWithoutEmittingText() async throws {
        let backend = DemoAssistantBackend(delay: { _ in })
        var deltas: [String] = []
        let reply = Task {
            try await backend.reply(to: [ConversationMessage(role: .user, text: "Hello")]) {
                deltas.append($0)
            }
        }
        reply.cancel()
        do {
            try await reply.value
            Issue.record("Cancelled demo reply completed successfully")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(deltas.isEmpty)
    }
}
