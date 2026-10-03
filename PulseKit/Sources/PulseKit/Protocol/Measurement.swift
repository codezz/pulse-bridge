import Foundation

/// On-demand measurements (`28 <type> 01`). SpO2 (type 3) returns no value on this firmware.
public enum MeasurementKind: UInt8, Sendable {
    case hrv = 0x01
    case heartRate = 0x02

    /// Measured on the band 2026-10-02; used for the progress ring.
    public var expectedDuration: TimeInterval {
        switch self {
        case .hrv: 75
        case .heartRate: 30
        }
    }
}

public struct MeasurementValues: Sendable, Equatable {
    public let kind: MeasurementKind
    public let heartRate: Int
    public let hrv: Int
    public let stress: Int
    public let systolic: Int
    public let diastolic: Int

    public init(kind: MeasurementKind, heartRate: Int, hrv: Int, stress: Int, systolic: Int, diastolic: Int) {
        self.kind = kind
        self.heartRate = heartRate
        self.hrv = hrv
        self.stress = stress
        self.systolic = systolic
        self.diastolic = diastolic
    }

    /// The band sends zeros until it has a reading.
    public var hasReading: Bool { heartRate > 0 }
}

/// One `28` packet: a progress update (`28 type hr spo2 hrv stress sys dia`) or `28 ff` (finished).
public enum MeasurementUpdate: Sendable, Equatable {
    case progress(MeasurementValues)
    case finished

    public init?(packet: Data) {
        let b = [UInt8](packet)
        guard b.count >= 8, b[0] == Opcode.measurement else { return nil }
        if b[1] == 0xFF {
            self = .finished
            return
        }
        guard let kind = MeasurementKind(rawValue: b[1]) else { return nil }
        self = .progress(MeasurementValues(kind: kind, heartRate: Int(b[2]), hrv: Int(b[4]), stress: Int(b[5]),
                                           systolic: Int(b[6]), diastolic: Int(b[7])))
    }
}
