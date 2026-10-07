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
        let cases: [(Int, String)] = [(0, "0 zile"), (1, "1 zi"), (2, "2 zile"), (19, "19 zile"), (20, "20 de zile"), (101, "101 zile")]
        for (count, expected) in cases {
            #expect(L("\(count) days", language: "ro") == expected)
        }
        #expect(L("\(1) days", language: "en") == "1 day")
    }

    /// Tests run in English even on a Mac set to Romanian: the default follows the main bundle
    /// (the app, or the test runner), not the Mac's preferred languages.
    @Test func defaultIsTheAppLanguage() {
        #expect(L("Steady") == "Steady")
    }
}
