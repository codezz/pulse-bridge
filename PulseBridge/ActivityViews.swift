import Charts
import CoreLocation
import MapKit
import PulseKit
import SwiftUI

func zoneColor(_ zone: Int) -> Color {
    switch zone {
    case 1: .blue
    case 2: .green
    case 3: .yellow
    case 4: .orange
    case 5: .red
    default: .gray
    }
}

func zoneName(_ zone: Int) -> String {
    switch zone {
    case 1: "very easy"
    case 2: "easy"
    case 3: "moderate"
    case 4: "hard"
    case 5: "max"
    default: "rest"
    }
}

func paceText(_ seconds: TimeInterval?) -> String {
    guard let seconds, seconds.isFinite, seconds < 3600 else { return "-" }
    return String(format: "%d'%02d\"", Int(seconds) / 60, Int(seconds) % 60)
}

/// Activity distance, e.g. "4.27 km".
func kmText(_ meters: Double) -> String { String(format: "%.2f km", meters / 1000) }

/// Everyday distance in the user's units, e.g. "4.3 km" or "2.7 mi".
func roadDistanceText(_ meters: Double) -> String {
    Measurement(value: meters, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road))
}

func clockText(_ seconds: TimeInterval) -> String {
    let s = Int(seconds)
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)
}

/// Pick an activity and a target zone, then start. Shown in a sheet from the Activities card.
struct StartActivityForm: View {
    let coordinator: SyncCoordinator
    let onStarted: () -> Void
    @State private var type = WorkoutActivity.running
    @State private var zone: Int? = 2
    @State private var zoneAlerts = true
    @State private var hr: HeartRateProfile?
    @State private var location = LocationAuthorization()
    @Environment(\.openURL) private var openURL

    private var locationDenied: Bool { [.denied, .restricted].contains(location.status) }

    var body: some View {
        Form {
            Section {
                Picker("Activity", selection: $type) {
                    Text("Run").tag(WorkoutActivity.running)
                    Text("Walk").tag(WorkoutActivity.walking)
                    Text("Ride").tag(WorkoutActivity.cycling)
                }
                .pickerStyle(.segmented)
                Picker("Target", selection: $zone) {
                    Text("Free").tag(Int?.none)
                    ForEach(1...5, id: \.self) { z in
                        if let hr {
                            let range = hr.zones.range(of: z)
                            Text("Zone \(z) · \(range.lowerBound)-\(range.upperBound) bpm").tag(Int?.some(z))
                        } else {
                            Text("Zone \(z)").tag(Int?.some(z))
                        }
                    }
                }
                if zone != nil {
                    Toggle(isOn: $zoneAlerts) {
                        Text("Zone alerts on the band")
                        Text("3 buzzes above the zone, 2 below").font(.caption)
                    }
                }
            }
            Section {
                if coordinator.profile == nil {
                    Text("Set your age in Band > Profile for accurate zones.").font(.caption).foregroundStyle(.secondary)
                }
                if coordinator.band.state != .connected {
                    Text("Band not connected: GPS only, no heart rate.").font(.caption).foregroundStyle(.orange)
                }
                if locationDenied {
                    Text("Allow location to record distance and the route.").font(.caption).foregroundStyle(.orange)
                    Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
                } else if location.accuracy == .reducedAccuracy {
                    Text("Turn on Precise Location for Pulse Bridge in Settings; approximate location can't measure distance.")
                        .font(.caption).foregroundStyle(.orange)
                }
                Button {
                    onStarted()
                    Task { await coordinator.startActivity(type, targetZone: zone, zoneAlerts: zoneAlerts) }
                } label: {
                    Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(coordinator.phase.isBusy || coordinator.live.isMeasuring || locationDenied)
            }
        }
        .navigationTitle("Start activity")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { hr = coordinator.heartRateProfile() }
    }
}

/// Full screen while an activity runs, then its summary.
struct ActivityCover: View {
    let coordinator: SyncCoordinator
    @State private var confirmDiscard = false

    var body: some View {
        if let session = coordinator.activity {
            ActivityLiveView(session: session, coordinator: coordinator)
        } else if let finished = coordinator.finishedActivity {
            NavigationStack {
                ActivitySummaryView(recorder: finished.recorder)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Discard", role: .destructive) { confirmDiscard = true }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") { Task { await coordinator.closeFinishedActivity(save: true) } }
                        }
                    }
                    .confirmationDialog("Discard this activity? It won't be saved or sent to Health.", isPresented: $confirmDiscard,
                                        titleVisibility: .visible) {
                        Button("Discard", role: .destructive) { Task { await coordinator.closeFinishedActivity(save: false) } }
                    }
            }
        }
    }
}

private struct ActivityLiveView: View {
    let session: ActivitySession
    let coordinator: SyncCoordinator
    @State private var confirmFinish = false
    /// Kept outside the 1 s timeline so the shown page survives each tick.
    @State private var page = 0

    private var recorder: ActivityRecorder { session.recorder }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: recorder.activity.systemImage)
                Text("\(recorder.activity.title)\(recorder.targetZone.map { " · Zone \($0)" } ?? "")")
                if session.zoneAlerts {
                    Image(systemName: "bell.fill").accessibilityLabel("Zone alerts on")
                }
            }
            .font(.headline).foregroundStyle(Palette.activity)
            // Swipe between the main numbers, heart rate and splits; the controls stay put.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                TabView(selection: $page) {
                    mainPage(at: context.date).tag(0)
                    heartRate(at: context.date).padding().tag(1)
                    splitsPage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            }
            if session.locationDenied {
                Text("Allow location in Settings to record distance and the route.").font(.caption).foregroundStyle(.orange)
            } else if (session.gpsAccuracy ?? 99) > ActivityRecorder.maxAccuracy {
                Text("Waiting for GPS...").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                if recorder.state == .paused {
                    Button { session.resume() } label: { Label("Resume", systemImage: "play.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(.green)
                } else {
                    Button { session.pause() } label: { Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                }
                Button(role: .destructive) { confirmFinish = true } label: {
                    Label("Finish", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        }
        .padding()
        .confirmationDialog("Finish this activity?", isPresented: $confirmFinish) {
            Button("Finish", role: .destructive) { coordinator.finishActivity() }
        }
    }

    private func mainPage(at now: Date) -> some View {
        VStack(spacing: 24) {
            Text(clockText(recorder.movingTime(at: now)))
                .numberFont(72, weight: .bold).monospacedDigit()
                .foregroundStyle(recorder.state == .paused ? .secondary : .primary)
            HStack {
                stat(String(format: "%.2f", recorder.distance / 1000), "km")
                stat(paceText(recorder.currentPace(at: now)), "pace /km")
                stat(paceText(recorder.averagePace(at: now)), "avg /km")
            }
            if let bpm = session.heartRate(at: now) {
                Label("\(bpm) bpm", systemImage: "heart.fill")
                    .font(.title3.bold())
                    .foregroundStyle(zoneColor(recorder.zones.zone(for: bpm)))
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var splitsPage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Splits").font(.title2.bold())
            if recorder.splitDurations.isEmpty {
                Text("Your first kilometre shows here.").foregroundStyle(.secondary)
            }
            ScrollView {
                ForEach(Array(recorder.splitDurations.enumerated().reversed()), id: \.offset) { index, seconds in
                    HStack {
                        Text("Km \(index + 1)").font(.headline)
                        Spacer()
                        Text("\(paceText(seconds)) /km").font(.title3.bold()).monospacedDigit()
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
            }
        }
        .padding()
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private func heartRate(at now: Date) -> some View {
        let bpm = session.heartRate(at: now)
        let zone = bpm.map { recorder.zones.zone(for: $0) }
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "heart.fill").foregroundStyle(zone.map(zoneColor) ?? .gray)
                Text(bpm.map(String.init) ?? "-").numberFont(80)
                Text("bpm").foregroundStyle(.secondary)
            }
            if let zone {
                Text(status(zone)).font(.headline).foregroundStyle(zoneColor(zone))
            }
            if let target = recorder.targetZone {
                let moving = max(1, recorder.movingTime(at: now))
                ProgressView(value: min(1, recorder.timeInTarget / moving)) {
                    Text("In zone \(target): \(clockText(recorder.timeInTarget))").font(.caption)
                }
                .tint(zoneColor(target))
            }
        }
    }

    private func status(_ zone: Int) -> String {
        guard let target = recorder.targetZone else { return "Zone \(zone) · \(zoneName(zone))" }
        if zone == target { return "In zone \(target)" }
        return zone > target ? "Above zone \(target): ease off" : "Below zone \(target): pick it up"
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack {
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Finished activity: map, totals, zones and splits.
struct ActivitySummaryView: View {
    let recorder: ActivityRecorder

    private var end: Date { recorder.end ?? .now }

    var body: some View {
        List {
            let points = recorder.points
            if points.count > 1 {
                RouteMap(points: points)
                    .frame(height: 220)
                .listRowInsets(EdgeInsets())
            }
            Section {
                LabeledContent("Distance", value: kmText(recorder.distance))
                LabeledContent("Moving time", value: clockText(recorder.movingTime(at: end)))
                LabeledContent("Average pace", value: "\(paceText(recorder.averagePace(at: end))) /km")
                LabeledContent("Heart rate", value: "avg \(recorder.averageHeartRate.map(String.init) ?? "-") · max \(recorder.maxHeartRate.map(String.init) ?? "-") bpm")
                if let target = recorder.targetZone {
                    LabeledContent("Time in zone \(target)", value: clockText(recorder.timeInTarget))
                }
            }
            if !recorder.timeInZone.isEmpty {
                Section("Time in zones") {
                    Chart((0...5).filter { (recorder.timeInZone[$0] ?? 0) > 0 }, id: \.self) { zone in
                        BarMark(x: .value("Minutes", (recorder.timeInZone[zone] ?? 0) / 60), y: .value("Zone", "Z\(zone)"))
                            .foregroundStyle(zoneColor(zone))
                    }
                    .frame(height: 160)
                }
            }
            if !recorder.splitDurations.isEmpty {
                Section("Splits") {
                    ForEach(Array(recorder.splitDurations.enumerated()), id: \.offset) { index, seconds in
                        LabeledContent("Km \(index + 1)", value: "\(paceText(seconds)) /km")
                    }
                }
            }
        }
        .navigationTitle("\(recorder.activity.title) · \(recorder.start.formatted(date: .abbreviated, time: .shortened))")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The route of a GPS activity. `interactive: false` for list thumbnails.
struct RouteMap: View {
    let points: [GeoPoint]
    var interactive = true

    var body: some View {
        Map(interactionModes: interactive ? .all : []) {
            MapPolyline(coordinates: points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
                .stroke(Palette.activity, lineWidth: interactive ? 4 : 3)
        }
        .allowsHitTesting(interactive)
        .accessibilityLabel("Route map")
    }
}
