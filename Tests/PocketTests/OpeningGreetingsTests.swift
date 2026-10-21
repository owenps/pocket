import Foundation
import Testing
@testable import Pocket

struct OpeningGreetingsTests {
    @Test(arguments: ["", "   \n\t"])
    func blankNamesUseUnpersonalizedCopy(name: String) {
        let greetings = OpeningGreetings.messages(userName: name, hour: 20)
        #expect(!greetings.isEmpty)
        #expect(greetings.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        #expect(greetings == OpeningGreetings.messages(userName: "", hour: 20))
    }

    @Test(arguments: ["Owen", "  Owen \n", "李 明", "Élodie Rose"])
    func namesPersonalizeGreetingsWithoutChangingSpelling(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let greetings = OpeningGreetings.messages(userName: name, hour: 20)
        #expect(greetings.contains { $0.contains(trimmed) })
        #expect(greetings == OpeningGreetings.messages(userName: trimmed, hour: 20))
        let fallback = OpeningGreetings.messages(userName: "", hour: 20)
        #expect(greetings.contains { fallback.contains($0) })
    }

    @Test(arguments: ["", "Owen"], [
        (0, nil), (4, nil), (5, "Good morning"), (11, "Good morning"),
        (12, "Good afternoon"), (16, "Good afternoon"), (17, nil), (23, nil)
    ] as [(Int, String?)])
    func timeOfDayGreetingsFollowLocalHour(name: String, time: (Int, String?)) {
        let greetings = OpeningGreetings.messages(userName: name, hour: time.0)
        let timeGreetings = greetings.filter {
            $0.hasPrefix("Good morning") || $0.hasPrefix("Good afternoon")
        }
        let suffix = name.isEmpty ? "!" : ", \(name)!"
        #expect(timeGreetings == time.1.map { [$0 + suffix] } ?? [])
    }
}
