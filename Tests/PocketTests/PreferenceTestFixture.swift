import Foundation
import Testing

@MainActor
func withTestDefaults<Result>(_ body: @MainActor (UserDefaults) throws -> Result) throws -> Result {
    let name = "PocketTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    return try body(defaults)
}
