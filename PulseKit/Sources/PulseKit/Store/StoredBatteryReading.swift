import Foundation
import SwiftData

/// The band's battery level at a connection or sync, for the battery history chart.
@Model
public final class StoredBatteryReading {
    public var date: Date
    public var percent: Int

    init(date: Date, percent: Int) {
        self.date = date
        self.percent = percent
    }
}

public struct BatteryReading: Sendable, Equatable {
    public let date: Date
    public let percent: Int

    public init(date: Date, percent: Int) {
        self.date = date
        self.percent = percent
    }
}
