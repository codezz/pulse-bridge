import Foundation
import Testing
@testable import PulseKit

struct LocalizedTests {
    @Test func picksTheRequestedLanguage() {
        #expect(L("Steady", language: "en") == "Steady")
        #expect(L("Steady", language: "ro") == "Constant")
    }

    /// Romanian has three plural forms; 20 and up take "de" (but 101 does not).
    @Test func romanianPlurals() {
        let cases: [(Int, String)] = [(0, "acum 0 zile"), (1, "acum 1 zi"), (2, "acum 2 zile"), (19, "acum 19 zile"), (20, "acum 20 de zile"), (101, "acum 101 zile")]
        for (count, expected) in cases {
            #expect(L("\(count) days ago", language: "ro") == expected)
        }
        #expect(L("\(1) days ago", language: "en") == "1 day ago")
    }

    /// Tests run in English even on a Mac set to Romanian: the default follows the main bundle
    /// (the app, or the test runner), not the Mac's preferred languages.
    @Test func defaultIsTheAppLanguage() {
        #expect(L("Steady") == "Steady")
    }

    @Test(.disabled("Romanian values arrive with the translations")) func relativeTimeInRomanian() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(RelativeTime.text(now - 30, now: now, language: "ro") == "chiar acum")
        #expect(RelativeTime.text(now - 300, now: now, language: "ro") == "acum 5 min")
        #expect(RelativeTime.text(now - 7200, now: now, language: "ro") == "acum 2 h")
    }

    @Test(.disabled("Romanian values arrive with the translations")) func sleepLabelInRomanian() {
        #expect(SleepScore.label(for: 90, language: "ro") == "Optim")
    }
}
