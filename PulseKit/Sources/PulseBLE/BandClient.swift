@preconcurrency import CoreBluetooth
import Foundation
import Observation
import PulseKit

@MainActor
enum BandUUID {
    static let vendorService = CBUUID(string: "FFF0")
    static let command = CBUUID(string: "FFF6")
    static let response = CBUUID(string: "FFF7")
    static let heartRateService = CBUUID(string: "180D")
    static let heartRate = CBUUID(string: "2A37")
    static let batteryService = CBUUID(string: "180F")
    static let battery = CBUUID(string: "2A19")
    static let deviceInfoService = CBUUID(string: "180A")
    static let serialNumber = CBUUID(string: "2A25")
    static let services = [vendorService, heartRateService, batteryService, deviceInfoService]
}

public enum BandError: LocalizedError {
    case bluetoothOff, bluetoothUnauthorized, bluetoothUnsupported, notPaired, bandForgotten, notFound, writeTimedOut

    public var errorDescription: String? {
        switch self {
        case .bluetoothOff: L("Bluetooth is off. Turn it on in Control Center.")
        case .bluetoothUnauthorized: L("Bluetooth access is not allowed. Enable it in Settings > Pulse Bridge.")
        case .bluetoothUnsupported: L("Bluetooth is not available on this device.")
        case .notPaired: L("No band paired yet.")
        case .bandForgotten: L("This iPhone no longer knows the band. Use Forget band, then pair it again.")
        case .writeTimedOut: L("The band stopped responding.")
        case .notFound: L("Band not found. Keep it close to the phone and make sure it is charged.")
        }
    }
}

public struct DiscoveredBand: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let rssi: Int
}

/// CoreBluetooth transport for the band. All CoreBluetooth callbacks arrive on the main queue.
@MainActor
@Observable
public final class BandClient: NSObject, CommandChannel {
    public enum State: Equatable, Sendable { case unknown, poweredOff, unauthorized, unsupported, disconnected, scanning, connecting, connected }

    private static let pairedKey = "pairedBandID"
    private static let connectTimeout: Duration = .seconds(10)
    private static let writeTimeout: Duration = .seconds(5)
    /// Only bands with this name prefix are offered for pairing.
    private static let namePrefix = "Pulse"

    public private(set) var state: State = .unknown
    public private(set) var discovered: [DiscoveredBand] = []
    public private(set) var heartRate: Int?
    public private(set) var battery: Int?
    public private(set) var serial: String?
    public private(set) var pairedID: UUID?
    /// Live heart rate on demand: heart-rate notifications are on only while this is true.
    public var streamsHeartRate = false {
        didSet {
            if !streamsHeartRate { heartRate = nil }
            if let peripheral, let heartRateCharacteristic {
                peripheral.setNotifyValue(streamsHeartRate, for: heartRateCharacteristic)
            }
        }
    }
    /// While true (during an activity), a dropped connection is re-requested right away. iOS keeps that
    /// request open with no timeout and completes it when the band is back in range, also in the background.
    @ObservationIgnored public var keepConnected = false
    /// Called for every heart-rate notification (also when the value repeats), for timestamping.
    @ObservationIgnored public var onHeartRate: ((Int) -> Void)?

    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var commandCharacteristic: CBCharacteristic?
    @ObservationIgnored private var heartRateCharacteristic: CBCharacteristic?
    @ObservationIgnored private var responseNotifying = false
    @ObservationIgnored private var inbox: [Data] = []
    @ObservationIgnored private var packetTimer: Task<Void, Never>?
    @ObservationIgnored private var packetWaiter: CheckedContinuation<Data?, Error>?
    @ObservationIgnored private var writeWaiter: CheckedContinuation<Void, Error>?
    @ObservationIgnored private var readyWaiter: CheckedContinuation<Void, Error>?
    @ObservationIgnored private var powerWaiters: [CheckedContinuation<Void, Error>] = []
    @ObservationIgnored private var scanWanted = false
    @ObservationIgnored private var writeTimer: Task<Void, Never>?
    /// Writes waiting for the one in flight (the band acknowledges one write at a time).
    @ObservationIgnored private var queuedWriters: [CheckedContinuation<Void, Never>] = []

    public override init() {
        super.init()
        pairedID = UserDefaults.standard.string(forKey: Self.pairedKey).flatMap(UUID.init(uuidString:))
        central = CBCentralManager(delegate: self, queue: .main)
    }

    /// Why Bluetooth can't be used right now, for the UI.
    public var bluetoothProblem: String? {
        switch state {
        case .poweredOff: BandError.bluetoothOff.errorDescription
        case .unauthorized: BandError.bluetoothUnauthorized.errorDescription
        case .unsupported: BandError.bluetoothUnsupported.errorDescription
        default: nil
        }
    }

    // MARK: Pairing

    public func startScan() async {
        scanWanted = true
        // The sheet may close while Bluetooth is still powering on.
        guard (try? await waitForPower()) != nil, scanWanted else { return }
        discovered = []
        state = .scanning
        central.scanForPeripherals(withServices: [BandUUID.vendorService])
    }

    public func stopScan() {
        scanWanted = false
        central.stopScan()
        if state == .scanning { state = .disconnected }
    }

    public func pair(_ band: DiscoveredBand) {
        stopScan()
        pair(id: band.id)
    }

    /// Pairs with a known CoreBluetooth identifier (used by the macOS test tool).
    public func pair(id: UUID) {
        pairedID = id
        UserDefaults.standard.set(id.uuidString, forKey: Self.pairedKey)
    }

    public func forget() {
        disconnect()
        pairedID = nil
        serial = nil
        battery = nil
        UserDefaults.standard.removeObject(forKey: Self.pairedKey)
    }

    // MARK: Connection

    public func connect() async throws {
        guard state != .connected else { return }
        guard state != .connecting else { throw PulseError.busy }
        try await waitForPower()
        // Another connect may have started while this one waited for power.
        guard state != .connected else { return }
        guard state != .connecting else { throw PulseError.busy }
        guard let pairedID else { throw BandError.notPaired }
        guard let target = central.retrievePeripherals(withIdentifiers: [pairedID]).first else {
            throw BandError.bandForgotten
        }
        peripheral = target
        target.delegate = self
        inbox.removeAll()
        state = .connecting
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: Self.connectTimeout)
            guard !Task.isCancelled else { return }
            self?.failConnection(BandError.notFound)
        }
        defer { timeout.cancel() }
        try await withCheckedThrowingContinuation { continuation in
            readyWaiter = continuation
            central.connect(target)
        }
    }

    public func disconnect() {
        guard let peripheral else { return }
        central.cancelPeripheralConnection(peripheral)
    }

    // MARK: CommandChannel

    /// Writes are serialized: a second caller waits for the first write's acknowledgement instead of
    /// replacing its continuation (which used to hang the first caller forever).
    public func send(_ frame: Data) async throws {
        while writeWaiter != nil {
            await withCheckedContinuation { queuedWriters.append($0) }
        }
        guard state == .connected, let peripheral, let commandCharacteristic else {
            resumeNextWriter()
            throw PulseError.notConnected
        }
        defer { resumeNextWriter() }
        try await withCheckedThrowingContinuation { continuation in
            writeWaiter = continuation
            writeTimer = Task { [weak self] in
                try? await Task.sleep(for: Self.writeTimeout)
                guard !Task.isCancelled else { return }
                self?.writeFinished(BandError.writeTimedOut)
            }
            peripheral.writeValue(frame, for: commandCharacteristic, type: .withResponse)
        }
    }

    public func nextPacket(timeout: Duration) async throws -> Data? {
        if !inbox.isEmpty { return inbox.removeFirst() }
        guard state == .connected else { throw PulseError.notConnected }
        // One reader at a time (LiveFeed or SyncEngine); a second one would orphan the first waiter.
        guard packetWaiter == nil else { throw PulseError.busy }
        return try await withCheckedThrowingContinuation { continuation in
            packetWaiter = continuation
            packetTimer = Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                self?.resumePacket(.success(nil))
            }
        }
    }

    // MARK: Internals

    private func waitForPower() async throws {
        switch central.state {
        case .poweredOn: return
        case .poweredOff: throw BandError.bluetoothOff
        case .unauthorized: throw BandError.bluetoothUnauthorized
        case .unsupported: throw BandError.bluetoothUnsupported
        default: try await withCheckedThrowingContinuation { powerWaiters.append($0) }
        }
    }

    fileprivate func powerChanged(_ power: CBManagerState) {
        let outcome: Result<Void, Error>
        switch power {
        case .poweredOn:
            if [.unknown, .poweredOff, .unauthorized, .unsupported].contains(state) { state = .disconnected }
            outcome = .success(())
        case .poweredOff:
            connectionLost()
            state = .poweredOff
            outcome = .failure(BandError.bluetoothOff)
        case .unauthorized:
            state = .unauthorized
            outcome = .failure(BandError.bluetoothUnauthorized)
        case .unsupported:
            state = .unsupported
            outcome = .failure(BandError.bluetoothUnsupported)
        default:
            return // .unknown / .resetting: keep waiting for a final state
        }
        let waiters = powerWaiters
        powerWaiters.removeAll()
        waiters.forEach { $0.resume(with: outcome) }
    }

    fileprivate func found(_ band: DiscoveredBand) {
        guard band.name.hasPrefix(Self.namePrefix) else { return }
        if !discovered.contains(where: { $0.id == band.id }) { discovered.append(band) }
    }

    fileprivate func configure(_ characteristic: CBCharacteristic, on peripheral: CBPeripheral) {
        switch characteristic.uuid {
        case BandUUID.command:
            commandCharacteristic = characteristic
            finishConnectingIfReady()
        case BandUUID.response:
            peripheral.setNotifyValue(true, for: characteristic)
        case BandUUID.heartRate:
            heartRateCharacteristic = characteristic
            peripheral.setNotifyValue(streamsHeartRate, for: characteristic)
        case BandUUID.battery:
            peripheral.setNotifyValue(true, for: characteristic)
            peripheral.readValue(for: characteristic)
        case BandUUID.serialNumber:
            peripheral.readValue(for: characteristic)
        default:
            break
        }
    }

    fileprivate func notificationChanged(_ uuid: CBUUID, notifying: Bool) {
        guard uuid == BandUUID.response else { return }
        responseNotifying = notifying
        finishConnectingIfReady()
    }

    fileprivate func received(_ value: Data, from uuid: CBUUID) {
        switch uuid {
        case BandUUID.response:
            if packetWaiter != nil { resumePacket(.success(value)) } else { inbox.append(value) }
        case BandUUID.heartRate:
            heartRate = HeartRateMeasurement.bpm(from: value)
            if let heartRate { onHeartRate?(heartRate) }
        case BandUUID.battery:
            battery = value.first.map(Int.init)
        case BandUUID.serialNumber:
            serial = String(decoding: value, as: UTF8.self)
            finishConnectingIfReady()
        default:
            break
        }
    }

    /// Connected means: commands can be written, responses arrive, and we know the serial.
    private func finishConnectingIfReady() {
        // Without a waiter this is a reconnect requested by `keepConnected`.
        guard readyWaiter != nil || keepConnected, state != .connected,
              commandCharacteristic != nil, responseNotifying, serial != nil else { return }
        state = .connected
        resume(&readyWaiter, with: .success(()))
    }

    fileprivate func failConnection(_ error: Error) {
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        state = .disconnected
        resume(&readyWaiter, with: .failure(error))
    }

    fileprivate func connectionLost() {
        state = .disconnected
        heartRate = nil
        commandCharacteristic = nil
        heartRateCharacteristic = nil
        responseNotifying = false
        inbox.removeAll()
        resumePacket(.failure(PulseError.notConnected))
        resume(&writeWaiter, with: .failure(PulseError.notConnected))
        resume(&readyWaiter, with: .failure(PulseError.notConnected))
    }

    private func resumeNextWriter() {
        guard !queuedWriters.isEmpty else { return }
        queuedWriters.removeFirst().resume()
    }

    fileprivate func writeFinished(_ error: Error?) {
        writeTimer?.cancel()
        writeTimer = nil
        resume(&writeWaiter, with: error.map { .failure($0) } ?? .success(()))
    }

    private func resumePacket(_ result: Result<Data?, Error>) {
        packetTimer?.cancel()
        packetTimer = nil
        resume(&packetWaiter, with: result)
    }

    private func resume<T: Sendable>(_ waiter: inout CheckedContinuation<T, Error>?, with result: Result<T, Error>) {
        guard let continuation = waiter else { return }
        waiter = nil
        continuation.resume(with: result)
    }
}

// CoreBluetooth calls these on the main queue (see init), so hopping is just an assertion.
extension BandClient: CBCentralManagerDelegate {
    public nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let power = central.state
        MainActor.assumeIsolated { powerChanged(power) }
    }

    public nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let band = DiscoveredBand(
            id: peripheral.identifier,
            name: advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? L("Unknown band"),
            rssi: RSSI.intValue)
        MainActor.assumeIsolated { found(band) }
    }

    public nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated { peripheral.discoverServices(BandUUID.services) }
    }

    public nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated { failConnection(error ?? BandError.notFound) }
    }

    public nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            connectionLost()
            if keepConnected, let peripheral = self.peripheral {
                state = .connecting
                central.connect(peripheral)
            }
        }
    }
}

extension BandClient: CBPeripheralDelegate {
    public nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            for service in peripheral.services ?? [] { peripheral.discoverCharacteristics(nil, for: service) }
        }
    }

    public nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        MainActor.assumeIsolated {
            for characteristic in service.characteristics ?? [] { configure(characteristic, on: peripheral) }
        }
    }

    public nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        let uuid = characteristic.uuid
        let notifying = characteristic.isNotifying
        MainActor.assumeIsolated { notificationChanged(uuid, notifying: notifying) }
    }

    public nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let value = characteristic.value else { return }
        let uuid = characteristic.uuid
        MainActor.assumeIsolated { received(value, from: uuid) }
    }

    public nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated { writeFinished(error) }
    }
}
