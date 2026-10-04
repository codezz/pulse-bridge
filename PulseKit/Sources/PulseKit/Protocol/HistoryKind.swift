/// History opcodes the app reads. Values from docs/protocol.md.
public enum HistoryKind: UInt8, CaseIterable, Sendable {
    case dailyTotals = 0x51
    case activity = 0x52
    case sleep = 0x53
    case continuousHR = 0x54
    case spotHR = 0x55
    case hrv = 0x56
    case spo2 = 0x66
    /// Workouts: walks the band detects by itself, or sessions started on the band or phone.
    case workout = 0x5C

    public var recordSize: Int {
        switch self {
        case .dailyTotals: 27
        case .activity: 25
        case .sleep: 130
        case .continuousHR: 24
        case .spotHR, .spo2: 10
        case .hrv: 15
        case .workout: 25
        }
    }

    /// BCD timestamp position. Daily totals have a 1-byte index and a date only.
    var timestampRange: Range<Int> { self == .dailyTotals ? 2..<5 : 3..<9 }

    /// Order from the spec: Health-relevant data first. Daily totals (`51`) aren't read: the
    /// 10-minute activity records hold the same steps and distance for longer, and nothing uses the
    /// band's calorie estimate.
    public static let syncOrder: [HistoryKind] = [.activity, .continuousHR, .spotHR, .hrv, .spo2, .sleep, .workout]
}

public enum HistoryMode: UInt8, Sendable {
    case newest = 0x00
    case next = 0x02
}
