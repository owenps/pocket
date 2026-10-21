import Foundation

@MainActor
public enum NativeUITestSupport {
    private static var isInUse = false

    public static func wait(timeout: TimeInterval = 2, until condition: () throws -> Bool) throws {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while true {
            if try condition() { return }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw PresentationTimeout(timeout: timeout) }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: min(0.008, remaining)))
        }
    }

    public static func withDesktop<T>(_ body: @MainActor () async throws -> T) async throws -> T {
        while isInUse {
            try await Task.sleep(for: .milliseconds(8))
        }
        try Task.checkCancellation()
        isInUse = true
        defer { isInUse = false }
        return try await body()
    }
}

private struct PresentationTimeout: LocalizedError, CustomStringConvertible {
    let timeout: TimeInterval

    var description: String { "Native UI condition was not satisfied within \(timeout) seconds." }
    var errorDescription: String? { description }
}
