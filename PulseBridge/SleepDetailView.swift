import Charts
import PulseKit
import SwiftUI

struct SleepDetailView: View {
    let service: SummaryService
    @State private var span: DaySpan = .day
    @State private var day: Date

    init(service: SummaryService, day: Date? = nil) {
        self.service = service
        _day = State(initialValue: Calendar.current.startOfDay(for: day ?? .now))
    }
    @State private var metrics: DailyMetrics?
    @State private var error: String?
    @State private var showScoreInfo = false
    @State private var insight: Insight?
    /// Last night's temperature and the usual of the nights before (needs 5).
    @State private var temperature: (last: Double, usual: Double)?

    var body: some View {
        List {
            Section {
                DayRangeHeader(span: $span, day: $day, firstDay: metrics?.days.first, spans: [.day, .week, .month])
            }
            if let insight {
                TopicInsightRow(insight: insight)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            } else if span == .day {
                if let metrics, let night = metrics.sleep(on: day), let score = metrics.sleepScore(on: day) {
                    nightSections(night, score: score, metrics: metrics)
                } else {
                    Text("No sleep data").foregroundStyle(.secondary)
                }
            } else {
                trendSections(metrics?.sleepSeries() ?? [])
            }
        }
        .navigationTitle("Sleep")
        .toolbar {
            Button { showScoreInfo = true } label: { Image(systemName: "info.circle") }
        }
        .sheet(isPresented: $showScoreInfo) { ScoreInfo() }
        .task(id: "\(span.rawValue)\(day.timeIntervalSince1970)") { load() }
    }

    // MARK: D

    @ViewBuilder private func nightSections(_ night: SleepNight, score: SleepScore, metrics: DailyMetrics) -> some View {
        // Once per night, for the Timing list and the chart markers.
        let wakeUps = SleepAnalysis.estimatedWakeUps(night, heartRate: metrics.readings(.heartRate, during: night))
        Section("Sleep score (estimate)") {
            HStack(spacing: 16) {
                ScoreRing(score: score.value, size: 80)
                VStack(alignment: .leading) {
                    Text(score.label).font(.title3.bold())
                    Text("\(hoursAndMinutes(night.asleep)) asleep").foregroundStyle(.secondary)
                }
            }
            ForEach(SleepScore.Contributor.allCases, id: \.self) { contributor in
                let value = score.contributors[contributor] ?? 0
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent(contributor.title, value: detail(contributor, night, score))
                    Text(contributor.summary).font(.caption).foregroundStyle(.secondary)
                    ProgressView(value: Double(value), total: 100).tint(scoreColor(value))
                }
            }
        }
        Section("Stages (Deep/REM split is an estimate)") {
            Chart(night.segments) { segment in
                RectangleMark(xStart: .value("Start", segment.start), xEnd: .value("End", segment.end),
                              y: .value("Stage", segment.stage.title))
                    .foregroundStyle(segment.stage.color)
            }
            .chartYScale(domain: SleepStage.chartOrder.map(\.title))
            .frame(height: 160)
            ForEach(SleepStage.chartOrder, id: \.self) { stage in
                let minutes = night.minutes[stage] ?? 0
                let share = stage == .awake ? Double(minutes) / Double(max(1, night.inBed)) : night.share(stage)
                LabeledContent {
                    Text("\(hoursAndMinutes(minutes)) · \(Int((share * 100).rounded()))%")
                } label: {
                    Label { Text(stage.title) } icon: { Circle().fill(stage.color).frame(width: 10) }
                    Text("typical \(stage.typicalRange)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        Section("Timing") {
            LabeledContent("Fell asleep", value: night.fellAsleep.formatted(date: .omitted, time: .shortened))
            LabeledContent("Woke up", value: night.wokeUp.formatted(date: .omitted, time: .shortened))
            LabeledContent("In bed", value: hoursAndMinutes(night.inBed))
            LabeledContent("Efficiency", value: "\(Int((night.efficiency * 100).rounded()))%")
            LabeledContent("Time to fall asleep", value: "\(night.latency) min")
            LabeledContent("Awakenings", value: "\(night.awakenings)")
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("Wake-ups (estimated)", value: "\(wakeUps.count)")
                ForEach(wakeUps) { wakeUp in
                    Text("\(wakeUp.date.formatted(date: .omitted, time: .shortened)) · \(wakeUp.bpm) bpm, \(wakeUp.reason.text)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("From heart-rate rises the band's stages explain; the band itself rarely marks waking in the night.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        Section("Night vitals") {
            let heart = metrics.readings(.heartRate, during: night)
            let lowest = metrics.lowestHeartRate(on: day)
            if heart.isEmpty {
                Text("No heart-rate readings during the night").foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(heart, id: \.date) { LineMark(x: .value("Time", $0.date), y: .value("bpm", $0.value)) }
                    ForEach(wakeUps) { wakeUp in
                        PointMark(x: .value("Time", wakeUp.date), y: .value("bpm", wakeUp.bpm))
                            .symbol(.triangle)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Estimated wake-up \(wakeUp.date.formatted(date: .omitted, time: .shortened)), \(wakeUp.bpm) bpm")
                    }
                    if let lowest {
                        PointMark(x: .value("Time", lowest.date), y: .value("bpm", lowest.value))
                            .annotation(position: .bottom) { Text("\(Int(lowest.value))").font(.caption2) }
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .foregroundStyle(.red)
                .chartScrub(heart.map { .time($0.date, "\(Int($0.value)) bpm") })
                .frame(height: 140)
            }
            NavigationLink(value: SummaryRoute.metric(.restingHeartRate, day: day)) {
                LabeledContent("Resting heart rate", value: metrics.restingHeartRate(on: day).map { "\($0) bpm" } ?? "-")
            }
            NavigationLink(value: SummaryRoute.metric(.temperature, day: day)) {
                LabeledContent("Temperature", value: temperatureText(metrics.nightTemperature(on: day)))
            }
            let hrv = metrics.readings(.hrv, during: night)
            if !hrv.isEmpty {
                Chart(hrv, id: \.date) {
                    PointMark(x: .value("Time", $0.date), y: .value("ms", $0.value))
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .foregroundStyle(.blue)
                .frame(height: 100)
            }
            NavigationLink(value: SummaryRoute.metric(.hrv, day: day)) {
                LabeledContent("HRV (average asleep)", value: metrics.hrv(on: day).map { "\($0) ms" } ?? "-")
            }
        }
    }

    private func detail(_ contributor: SleepScore.Contributor, _ night: SleepNight, _ score: SleepScore) -> String {
        let percent = { (value: Double) in "\(Int((value * 100).rounded()))%" }
        switch contributor {
        case .totalSleep: return hoursAndMinutes(night.asleep)
        case .efficiency: return percent(night.efficiency)
        case .restfulness: return String(localized: "\(night.awakeAfterOnset) min awake · \(night.longAwakenings) wake-ups")
        case .rem: return percent(night.share(.rem))
        case .deep: return percent(night.share(.deep))
        case .latency: return "\(night.latency) min"
        case .regularity:
            let mid = night.midpoint.formatted(date: .omitted, time: .shortened)
            guard let usual = score.usualMidpoint else { return String(localized: "midpoint \(mid)") }
            let usualText = String(format: "%02d:%02d", usual / 60, usual % 60)
            return String(localized: "midpoint \(mid) · usual \(usualText)")
        }
    }

    // MARK: W / M

    @ViewBuilder private func trendSections(_ nights: [NightValue]) -> some View {
        if nights.isEmpty {
            Text("No sleep data").foregroundStyle(.secondary)
        } else {
            Section("Stages per night") {
                Chart {
                    ForEach(nights) { value in
                        ForEach(SleepStage.chartOrder.reversed(), id: \.self) { stage in
                            BarMark(x: .value("Night", value.day, unit: .day),
                                    y: .value("Hours", Double(value.night.minutes[stage] ?? 0) / 60))
                                .foregroundStyle(by: .value("Stage", stage.title))
                        }
                    }
                }
                .chartForegroundStyleScale(domain: SleepStage.chartOrder.map(\.title),
                                           range: SleepStage.chartOrder.map(\.color))
                .chartScrub(nights.map { .day($0.day, "\(hoursAndMinutes($0.night.asleep)) · score \($0.score.value)") })
                .frame(height: 200)
            }
            Section("Averages") {
                LabeledContent("Time asleep", value: hoursAndMinutes(nights.map(\.night.asleep).reduce(0, +) / nights.count))
                LabeledContent("Sleep score", value: "\(nights.map(\.score.value).reduce(0, +) / nights.count)")
                LabeledContent("Fell asleep", value: averageClock(nights.map(\.night.fellAsleep)))
                LabeledContent("Woke up", value: averageClock(nights.map(\.night.wokeUp)))
                LabeledContent("Bedtime consistency", value: "± \(Int(bedtimeSpread(nights.map(\.night.fellAsleep)))) min")
            }
            Section("Resting heart rate") {
                let resting = metrics?.series(.restingHeartRate) ?? []
                Chart(resting) {
                    LineMark(x: .value("Day", $0.day, unit: .day), y: .value("bpm", $0.range.average))
                    PointMark(x: .value("Day", $0.day, unit: .day), y: .value("bpm", $0.range.average))
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .foregroundStyle(.pink)
                .chartScrub(resting.map { .day($0.day, "\(Int($0.range.average)) bpm") })
                .frame(height: 120)
            }
        }
    }

    /// Minutes after noon, so times around midnight average correctly.
    private func minutesAfterNoon(_ date: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double(((c.hour! + 12) % 24) * 60 + c.minute!)
    }

    private func averageClock(_ dates: [Date]) -> String {
        let average = dates.map(minutesAfterNoon).reduce(0, +) / Double(dates.count)
        let minutes = (Int(average.rounded()) + 12 * 60) % (24 * 60)
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private func bedtimeSpread(_ dates: [Date]) -> Double {
        let values = dates.map(minutesAfterNoon)
        let mean = values.reduce(0, +) / Double(values.count)
        return (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)).squareRoot()
    }

    /// "36.4 °C · +0.3 vs usual"
    private func temperatureText(_ night: Double?) -> String {
        guard let night else { return "-" }
        let value = "\(Metric.temperature.format(night)) °C"
        guard let temperature else { return value }
        return String(localized: "\(value) · \(Insights.signedCelsius(temperature.last - temperature.usual)) vs usual")
    }

    private func load() {
        do {
            metrics = try service.load(days: span.days, endingOn: day)
            // One longer load for the insight and the temperature baseline.
            let series = (try? service.load(days: SummaryModel.loadedDays, endingOn: day))?.insightSeries() ?? [:]
            insight = Insights.make(series, today: day, calendar: .current).first { $0.topic == .sleep }
            temperature = Insights.usual(series[.temperature], today: day, calendar: .current)
            error = nil
        } catch {
            self.error = String(localized: "Couldn't load data: \(error.localizedDescription)")
        }
    }
}

private struct ScoreInfo: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Text("An estimate in the style of Oura's sleep score, with this app's own published formula. Each contributor scores 0-100; the score is their weighted average. Ranges follow the National Sleep Foundation's sleep quality recommendations (Ohayon 2017) and the AASM's 7+ hours. Stages count little because wrist bands can't tell deep sleep from REM reliably.")
                ForEach(SleepScore.Contributor.allCases, id: \.self) { c in
                    LabeledContent(c.title, value: "\(c.weight)%")
                }
                Text("Full marks: 7-9 h asleep; efficiency 90%+; 20 min or less awake after falling asleep and at most 1 wake-up over 5 min; sleep midpoint within 30 min of your usual (median of the last 14 nights; 00:00-03:00 until there are 3 nights); 5-30 min to fall asleep; REM 21-40%; deep 16%+. Nights under 6 h score at most 70.")
                    .font(.footnote)
                Text("85+ Optimal · 70-84 Good · 60-69 Fair · under 60 Pay attention").font(.footnote)
            }
            .navigationTitle("Sleep score")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

extension EstimatedWakeUp.Reason {
    var text: String {
        switch self {
        case .outOfREM: String(localized: "coming out of REM")
        case .awake: String(localized: "the band marked awake")
        case .outOfDeepSleep: String(localized: "out of deep sleep")
        case .highHeartRate: String(localized: "well above the night's typical heart rate")
        }
    }
}
