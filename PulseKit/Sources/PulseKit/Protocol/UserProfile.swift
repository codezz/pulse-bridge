import Foundation

public enum Sex: Int, Codable, Sendable, CaseIterable {
    case female = 0, male = 1
}

/// The user's profile, as the band stores it (`42` reads, `02` writes). Age is kept as a birth year.
public struct UserProfile: Codable, Sendable, Equatable {
    public var birthYear: Int
    public var sex: Sex
    public var heightCm: Int
    public var weightKg: Int
    /// The band's stride for step-based distance (not edited in the app; kept as the band reports it).
    public var stepLengthCm: Int

    public init(birthYear: Int, sex: Sex, heightCm: Int, weightKg: Int, stepLengthCm: Int) {
        self.birthYear = birthYear
        self.sex = sex
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.stepLengthCm = stepLengthCm
    }

    public func age(at date: Date, calendar: Calendar) -> Int {
        calendar.component(.year, from: date) - birthYear
    }

    public init?(bandPacket: Data, now: Date, calendar: Calendar) {
        let b = [UInt8](bandPacket)
        guard b.count >= 6, b[0] == Opcode.readProfile, let sex = Sex(rawValue: Int(b[1])) else { return nil }
        self.init(birthYear: calendar.component(.year, from: now) - Int(b[2]), sex: sex,
                  heightCm: Int(b[3]), weightKg: Int(b[4]), stepLengthCm: Int(b[5]))
    }

    public func command(at date: Date, calendar: Calendar) -> Data {
        Frame.make([Opcode.setProfile, UInt8(sex.rawValue), UInt8(clamping: age(at: date, calendar: calendar)),
                    UInt8(clamping: heightCm), UInt8(clamping: weightKg), UInt8(clamping: stepLengthCm)])
    }
}
