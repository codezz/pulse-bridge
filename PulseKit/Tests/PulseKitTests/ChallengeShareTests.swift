import Foundation
import Testing
@testable import PulseKit

struct ChallengeShareTests {
    private func summary(_ items: [(String, Int, Int)], streak: Int, done: Int = 37, day: Int = 42) -> ChallengeShareSummary {
        ChallengeShareSummary(day: Date(timeIntervalSince1970: 0), items: items.map { .init(name: $0.0, total: $0.1, target: $0.2) },
                              streak: streak, daysDone: done, challengeDay: day)
    }

    @Test func romanianCompactText() {
        let s = summary([("Flotări", 60, 60), ("Genuflexiuni", 60, 60)], streak: 5)
        #expect(s.text(language: "ro") == "💪 Ziua 37/42. 5 zile la rând\n✅ 60F/60G")
    }

    @Test func romanianStreakPlurals() {
        let one = summary([("Flotări", 60, 60)], streak: 1).text(language: "ro")
        let twenty = summary([("Flotări", 60, 60)], streak: 20).text(language: "ro")
        #expect(one.hasPrefix("💪 Ziua 37/42. 1 zi la rând\n"))
        #expect(twenty.hasPrefix("💪 Ziua 37/42. 20 de zile la rând\n"))
    }

    /// Not done yet: hourglass; no streak: the day alone.
    @Test func unfinishedDayWithoutStreak() {
        let s = summary([("Flotări", 40, 60), ("Genuflexiuni", 60, 60)], streak: 0, done: 36)
        #expect(s.text(language: "ro") == "💪 Ziua 36/42\n⏳ 40F/60G")
    }

    @Test func englishCompactText() {
        let s = summary([("Push-ups", 60, 60), ("squats", 45, 60)], streak: 5)
        #expect(s.text(language: "en") == "💪 Day 37/42. 5-day streak\n⏳ 60P/45S")
    }

    /// The app's default exercises take the share language's letter, whatever language they were named in.
    @Test func defaultExercisesUseTheShareLanguage() {
        let english = summary([("Push-ups", 60, 60), ("Squats", 60, 60)], streak: 5)
        #expect(english.text(language: "ro").hasSuffix("✅ 60F/60G"))
        let romanian = summary([("Flotări", 60, 60), ("genuflexiuni", 50, 60)], streak: 5)
        #expect(romanian.text(language: "en").hasSuffix("⏳ 60P/50S"))
    }

    @Test func ownNamesKeepTheirLetter() {
        let s = summary([("Abdomene", 30, 30), ("Push-ups", 60, 60)], streak: 2)
        #expect(s.text(language: "ro").hasSuffix("✅ 30A/60F"))
    }

    @Test func defaultNamesPerLanguage() {
        #expect(ChallengeDefaults.exerciseNames(language: "ro") == ["Flotări", "Genuflexiuni"])
        #expect(ChallengeDefaults.exerciseNames(language: "en") == ["Push-ups", "Squats"])
    }
}
