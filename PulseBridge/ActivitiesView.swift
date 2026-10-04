import PulseKit
import SwiftUI

extension WorkoutActivity {
    var title: String {
        switch self {
        case .running: "Run"
        case .cycling: "Ride"
        case .walking: "Walk"
        case .hiking: "Hike"
        case .other: "Activity"
        }
    }

    var systemImage: String {
        switch self {
        case .running: "figure.run"
        case .cycling: "figure.outdoor.cycle"
        case .walking: "figure.walk"
        case .hiking: "figure.hiking"
        case .other: "figure.mixed.cardio"
        }
    }
}

extension Workout {
    var durationText: String {
        let s = info.seconds
        return s >= 3600 ? "\(s / 3600)h \(String(format: "%02d", s % 3600 / 60))m" : "\(s / 60)m \(String(format: "%02d", s % 60))s"
    }

    var distanceText: String {
        roadDistanceText(Double(info.distanceMeters))
    }

    /// Minutes per km, e.g. 11'20".
    var paceText: String? {
        guard info.distanceMeters > 0 else { return nil }
        let perKm = Double(info.seconds) / (Double(info.distanceMeters) / 1000)
        return String(format: "%d'%02d\"/km", Int(perKm) / 60, Int(perKm) % 60)
    }
}

/// Latest activity and this week's count, for Summary, with a Start button.
struct ActivitiesCard: View {
    /// Newest first (the 7 loaded days).
    let workouts: [Workout]
    let onStart: () -> Void

    var body: some View {
        Card(title: "Activities", systemImage: "figure.walk.motion", color: .green) {
            NavigationLink(value: SummaryRoute.activities) {
                VStack(alignment: .leading, spacing: 8) {
                    if let latest = workouts.first {
                        HStack(spacing: 12) {
                            Image(systemName: latest.info.activity.systemImage).font(.title2).foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(latest.info.activity.title) · \(latest.durationText)").font(.headline)
                                Text("\(latest.start.formatted(date: .abbreviated, time: .shortened)) · \(latest.info.steps.formatted()) steps · \(latest.distanceText)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        Text("\(workouts.count) in the last 7 days").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("No activities in the last 7 days").foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } accessory: {
            Button("Start", systemImage: "play.fill", action: onStart)
                .font(.caption.bold())
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.small)
        }
    }
}

/// All activities of the last 30 days, grouped by day.
struct ActivitiesView: View {
    let service: SummaryService
    @State private var workouts: [Workout] = []
    /// Decoded once per load, not on every redraw.
    @State private var recorded: [(id: UUID, recorder: ActivityRecorder)] = []
    @State private var error: String?

    private var days: [(Date, [Workout])] {
        Dictionary(grouping: workouts) { Calendar.current.startOfDay(for: $0.start) }
            .sorted { $0.key > $1.key }
            .map { ($0.key, $0.value.sorted { $0.start > $1.start }) }
    }

    var body: some View {
        List {
            if let error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            } else if workouts.isEmpty && recorded.isEmpty {
                Text("No activities in the last 30 days").foregroundStyle(.secondary)
            }
            if !recorded.isEmpty {
                Section("Recorded with GPS") {
                    ForEach(recorded, id: \.id) { item in
                        NavigationLink { ActivitySummaryView(recorder: item.recorder) } label: {
                            RecordedActivityRow(recorder: item.recorder)
                        }
                    }
                }
            }
            ForEach(days, id: \.0) { day, items in
                Section(day.formatted(date: .complete, time: .omitted)) {
                    ForEach(items) { ActivityRow(workout: $0) }
                }
            }
        }
        .navigationTitle("Activities")
        .task { load() }
    }

    private func load() {
        do {
            workouts = try service.load(days: 30, endingOn: .now).workouts()
            recorded = ((try? service.store.activities(from: Date.now.addingTimeInterval(-30 * 86400), to: .now)) ?? [])
                .compactMap { stored in stored.recorder.map { (stored.id, $0) } }
            error = nil
        } catch {
            self.error = "Couldn't load data: \(error.localizedDescription)"
        }
    }
}

private struct ActivityRow: View {
    let workout: Workout

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: workout.info.activity.systemImage)
                .font(.title3).foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Palette.activity.gradient, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(workout.info.activity.title).font(.headline)
                    Spacer()
                    Text("\(workout.start.formatted(date: .omitted, time: .shortened)) - \(workout.end.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text([workout.durationText, "\(workout.info.steps.formatted()) steps", workout.distanceText, workout.paceText]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                Text([workout.info.heartRate > 0 ? "avg \(workout.info.heartRate) bpm" : nil,
                      workout.info.calories > 0 ? "\(Int(workout.info.calories)) kcal" : nil]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// A GPS activity: route thumbnail, then title, date, distance, time and pace.
private struct RecordedActivityRow: View {
    let recorder: ActivityRecorder

    private var end: Date { recorder.end ?? recorder.start }

    var body: some View {
        HStack(spacing: 12) {
            if recorder.points.count > 1 {
                RouteMap(points: recorder.points, interactive: false)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Image(systemName: recorder.activity.systemImage)
                    .font(.title2).foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Palette.activity.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(recorder.activity.title).font(.headline)
                Text(recorder.start.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                Text("\(kmText(recorder.distance)) · \(clockText(recorder.movingTime(at: end))) · \(paceText(recorder.averagePace(at: end))) /km")
                    .font(.subheadline).monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }
}
