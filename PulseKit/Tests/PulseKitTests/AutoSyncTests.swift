import Foundation
import Testing
@testable import PulseKit

struct AutoSyncTests {
    let now = utcDate(2026, 10, 2, 18, 0)

    @Test func dueWhenNeverSynced() { #expect(AutoSync.isDue(lastSync: nil, now: now)) }
    @Test func notDueWithinTheHour() { #expect(!AutoSync.isDue(lastSync: now.addingTimeInterval(-59 * 60), now: now)) }
    @Test func dueAfterAnHour() { #expect(AutoSync.isDue(lastSync: now.addingTimeInterval(-3600), now: now)) }
    @Test func dueWhenTheClockWentBackwards() { #expect(AutoSync.isDue(lastSync: now.addingTimeInterval(7200), now: now)) }
}
