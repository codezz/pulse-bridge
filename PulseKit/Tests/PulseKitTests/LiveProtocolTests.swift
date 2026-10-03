import Foundation
import Testing
@testable import PulseKit

struct LiveProtocolTests {
    @Test func realTimeActivityCommands() {
        // Captured writes 2026-10-02 19:11:39
        #expect(Command.realTimeActivity(true) == bytes("09 01 00 00 00 00 00 00 00 00 00 00 00 00 00 0a"))
        #expect(Command.realTimeActivity(false) == bytes("09 00 00 00 00 00 00 00 00 00 00 00 00 00 00 09"))
    }

    @Test func measurementCommands() {
        #expect(Command.measurement(.heartRate, start: true) == bytes("28 02 01 00 00 00 00 00 00 00 00 00 00 00 00 2b"))
        #expect(Command.measurement(.hrv, start: false) == bytes("28 01 00 00 00 00 00 00 00 00 00 00 00 00 00 29"))
    }

    @Test func parsesCapturedActivityPacket() throws {
        let packet = bytes("09 4a 00 00 00 51 10 02 00 05 00 00 00 26 00 00 00 00 00 00 00 00 00 00 00 00 00 3e 47 00")
        let a = try #require(LiveActivity(packet: packet))
        #expect(a.steps == 74)
        #expect(a.distanceMeters == 50)
        #expect(a.calories == 1352.49)
        #expect(a.activeTime == 38)
        #expect(a.heartRate == 62)
    }

    @Test func activityRejectsShortOrForeignPackets() {
        #expect(LiveActivity(packet: bytes("09 00 00 00 00 00 00 00 00 00 00 00 00 00 00 09")) == nil)
        #expect(LiveActivity(packet: bytes("55 00 00 26 10 02 19 18 20 3e")) == nil)
    }

    @Test func parsesMeasurementProgressAndResult() {
        // Captured 2026-10-02 19:48:13: final HRV packet
        let hrv = Frame.make([0x28, 0x01, 0x57, 0x00, 0x20, 0x39, 0x78, 0x4b, 0xe9])
        #expect(MeasurementUpdate(packet: hrv) == .progress(MeasurementValues(
            kind: .hrv, heartRate: 87, hrv: 32, stress: 57, systolic: 120, diastolic: 75)))
        let hr = Frame.make([0x28, 0x02, 0x58, 0, 0, 0, 0, 0, 0xe9])
        #expect(MeasurementUpdate(packet: hr) == .progress(MeasurementValues(
            kind: .heartRate, heartRate: 88, hrv: 0, stress: 0, systolic: 0, diastolic: 0)))
        #expect(MeasurementUpdate(packet: bytes("28 ff 00 00 00 00 00 00 00 00 00 00 00 00 00 27")) == .finished)
    }

    @Test func measurementRejectsUnknownKindsAndOtherOpcodes() {
        #expect(MeasurementUpdate(packet: Frame.make([0x28, 0x03, 0x4d])) == nil) // SpO2: unsupported
        #expect(MeasurementUpdate(packet: bytes("16 07 01 00 00 00 00 00 00 00 00 00 00 00 00 1e")) == nil)
    }

    @Test func readingNeedsAHeartRate() {
        #expect(!MeasurementValues(kind: .heartRate, heartRate: 0, hrv: 0, stress: 0, systolic: 0, diastolic: 0).hasReading)
        #expect(MeasurementValues(kind: .heartRate, heartRate: 88, hrv: 0, stress: 0, systolic: 0, diastolic: 0).hasReading)
    }
}
