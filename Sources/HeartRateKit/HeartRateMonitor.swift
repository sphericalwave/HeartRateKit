//
//  HeartRateMonitor.swift
//  HeartRateKit
//
//  App-facing facade over a BLE strap + HRRecorder: one observable object
//  carrying live BPM, a human-readable connection state, and the discovered
//  device list. This is what `HRPill` / `HRConnectSheet` bind to.
//

import Foundation
import CoreBluetooth
import Combine

@MainActor
public final class HeartRateMonitor: ObservableObject {

    @Published public private(set) var bpm: Int?
    @Published public private(set) var state: ConnectionState = .idle
    @Published public private(set) var discovered: [CBPeripheral] = []

    /// Rolling 60s window, shaped for `CompactHRChart(recent:)`.
    @Published public private(set) var recent: [(t: Date, bpm: Int)] = []

    public enum ConnectionState: Equatable {
        case idle
        case bluetoothOff
        case unauthorized
        case scanning
        case connecting
        case connected(name: String)
        case disconnected

        public var label: String {
            switch self {
            case .idle: return "Connect HR"
            case .bluetoothOff: return "Bluetooth off"
            case .unauthorized: return "Permission needed"
            case .scanning: return "Scanning…"
            case .connecting: return "Connecting…"
            case .connected(let name): return name
            case .disconnected: return "Reconnect"
            }
        }

        public var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    private let ble = BLEHeartRateSource()
    private let recorder = HRRecorder()
    private var cancellables: Set<AnyCancellable> = []

    public init() {
        recorder.attach(ble)

        recorder.$latestBpm.sink { [weak self] in self?.bpm = $0 }.store(in: &cancellables)
        recorder.$recent.sink { [weak self] in self?.recent = $0 }.store(in: &cancellables)
        ble.$discovered.sink { [weak self] in self?.discovered = $0 }.store(in: &cancellables)

        ble.$connected.sink { [weak self] peripheral in
            guard let self else { return }
            if let peripheral {
                state = .connected(name: peripheral.name ?? "HR Monitor")
            } else if state.isConnected {
                // Only a live connection dropping means "disconnected"; a nil
                // here during scan/idle is just the starting value.
                state = .disconnected
                bpm = nil
            }
        }.store(in: &cancellables)

        ble.$state.sink { [weak self] cbState in
            guard let self else { return }
            switch cbState {
            case .poweredOff:
                state = .bluetoothOff
                bpm = nil
            case .unauthorized:
                state = .unauthorized
            default:
                break
            }
        }.store(in: &cancellables)
    }

    // MARK: - Connection

    /// Begin discovery. If a strap was previously chosen it is reconnected
    /// directly rather than rescanned.
    public func startScan() {
        if !state.isConnected { state = .scanning }
        Task { [ble] in try? await ble.start() }
    }

    /// Stop discovery. A live connection is left alone — closing the picker
    /// must not drop the strap the user is mid-workout with.
    public func stopScan() {
        ble.stopScanning()
        if state == .scanning { state = .idle }
    }

    public func connect(_ peripheral: CBPeripheral) {
        state = .connecting
        ble.select(peripheral)
    }

    /// Drop the strap *and* forget it, so the next `startScan()` looks for a
    /// new one instead of silently reconnecting the one just dismissed.
    public func disconnect() {
        ble.forgetDevice()
        bpm = nil
        state = .idle
    }

    // MARK: - Per-set capture

    public func beginSet() { recorder.beginSession() }

    /// Samples captured so far in the current set, with absolute timestamps.
    /// Lets a host persist incrementally mid-set instead of waiting for
    /// `endSet()` — so readings survive the app being killed part-way through.
    public var sessionSamples: [(t: Date, bpm: Int)] { recorder.sessionSamples }

    /// Stats plus the raw samples for the set just finished, `t` relative to
    /// the first reading. Nil when no samples arrived.
    public func endSet() -> (stats: HRRecorder.SessionStats, samples: [(t: TimeInterval, bpm: Int)])? {
        let raw = recorder.sessionSamples
        guard let stats = recorder.endSession(), let first = raw.first?.t else { return nil }
        return (stats, raw.map { (t: $0.t.timeIntervalSince(first), bpm: $0.bpm) })
    }
}
