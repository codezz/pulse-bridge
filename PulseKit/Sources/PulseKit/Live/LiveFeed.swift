import Foundation
import Observation

/// Reads the band's command channel while no sync runs: today's activity (`09` stream) and
/// on-demand measurements (`28`). Only one reader may use the channel at a time, so callers
/// stop the feed (and wait for it) before a sync.
@MainActor
@Observable
public final class LiveFeed {
    public enum MeasurementState: Equatable, Sendable {
        case idle
        case running(MeasurementKind, latest: MeasurementValues?, startedAt: Date)
        case finished(MeasurementValues)
        case failed(MeasurementKind)
        /// Stopped by the app going to the background or the band disconnecting.
        case interrupted(MeasurementKind)
    }

    public private(set) var activity: LiveActivity?
    public private(set) var lastActivityAt: Date?
    public private(set) var measurement: MeasurementState = .idle
    public private(set) var isRunning = false
    public var measurementTimeout: TimeInterval = 120
    public var pollTimeout: Duration = .seconds(1)
    /// Called once when a measurement finishes, fails, is cancelled or interrupted.
    @ObservationIgnored public var onMeasurementEnded: ((MeasurementState) -> Void)?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var channel: (any CommandChannel)?
    @ObservationIgnored private let now: () -> Date

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    public var isMeasuring: Bool {
        if case .running = measurement { true } else { false }
    }

    public func start(over channel: some CommandChannel) async throws {
        guard task == nil else { return }
        // Reserve the channel before the first await, so stop() and a second start() see it.
        self.channel = channel
        isRunning = true
        let enable = Task { try await channel.send(Command.realTimeActivity(true)) }
        task = Task { [weak self] in
            guard (try? await enable.value) != nil else {
                self?.endAfterDisconnect()
                return
            }
            await self?.read(channel)
        }
        try await enable.value
    }

    /// Returns once the loop has stopped reading, so another reader can take the channel.
    public func stop() async {
        guard let task else { return }
        task.cancel()
        await task.value
        self.task = nil
        await stopBandMeasurement(endingAs: MeasurementState.interrupted)
        try? await channel?.send(Command.realTimeActivity(false))
        self.channel = nil
    }

    /// Running only once the band accepted the start command (the first progress packet comes
    /// about a second later), so a failed write leaves no progress bar behind.
    public func measure(_ kind: MeasurementKind) async throws {
        guard let channel, isRunning, !isMeasuring else { return }
        try await channel.send(Command.measurement(kind, start: true))
        // stop() may have run during the send: then nothing would ever end this measurement.
        guard isRunning, let current = self.channel, current === channel else {
            try? await channel.send(Command.measurement(kind, start: false))
            return
        }
        measurement = .running(kind, latest: nil, startedAt: now())
    }

    public func cancelMeasurement() async {
        await stopBandMeasurement(endingAs: { _ in .idle })
    }

    /// Clears a finished or failed result.
    public func resetMeasurement() {
        if !isMeasuring { measurement = .idle }
    }

    private func stopBandMeasurement(endingAs outcome: (MeasurementKind) -> MeasurementState) async {
        guard case .running(let kind, _, _) = measurement else { return }
        end(outcome(kind))
        try? await channel?.send(Command.measurement(kind, start: false))
    }

    /// The one place a measurement ends: sets the state and notifies once.
    private func end(_ state: MeasurementState) {
        measurement = state
        onMeasurementEnded?(state)
    }

    private func read(_ channel: some CommandChannel) async {
        while !Task.isCancelled {
            let packet: Data?
            do {
                packet = try await channel.nextPacket(timeout: pollTimeout)
            } catch {
                break // disconnected
            }
            if let packet { handle(packet) }
            await failMeasurementIfTimedOut()
        }
        // Cancelled means stop() is in charge (it also tells the band).
        guard !Task.isCancelled else {
            isRunning = false
            return
        }
        endAfterDisconnect()
    }

    /// The band went away: interrupt a running measurement and allow start() again.
    private func endAfterDisconnect() {
        isRunning = false
        if case .running(let kind, _, _) = measurement { end(.interrupted(kind)) }
        task = nil
        channel = nil
    }

    private func handle(_ packet: Data) {
        if let activity = LiveActivity(packet: packet) {
            self.activity = activity
            lastActivityAt = now()
            return
        }
        guard case .running(let kind, let latest, let startedAt) = measurement,
              let update = MeasurementUpdate(packet: packet) else { return }
        switch update {
        case .progress(let values) where kind == .hrv && values.kind == .hrv && values.hrv > 0:
            // The HRV result is the end: the band repeats it a few times and never sends `28 ff`.
            end(.finished(values))
        case .progress(let values) where values.kind == kind:
            measurement = .running(kind, latest: values, startedAt: startedAt)
        case .finished:
            end(latest.map { $0.hasReading ? .finished($0) : .failed(kind) } ?? .failed(kind))
        case .progress:
            break // another kind's packet (for example a late result); not ours
        }
    }

    private func failMeasurementIfTimedOut() async {
        guard case .running(_, _, let startedAt) = measurement,
              now().timeIntervalSince(startedAt) > measurementTimeout else { return }
        await stopBandMeasurement(endingAs: MeasurementState.failed)
    }
}
