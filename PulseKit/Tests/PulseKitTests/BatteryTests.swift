import Foundation
import Testing
@testable import PulseKit

@MainActor
struct BatteryTests {
    let store: RecordStore
    let t0 = utcDate(2026, 10, 4, 8, 0)

    init() throws {
        store = RecordStore(container: try RecordStore.container(inMemory: true))
    }

    @Test func keepsOneReadingPer15Minutes() throws {
        try store.recordBattery(90, at: t0)
        try store.recordBattery(89, at: t0 + 600)          // too soon: skipped
        try store.recordBattery(88, at: t0 + 900)
        #expect(try store.batteryReadings(since: t0 - 1).map(\.percent) == [90, 88])
    }

    @Test func dropsReadingsOlderThan90Days() throws {
        try store.recordBattery(90, at: t0 - 91 * 86400)
        try store.recordBattery(80, at: t0)
        #expect(try store.batteryReadings(since: .distantPast).map(\.percent) == [80])
    }

    @Test func drainPerDay() {
        let r = [BatteryReading(date: t0, percent: 90), BatteryReading(date: t0 + 86400, percent: 80),
                 BatteryReading(date: t0 + 2 * 86400, percent: 70)]
        #expect(BatteryDrain.perDay(r) == 10)
    }

    @Test func chargingIsExcluded() {
        let r = [BatteryReading(date: t0, percent: 50), BatteryReading(date: t0 + 86400, percent: 40),
                 BatteryReading(date: t0 + 86400 + 3600, percent: 100),          // charged
                 BatteryReading(date: t0 + 2 * 86400 + 3600, percent: 90)]
        #expect(BatteryDrain.perDay(r) == 10)
    }

    @Test func needsTwoDays() {
        let r = [BatteryReading(date: t0, percent: 90), BatteryReading(date: t0 + 86400, percent: 80)]
        #expect(BatteryDrain.perDay(r) == nil)
    }
}
