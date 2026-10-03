import Foundation

/// The band stores dates as BCD bytes: 0x26 0x03 0x27 = 2026-03-27.
public enum BCD {
    public static func byte(_ value: Int) -> UInt8 {
        UInt8((value / 10) << 4 | (value % 10))
    }

    public static func value(_ byte: UInt8) -> Int? {
        let high = Int(byte >> 4), low = Int(byte & 0x0F)
        return high < 10 && low < 10 ? high * 10 + low : nil
    }

    /// `[YY, MM, DD, hh, mm, ss]` in the given time zone.
    public static func encode(_ date: Date, in timeZone: TimeZone) -> [UInt8] {
        let c = calendar(timeZone).dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return [c.year! % 100, c.month!, c.day!, c.hour!, c.minute!, c.second!].map(byte)
    }

    /// Decodes 3 bytes (date, midnight) or 6 bytes (date and time). Nil if not a real date.
    public static func date<C: Collection>(_ bytes: C, in timeZone: TimeZone) -> Date? where C.Element == UInt8 {
        let digits = bytes.compactMap(value)
        guard digits.count == bytes.count, digits.count == 3 || digits.count == 6 else { return nil }
        var components = DateComponents(year: 2000 + digits[0], month: digits[1], day: digits[2])
        if digits.count == 6 {
            components.hour = digits[3]
            components.minute = digits[4]
            components.second = digits[5]
        }
        let cal = calendar(timeZone)
        guard components.isValidDate(in: cal) else { return nil }
        return cal.date(from: components)
    }

    private static func calendar(_ timeZone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }
}
