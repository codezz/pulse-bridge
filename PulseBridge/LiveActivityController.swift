@preconcurrency import ActivityKit
import Foundation
import PulseKit

/// Starts, updates and ends the Live Activity. Updates are pushed at most every 5 s, except right
/// away when pausing or resuming changes the clock.
@MainActor
final class LiveActivityController {
    static let updateInterval: TimeInterval = 5

    private var activity: Activity<PulseActivityAttributes>?
    /// The last ended one, still showing its final numbers, until dismissed (Discard).
    private var finished: Activity<PulseActivityAttributes>?
    private var ticker: Task<Void, Never>?
    private var lastPush = Date.distantPast
    private var lastPaused = false

    /// Live Activities left over from a run the app didn't end (killed): dismiss them.
    func endStale() {
        for stale in Activity<PulseActivityAttributes>.activities {
            Task { await stale.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// `state` is asked once a second; it's sent when 5 s passed or the pause state changed.
    func start(kind: PulseActivityAttributes.Kind, title: String, state: @escaping () -> PulseActivityAttributes.ContentState) {
        end(dismissNow: true)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let first = state()
        activity = try? Activity.request(attributes: PulseActivityAttributes(kind: kind, title: title),
                                         content: ActivityContent(state: first, staleDate: nil))
        guard activity != nil else { return }      // not allowed or failed: nothing to update
        lastPush = .now
        lastPaused = first.timerStart == nil
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.tick(state())
            }
        }
    }

    private func tick(_ state: PulseActivityAttributes.ContentState) {
        guard let activity else { return }
        let paused = state.timerStart == nil
        guard paused != lastPaused || Date.now.timeIntervalSince(lastPush) >= Self.updateInterval else { return }
        lastPush = .now
        lastPaused = paused
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    /// Finish: the final numbers stay on the Lock Screen for 15 minutes. Cancel: gone now.
    func end(final state: PulseActivityAttributes.ContentState? = nil, dismissNow: Bool = false) {
        ticker?.cancel()
        ticker = nil
        guard let activity else { return }
        self.activity = nil
        finished = dismissNow ? nil : activity
        let policy: ActivityUIDismissalPolicy = dismissNow ? .immediate : .after(.now.addingTimeInterval(15 * 60))
        Task { await activity.end(state.map { ActivityContent(state: $0, staleDate: nil) }, dismissalPolicy: policy) }
    }

    /// Discarding the finished activity: take its numbers off the Lock Screen now.
    func dismissFinished() {
        guard let finished else { return }
        self.finished = nil
        Task { await finished.end(nil, dismissalPolicy: .immediate) }
    }
}

extension PulseActivityAttributes.Kind {
    init(_ activity: WorkoutActivity) {
        switch activity {
        case .running: self = .running
        case .cycling: self = .cycling
        case .walking, .hiking, .other: self = .walking
        }
    }
}

extension ActivitySession {
    /// The Live Activity's numbers right now.
    func liveActivityState(at now: Date = .now) -> PulseActivityAttributes.ContentState {
        let elapsed = recorder.movingTime(at: now)
        let bpm = heartRate(at: now)
        let zone = bpm.map { recorder.zones.zone(for: $0) }
        var status: String?
        if let zone {
            if let target = recorder.targetZone {
                status = zone == target ? "In zone \(target)" : zone > target ? "Above zone \(target)" : "Below zone \(target)"
            } else {
                status = zone == 0 ? "Below zone 1" : "Zone \(zone)"
            }
        }
        return PulseActivityAttributes.ContentState(
            // Only a running activity's clock ticks on the Lock Screen (paused or finished: frozen).
            timerStart: recorder.state == .recording ? now.addingTimeInterval(-elapsed) : nil,
            elapsed: elapsed, distanceMeters: recorder.distance, paceSecondsPerKm: recorder.currentPace(at: now),
            heartRate: bpm, zone: zone, status: status)
    }
}
