import Foundation
import PulseKit

/// The daily challenge as a message for the group chat, in the app's language:
///
///     💪 Daily challenge · Tue 7 Oct
///     ✅ Push-ups: 60/60
///     ⏳ Squats: 40/60
///     🔥 6-day streak
///     📅 39 days done · day 42
enum ChallengeShareText {
    static func make(_ summary: ChallengeShareSummary) -> String {
        let date = summary.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        var lines = [String(localized: "💪 Daily challenge · \(date)")]
        for item in summary.items {
            lines.append("\(item.done ? "✅" : "⏳") \(item.name): \(item.total)/\(item.target)")
        }
        if summary.streak > 0 { lines.append(String(localized: "🔥 \(summary.streak)-day streak")) }
        lines.append(String(localized: "📅 \(summary.daysDone) days done · day \(summary.challengeDay)"))
        return lines.joined(separator: "\n")
    }
}
