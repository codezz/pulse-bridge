import Foundation
import Testing
@testable import PulseKit

struct ZoneAlertTests {
    let t0 = utcDate(2026, 10, 4, 8, 0)

    private func feed(_ alert: inout ZoneAlert, bpm: Int, seconds: ClosedRange<Int>) -> [ZoneAlert.Direction] {
        seconds.compactMap { alert.update(bpm: bpm, at: t0 + Double($0)) }
    }

    @Test func aboveFor15SecondsAlertsOnce() {
        var a = ZoneAlert(target: 120...131)
        #expect(feed(&a, bpm: 140, seconds: 0...14).isEmpty)
        #expect(a.update(bpm: 140, at: t0 + 15) == .above)
        #expect(feed(&a, bpm: 140, seconds: 16...74).isEmpty)       // under 60 s since the alert
        #expect(a.update(bpm: 140, at: t0 + 75) == .above)          // repeats after 60 s
    }

    @Test func belowAlertsToo() {
        var a = ZoneAlert(target: 120...131)
        #expect(feed(&a, bpm: 110, seconds: 0...15) == [.below])
    }

    @Test func backInsideResets() {
        var a = ZoneAlert(target: 120...131)
        _ = feed(&a, bpm: 140, seconds: 0...10)
        #expect(a.update(bpm: 125, at: t0 + 11) == nil)
        #expect(feed(&a, bpm: 140, seconds: 12...26).isEmpty)       // the 15 s start again
        #expect(a.update(bpm: 140, at: t0 + 27) == .above)
    }

    @Test func switchingDirectionRestartsTheTimer() {
        var a = ZoneAlert(target: 120...131)
        _ = feed(&a, bpm: 140, seconds: 0...10)
        #expect(feed(&a, bpm: 110, seconds: 11...25).isEmpty)
        #expect(a.update(bpm: 110, at: t0 + 26) == .below)
    }

    @Test func staleHeartRatePausesTheTimer() {
        var a = ZoneAlert(target: 120...131)
        _ = feed(&a, bpm: 140, seconds: 0...10)
        #expect(a.update(bpm: 140, at: t0 + 30) == nil)             // 20 s gap: starts over
        #expect(feed(&a, bpm: 140, seconds: 31...44).isEmpty)
        #expect(a.update(bpm: 140, at: t0 + 45) == .above)
    }

    @Test func buzzCounts() {
        #expect(ZoneAlert.buzzes(for: .above) == 3)
        #expect(ZoneAlert.buzzes(for: .below) == 2)
    }
}
