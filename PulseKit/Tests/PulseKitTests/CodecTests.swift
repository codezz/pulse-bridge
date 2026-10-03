import Foundation
import Testing
@testable import PulseKit

struct FrameTests {
    @Test func padsAndAppendsChecksum() {
        #expect(Frame.make([0x41]) == bytes("41 00 00 00 00 00 00 00 00 00 00 00 00 00 00 41"))
    }

    @Test func checksumWrapsLikeTheCapturedSetTime() {
        // Captured 2026-10-02: 01 26 10 02 16 49 54 ... ec
        #expect(Frame.make([0x01, 0x26, 0x10, 0x02, 0x16, 0x49, 0x54]).last == 0xEC)
    }

    @Test func validatesCapturedAck() {
        #expect(Frame.isValid(bytes("01 f4 00 00 00 00 00 00 00 00 00 00 00 00 00 f5")))
        #expect(!Frame.isValid(bytes("01 f4 00 00 00 00 00 00 00 00 00 00 00 00 00 f6")))
    }

    @Test func recognisesDeviceEvents() {
        #expect(Frame.isDeviceEvent(bytes("16 07 01 00 00 00 00 00 00 00 00 00 00 00 00 1e")))
        #expect(!Frame.isDeviceEvent(bytes("16 07 01")))
        #expect(!Frame.isDeviceEvent(bytes("55 00 00 26 06 16 18 06 14 47 00 00 00 00 00 00")))
    }

    @Test func refusesForbiddenOpcodes() async {
        await #expect(processExitsWith: .failure) { _ = Frame.make([0x12]) }
        await #expect(processExitsWith: .failure) { _ = Frame.make([0x2E]) }
        await #expect(processExitsWith: .failure) { _ = Frame.make([0x61]) }
    }

    @Test func setTimeCommand() {
        #expect(Command.setTime(utcDate(2026, 10, 2, 16, 49, 54), in: utc)
            == bytes("01 26 10 02 16 49 54 00 00 00 00 00 00 00 00 ec"))
    }
}

struct BCDTests {
    @Test func encodesDate() {
        #expect(BCD.encode(utcDate(2026, 10, 2, 16, 49, 54), in: utc) == [0x26, 0x10, 0x02, 0x16, 0x49, 0x54])
    }

    @Test func decodesDateAndTime() {
        #expect(BCD.date([0x26, 0x06, 0x16, 0x18, 0x06, 0x14], in: utc) == utcDate(2026, 6, 16, 18, 6, 14))
    }

    @Test func decodesDateOnlyAsMidnight() {
        #expect(BCD.date([0x26, 0x03, 0x20], in: utc) == utcDate(2026, 3, 20))
    }

    @Test func rejectsNonBCDNibbles() {
        #expect(BCD.date([0x26, 0x1A, 0x01], in: utc) == nil)
    }

    @Test func rejectsImpossibleDates() {
        #expect(BCD.date([0x26, 0x02, 0x30], in: utc) == nil)
        #expect(BCD.date([0x26, 0x01, 0x01, 0x25, 0x00, 0x00], in: utc) == nil)
    }
}

struct HeartRateMeasurementTests {
    @Test func parsesUInt8Format() { #expect(HeartRateMeasurement.bpm(from: bytes("00 3c")) == 60) }
    @Test func parsesUInt16Format() { #expect(HeartRateMeasurement.bpm(from: bytes("01 2c 01")) == 300) }
    @Test func rejectsTruncated() {
        #expect(HeartRateMeasurement.bpm(from: Data()) == nil)
        #expect(HeartRateMeasurement.bpm(from: bytes("01 2c")) == nil)
    }
}
