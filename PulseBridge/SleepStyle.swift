import PulseKit
import SwiftUI

extension SleepStage {
    /// Top to bottom in the stage chart, like Apple Health.
    static let chartOrder: [SleepStage] = [.awake, .rem, .core, .deep]

    var title: String {
        switch self {
        case .awake: "Awake"
        case .rem: "REM"
        case .core: "Core"
        case .deep: "Deep"
        }
    }

    var color: Color {
        switch self {
        case .awake: Color(red: 1.0, green: 0.48, blue: 0.40)
        case .rem: Color(red: 0.25, green: 0.78, blue: 0.95)
        case .core: Color(red: 0.16, green: 0.48, blue: 1.0)
        case .deep: Color(red: 0.24, green: 0.20, blue: 0.70)
        }
    }

    /// Typical share of time asleep for adults (awake: of time in bed).
    var typicalRange: String {
        switch self {
        case .awake: "under 10%"
        case .rem: "20-25%"
        case .core: "about 50%"
        case .deep: "13-23%"
        }
    }
}

extension SleepScore.Contributor {
    var title: String {
        switch self {
        case .totalSleep: "Total sleep"
        case .efficiency: "Efficiency"
        case .restfulness: "Restfulness"
        case .rem: "REM sleep"
        case .deep: "Deep sleep"
        case .latency: "Latency"
        case .regularity: "Regularity"
        }
    }

    /// One line on what it measures and what full marks need.
    var summary: String {
        switch self {
        case .totalSleep: "Time asleep; 7-9 h for full marks"
        case .efficiency: "Share of time in bed spent asleep; 90% or more for full marks"
        case .restfulness: "Awake time and wake-ups over 5 min; 20 min or less and 0-1 wake-ups is ideal"
        case .rem: "REM share of sleep (band estimate); 21-40% is typical"
        case .deep: "Deep share of sleep (band estimate); 16% or more is typical"
        case .latency: "Time to fall asleep; 5-30 min is ideal"
        case .regularity: "Middle of your sleep vs your last 14 nights; within 30 min is ideal"
        }
    }
}

func scoreColor(_ value: Int) -> Color {
    switch value {
    case 85...: .green
    case 70..<85: .teal
    case 60..<70: .orange
    default: .red
    }
}

func hoursAndMinutes(_ minutes: Int) -> String {
    "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
}

struct ScoreRing: View {
    let score: Int?
    var size: CGFloat = 64

    var body: some View {
        ProgressRing(progress: Double(score ?? 0) / 100, color: scoreColor(score ?? 0), size: size) {
            Text(score.map(String.init) ?? "-").font(.system(size: size / 3, weight: .bold, design: .rounded))
        }
        .accessibilityLabel("Score")
        .accessibilityValue(score.map { "\($0) of 100" } ?? "none")
    }
}

/// One thin bar with each stage's share of the night.
struct StageBar: View {
    let night: SleepNight

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(SleepStage.chartOrder, id: \.self) { stage in
                    let minutes = night.minutes[stage] ?? 0
                    if minutes > 0 {
                        stage.color.frame(width: geo.size.width * CGFloat(minutes) / CGFloat(max(1, night.inBed)))
                    }
                }
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
        .accessibilityElement()
        .accessibilityLabel("Sleep stages")
        .accessibilityValue(SleepStage.chartOrder.compactMap { stage in
            night.minutes[stage].flatMap { $0 > 0 ? "\(stage.title) \(hoursAndMinutes($0))" : nil }
        }.joined(separator: ", "))
    }
}
