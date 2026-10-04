import Foundation
import Testing
@testable import PulseKit

struct BackgroundSyncTests {
    let now = utcDate(2026, 10, 4, 12, 0)

    @Test func runsWhenDueAndIdle() {
        #expect(BackgroundSync.shouldRun(lastExport: now - 4000, lastAttempt: nil, paired: true, busy: false, now: now))
    }

    @Test func skipsWithinTheHourOfAnAttempt() {
        #expect(!BackgroundSync.shouldRun(lastExport: now - 9000, lastAttempt: now - 600, paired: true, busy: false, now: now))
    }

    @Test func skipsWhenBusyOrUnpaired() {
        #expect(!BackgroundSync.shouldRun(lastExport: nil, lastAttempt: nil, paired: true, busy: true, now: now))
        #expect(!BackgroundSync.shouldRun(lastExport: nil, lastAttempt: nil, paired: false, busy: false, now: now))
    }
}
