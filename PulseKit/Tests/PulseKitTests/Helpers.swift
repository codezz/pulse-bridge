import Foundation
@testable import PulseKit

/// "41 00 ff" -> Data([0x41, 0x00, 0xff])
func bytes(_ hex: String) -> Data {
    Data(hex.split(separator: " ").map { UInt8($0, radix: 16)! })
}

/// Hex prefix zero-padded to a full record size.
func padded(_ hex: String, to size: Int) -> Data {
    let head = bytes(hex)
    return head + Data(count: size - head.count)
}

let utc = TimeZone(identifier: "UTC")!

func utcDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    return calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
}

/// A record of `kind` starting at `date` (UTC), with `payload` after the 9-byte header.
func makeRecord(_ kind: HistoryKind, _ date: Date, _ payload: [UInt8]) -> HistoryRecord {
    var raw: [UInt8] = [kind.rawValue, 0, 0] + BCD.encode(date, in: utc) + payload
    raw += [UInt8](repeating: 0, count: kind.recordSize - raw.count)
    return HistoryRecord(kind: kind, start: date, raw: Data(raw))
}
