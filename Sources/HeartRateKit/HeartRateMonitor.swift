//
//  HeartRateMonitor.swift
//  HeartRateKit
//
//  App-facing facade over a heart-rate source + HRRecorder: one observable
//  object carrying live BPM, a human-readable connection state, and the
//  discovered device list. This is what `HRPill` / `HRConnectSheet` bind to.
//
//  The source is swappable: a BLE strap, or (on iOS) a paired Apple Watch
//  running `WatchHRStreamer`. Everything downstream — `bpm`, `recent`, the
//  charts, per-set capture — reads the same regardless of which is feeding it.
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

    /// Which source is feeding `bpm`. Change it with `use(_:)`.
    @Published public private(set) var sourceKind: SourceKind = .ble

    public enum SourceKind: String, CaseIterable, Identifiable, Sendable {
        case ble
        case watch

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .ble: return "Chest strap"
            case .watch: return "Apple Watch"
            }
        }
    }

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
    #if os(iOS)
    private let watch = WatchHeartRateSource()
    #endif
    private let recorder = HRRecorder()
    private var cancellables: Set<AnyCancellable> = []

    public init() {
        recorder.attach(ble)

        recorder.$latestBpm.sink { [weak self] in
            guard let self else { return }
            bpm = $0
            // The watch has no connect handshake to report — the first reading
            // through is what proves it's streaming.
            if sourceKind == .watch, $0 != nil, !state.isConnected {
                state = .connected(name: SourceKind.watch.label)
            }
        }.store(in: &cancellables)
        recorder.$recent.sink { [weak self] in self?.recent = $0 }.store(in: &cancellables)
        ble.$discovered.sink { [weak self] in self?.discovered = $0 }.store(in: &cancellables)

        ble.$connected.sink { [weak self] peripheral in
            guard let self, sourceKind == .ble else { return }
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
            guard let self, sourceKind == .ble else { return }
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

    // MARK: - Source

    /// Switches which source feeds the monitor. The old one is stopped, so a
    /// strap isn't left connected (and draining) behind a watch session.
    public func use(_ kind: SourceKind) {
        guard kind != sourceKind else { return }
        stopCurrentSource()
        sourceKind = kind
        bpm = nil
        recorder.detach()

        switch kind {
        case .ble:
            recorder.attach(ble)
            state = .idle
            startScan()
        case .watch:
            #if os(iOS)
            recorder.attach(watch)
            discovered = []
            // Stays "connecting" until a reading actually arrives — the watch
            // app may be asleep, and claiming otherwise would be a fiction.
            state = .connecting
            Task { [watch] in try? await watch.start() }
            #endif
        }
    }

    /// Re-sends the streaming request to the watch. The watch only hears the
    /// phone while its app is running, so a request made before the user
    /// opened it needs repeating.
    public func nudgeWatch() {
        #if os(iOS)
        guard sourceKind == .watch else { return }
        Task { [watch] in try? await watch.start() }
        #endif
    }

    /// Whether there's a watch app to stream from at all — lets a host say
    /// "waiting for the watch" or "nothing to wait for" rather than leaving a
    /// spinner up forever.
    public var isWatchAppAvailable: Bool {
        #if os(iOS)
        watch.isWatchAppAvailable
        #else
        false
        #endif
    }

    /// Forwarding density for the watch source. No-op for a strap, which
    /// sends every reading it takes.
    public func setWatchResolution(_ resolution: HRResolution) {
        #if os(iOS)
        watch.setResolution(resolution)
        #endif
    }

    private func stopCurrentSource() {
        switch sourceKind {
        case .ble:
            ble.stopScanning()
        case .watch:
            #if os(iOS)
            watch.stop()
            #endif
        }
    }

    // MARK: - Connection

    /// Begin discovery. If a strap was previously chosen it is reconnected
    /// directly rather than rescanned. No-op unless the strap is the source.
    public func startScan() {
        guard sourceKind == .ble else { return }
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
        guard sourceKind == .ble else { return }
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

#if DEBUG
extension HeartRateMonitor {
    /// A monitor seeded with fixed values for previews/screenshots — no live
    /// BLE. Defined here (not in an extension file) so it can assign the
    /// file-private `private(set)` published properties.
    static func preview(bpm seededBpm: Int? = 132,
                        state seededState: ConnectionState = .connected(name: "Polar H10")) -> HeartRateMonitor {
        let monitor = HeartRateMonitor()
        monitor.bpm = seededBpm
        monitor.state = seededState
        monitor.recent = HeartRateKitSamples.recent
        return monitor
    }
}
#endif
