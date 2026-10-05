import ActivityKit
import SwiftUI
import WidgetKit

@main
struct PulseBridgeWidgets: WidgetBundle {
    var body: some Widget {
        PulseLiveActivity()
    }
}

struct PulseLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PulseActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.6))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.title, systemImage: context.attributes.kind.systemImage)
                        .font(.caption.bold()).foregroundStyle(.mint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HeartRateText(state: context.state).font(.caption.bold())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(alignment: .firstTextBaseline) {
                        ElapsedText(state: context.state).font(.title.bold()).monospacedDigit()
                        Spacer()
                        Metrics(state: context.state)
                    }
                }
            } compactLeading: {
                // Heart rate when there is one, else the activity symbol; the time is on the right.
                if context.state.heartRate != nil {
                    HeartRateText(state: context.state).font(.caption.bold()).labelStyle(.titleAndIcon)
                } else {
                    Image(systemName: context.attributes.kind.systemImage).foregroundStyle(.mint)
                }
            } compactTrailing: {
                ElapsedText(state: context.state).monospacedDigit().frame(maxWidth: 56)
            } minimal: {
                Image(systemName: context.attributes.kind.systemImage).foregroundStyle(.mint)
            }
        }
    }
}

private struct LockScreenView: View {
    let attributes: PulseActivityAttributes
    let state: PulseActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(attributes.title, systemImage: attributes.kind.systemImage).font(.subheadline.bold()).foregroundStyle(.mint)
                Spacer()
                HeartRateText(state: state).font(.subheadline.bold())
            }
            HStack(alignment: .firstTextBaseline) {
                ElapsedText(state: state).font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                if state.timerStart == nil { Text("Paused").font(.caption.bold()).foregroundStyle(.secondary) }
                Spacer()
                Metrics(state: state)
            }
            if let status = state.status {
                Text(status).font(.caption.bold()).foregroundStyle(state.zone.map(zoneColor) ?? .secondary)
            }
        }
        .padding()
        .foregroundStyle(.white)
    }
}

/// Runs by itself (no updates needed) unless paused.
private struct ElapsedText: View {
    let state: PulseActivityAttributes.ContentState

    var body: some View {
        if let start = state.timerStart {
            Text(timerInterval: start...Date.distantFuture, countsDown: false)
        } else {
            Text(Duration.seconds(state.elapsed).formatted(.time(pattern: state.elapsed >= 3600 ? .hourMinuteSecond : .minuteSecond)))
        }
    }
}

private struct HeartRateText: View {
    let state: PulseActivityAttributes.ContentState

    var body: some View {
        Label(state.heartRate.map { "\($0)" } ?? "-", systemImage: "heart.fill")
            .foregroundStyle(state.zone.map(zoneColor) ?? .red)
    }
}

private struct Metrics: View {
    let state: PulseActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let meters = state.distanceMeters {
                Text(String(format: "%.2f km", meters / 1000)).font(.headline).monospacedDigit()
            }
            if let pace = state.paceSecondsPerKm, pace.isFinite, pace < 3600 {
                Text(String(format: "%d'%02d\" /km", Int(pace) / 60, Int(pace) % 60)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
