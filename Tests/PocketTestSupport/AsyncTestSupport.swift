import Foundation

@MainActor
public enum AsyncTestSupport {
    public static func wait(timeout: TimeInterval = 2, until condition: () throws -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while true {
            if try condition() { return }
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                throw AsyncConditionTimeout(timeout: timeout)
            }
            try await Task.sleep(for: .milliseconds(1))
        }
    }
}

private struct AsyncConditionTimeout: LocalizedError, CustomStringConvertible {
    let timeout: TimeInterval

    var description: String { "Async condition was not satisfied within \(timeout) seconds." }
    var errorDescription: String? { description }
}
