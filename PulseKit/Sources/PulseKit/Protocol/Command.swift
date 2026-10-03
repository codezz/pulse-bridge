import Foundation

public enum Opcode {
    public static let setTime: UInt8 = 0x01
    public static let realTimeActivity: UInt8 = 0x09
    public static let measurement: UInt8 = 0x28
    public static let setProfile: UInt8 = 0x02
    public static let vibrate: UInt8 = 0x36
    public static let readProfile: UInt8 = 0x42
    /// Factory reset, MCU reset, clear all data. Never sent.
    public static let forbidden: Set<UInt8> = [0x12, 0x2E, 0x61]
}

public enum Command {
    public static func setTime(_ date: Date, in timeZone: TimeZone) -> Data {
        Frame.make([Opcode.setTime] + BCD.encode(date, in: timeZone))
    }

    public static func history(_ kind: HistoryKind, mode: HistoryMode) -> Data {
        Frame.make([kind.rawValue, mode.rawValue])
    }

    /// While enabled the band sends one `09` packet per second with today's activity.
    public static func realTimeActivity(_ enabled: Bool) -> Data {
        Frame.make([Opcode.realTimeActivity, enabled ? 1 : 0, 0])
    }

    public static let readProfile = Frame.make([Opcode.readProfile])

    /// The band has no screen; buzzes are its only feedback. 2 is easy to miss; use 3 or more.
    public static func vibrate(times: Int) -> Data {
        Frame.make([Opcode.vibrate, UInt8(clamping: times)])
    }

    public static func measurement(_ kind: MeasurementKind, start: Bool) -> Data {
        Frame.make([Opcode.measurement, kind.rawValue, start ? 1 : 0])
    }
}
