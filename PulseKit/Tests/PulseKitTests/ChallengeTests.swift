import Foundation
import Testing
@testable import PulseKit

struct ChallengeTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = utc
        c.firstWeekday = 2
        return c
    }
    // Monday 5 Oct 2026
    let monday = utcDate(2026, 10, 5)
    let push = UUID(), squat = UUID()

    private func day(_ offset: Int, _ hour: Int = 12) -> Date { monday + Double(offset) * 86400 + Double(hour) * 3600 }

    private func exercise(_ id: UUID, created: Int = -30, archived: Int? = nil, _ changes: [TargetChange]) -> ExerciseInfo {
        ExerciseInfo(id: id, name: id == push ? "Push-ups" : "Squats", unit: .reps,
                     createdAt: day(created, 0), archivedAt: archived.map { day($0, 0) }, changes: changes)
    }

    private func change(_ offset: Int, _ target: Int, step: Int = 0, weekday: Int? = nil) -> TargetChange {
        TargetChange(day: day(offset, 0), target: target, autoStep: step, autoWeekday: weekday)
    }

    @Test func targetUsesTheLatestChangeAndKeepsPastDays() {
        let e = exercise(push, [change(-10, 60), change(0, 70)])
        let h = ChallengeHistory(exercises: [e], sets: [], calendar: calendar)
        #expect(h.target(of: e, on: day(-1)) == 60)
        #expect(h.target(of: e, on: day(0)) == 70)
        #expect(h.target(of: e, on: day(-11)) == nil)
    }

    @Test func autoGrowthStartsAfterTheChangeDay() {
        // +5 every Monday (weekday 2), set on Monday 5 Oct
        let e = exercise(push, [change(0, 60, step: 5, weekday: 2)])
        let h = ChallengeHistory(exercises: [e], sets: [], calendar: calendar)
        #expect(h.target(of: e, on: day(0)) == 60)
        #expect(h.target(of: e, on: day(6)) == 60)
        #expect(h.target(of: e, on: day(7)) == 65)
        #expect(h.target(of: e, on: day(15)) == 70)
    }

    /// Two years of daily sets with weekly growth: the streak must stay instant (it runs on every tap).
    @Test func streaksStayFastWithAutoGrowth() {
        let es = [exercise(push, created: -730, [change(-730, 10, step: 1, weekday: 2)]),
                  exercise(squat, created: -730, [change(-730, 10, step: 1, weekday: 2)])]
        let sets = (-730...0).flatMap { [SetInfo(exerciseID: push, date: day($0), count: 500), SetInfo(exerciseID: squat, date: day($0), count: 500)] }
        let h = ChallengeHistory(exercises: es, sets: sets, calendar: calendar)
        let start = Date()
        #expect(h.bestStreak(today: day(0)) == 731)
        #expect(h.streak(today: day(0)) == 731)
        #expect(Date().timeIntervalSince(start) < 0.2)
        // Day -730 is a Saturday: 105 Mondays from day -728 up to today (a Monday): 10 + 105
        #expect(h.target(of: es[0], on: day(0)) == 115)
        #expect(h.target(of: es[0], on: day(-1)) == 114)
    }

    @Test func statusDonePartialNone() {
        let es = [exercise(push, [change(-10, 60)]), exercise(squat, [change(-10, 60)])]
        let sets = [SetInfo(exerciseID: push, date: day(0, 9), count: 40), SetInfo(exerciseID: push, date: day(0, 18), count: 20),
                    SetInfo(exerciseID: squat, date: day(0, 10), count: 60),
                    SetInfo(exerciseID: push, date: day(-1, 10), count: 10)]
        let h = ChallengeHistory(exercises: es, sets: sets, calendar: calendar)
        #expect(h.total(of: push, on: day(0)) == 60)
        #expect(h.status(on: day(0)) == .done)
        #expect(h.status(on: day(-1)) == .partial)
        #expect(h.status(on: day(-2)) == .none)
    }

    @Test func archivedExerciseStopsCounting() {
        let es = [exercise(push, [change(-10, 60)]), exercise(squat, archived: 0, [change(-10, 60)])]
        let sets = [SetInfo(exerciseID: push, date: day(0), count: 60), SetInfo(exerciseID: push, date: day(-1), count: 60)]
        let h = ChallengeHistory(exercises: es, sets: sets, calendar: calendar)
        #expect(h.status(on: day(0)) == .done)       // squats archived today
        #expect(h.status(on: day(-1)) == .partial)   // squats still active yesterday
    }

    @Test func streakIgnoresUnfinishedToday() {
        let e = exercise(push, [change(-10, 10)])
        let sets = [-3, -2, -1].map { SetInfo(exerciseID: push, date: day($0), count: 10) }
            + [SetInfo(exerciseID: push, date: day(-6), count: 10)]
        let h = ChallengeHistory(exercises: [e], sets: sets, calendar: calendar)
        #expect(h.streak(today: day(0)) == 3)
        let done = ChallengeHistory(exercises: [e], sets: sets + [SetInfo(exerciseID: push, date: day(0), count: 10)], calendar: calendar)
        #expect(done.streak(today: day(0)) == 4)
        #expect(done.bestStreak(today: day(0)) == 4)
        #expect(ChallengeHistory(exercises: [e], sets: [], calendar: calendar).streak(today: day(0)) == 0)
    }

    @Test func progressOfADay() {
        let e = exercise(push, [change(-10, 60)])
        let h = ChallengeHistory(exercises: [e], sets: [SetInfo(exerciseID: push, date: day(0), count: 70)], calendar: calendar)
        #expect(h.progress(of: e, on: day(0)) == ChallengeProgress(total: 70, target: 60))
        #expect(h.progress(of: e, on: day(0)).isDone)
        #expect(!h.progress(of: e, on: day(-1)).isDone)
        #expect(!ChallengeProgress(total: 0, target: 0).isDone)     // no target yet
    }

    /// "This week" starts on Monday whatever the phone's locale says.
    @Test func weeksStartOnMonday() {
        var sundayFirst = calendar
        sundayFirst.firstWeekday = 1
        let h = ChallengeHistory(exercises: [], sets: [], calendar: sundayFirst)
        let week = h.week(containing: day(-1))            // Sunday 4 Oct
        #expect(week.start == utcDate(2026, 9, 28))       // Monday
        #expect(week.end == utcDate(2026, 10, 5))
    }

    /// Progress from before the app: started 39 days ago, 33 days done, streak 1 and best 14 then.
    private func withBaseline(_ sets: [SetInfo]) -> ChallengeHistory {
        let e = exercise(push, created: 0, [change(0, 60)])
        let baseline = ChallengeBaseline(startDate: day(-38, 0), daysDoneBefore: 33, streakBefore: 1, bestBefore: 14)
        return ChallengeHistory(exercises: [e], sets: sets, calendar: calendar, baseline: baseline)
    }

    @Test func baselineCarriesStreakDaysAndBest() {
        let h = withBaseline([SetInfo(exerciseID: push, date: day(0), count: 60)])
        #expect(h.streak(today: day(0)) == 2)
        #expect(h.bestStreak(today: day(0)) == 14)
        #expect(h.daysDone(today: day(0)) == 34)
        #expect(h.challengeDay(today: day(0)) == 39)
        #expect(h.isBeforeTracking(day(-5)))
        #expect(!h.isBeforeTracking(day(0)))
        #expect(!h.isBeforeTracking(day(-40)))           // before the challenge started
    }

    @Test func baselineStreakContinuesAndBreaks() {
        let next = [0, 1].map { SetInfo(exerciseID: push, date: day($0), count: 60) }
        #expect(withBaseline(next).streak(today: day(1)) == 3)
        #expect(withBaseline(next).streak(today: day(2)) == 3)               // tomorrow not done yet
        #expect(withBaseline(next).streak(today: day(3)) == 0)               // missed day 2
        // A run in the app that doesn't reach back to the first tracked day doesn't add the old streak.
        let gap = [SetInfo(exerciseID: push, date: day(0), count: 60), SetInfo(exerciseID: push, date: day(2), count: 60)]
        #expect(withBaseline(gap).streak(today: day(2)) == 1)
    }

    @Test func noBaselineNumbers() {
        let e = exercise(push, created: 0, [change(0, 60)])
        let h = ChallengeHistory(exercises: [e], sets: [SetInfo(exerciseID: push, date: day(0), count: 60)], calendar: calendar)
        #expect(h.daysDone(today: day(0)) == 1)
        #expect(h.challengeDay(today: day(0)) == 1)
        #expect(!h.isBeforeTracking(day(-1)))
    }

    @Test func periodTotals() {
        let e = exercise(push, [change(-10, 10)])
        let sets = [SetInfo(exerciseID: push, date: day(0), count: 10), SetInfo(exerciseID: push, date: day(6), count: 5),
                    SetInfo(exerciseID: push, date: day(7), count: 7)]
        let h = ChallengeHistory(exercises: [e], sets: sets, calendar: calendar)
        let week = calendar.dateInterval(of: .weekOfYear, for: day(2))!
        #expect(h.total(of: push, in: week) == 15)
        #expect(h.sets(on: day(0)).map(\.count) == [10])
    }
}
