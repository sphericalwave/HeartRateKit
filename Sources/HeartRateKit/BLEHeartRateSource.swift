//
//  BLEHeartRateSource.swift
//  HeartRateKit
//
//  Bluetooth LE Heart Rate Profile (service 0x180D, measurement 0x2A37).
//  Remembers the preferred strap and auto-reconnects. From the
//  bounce/breathe lineage (byte-identical there).
//
//  Opt-in state restoration: with a `restoreIdentifier` (and the host's
//  `bluetooth-central` background mode), iOS keeps the strap connection
//  alive after the app is killed in the background and relaunches the app
//  when the strap next sends a reading. The host must create the source with
//  the same identifier early in every launch to receive it.
//

import Foundation
import CoreBluetooth
import Combine
import HeartRateCore

private let heartRateServiceUUID = CBUUID(string: "180D")
private let heartRateMeasurementCharUUID = CBUUID(string: "2A37")

/// A peripheral seen while scanning, with the signal strength needed to
/// identify a strap in a crowded gym. Live bpm is not available pre-connect —
/// the HR measurement characteristic only notifies after connection.
public struct HRDiscovery: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let name: String?
    public let rssi: Int
    public let lastSeen: Date
}

public final class BLEHeartRateSource: NSObject, DetailedHeartRateSource, ObservableObject {

    @Published public private(set) var discovered: [CBPeripheral] = []
    @Published public private(set) var discoveries: [HRDiscovery] = []
    @Published public private(set) var connected: CBPeripheral?
    @Published public private(set) var state: CBManagerState = .unknown

    private var central: CBCentralManager!
    private var continuation: AsyncStream<Int>.Continuation?
    public let samples: AsyncStream<Int>
    private var detailedContinuation: AsyncStream<HeartRateSample>.Continuation?
    public let detailedSamples: AsyncStream<HeartRateSample>
    private let startUptime = Date()

    private var wantsConnection = false
    private var wantsScan = false
    private var connectingPeripheral: CBPeripheral?
    /// Set by state restoration until the central powers on and the
    /// restored strap can be resumed.
    private var needsRestoreResume = false

    private var preferredPeripheralID: UUID? {
        get {
            guard let s = UserDefaults.standard.string(forKey: "ble.preferredPeripheralID") else { return nil }
            return UUID(uuidString: s)
        }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: "ble.preferredPeripheralID") }
    }

    /// True once a strap has been selected, so `start()` reconnects it rather
    /// than connecting to whichever strap it hears first.
    public var hasRememberedDevice: Bool { preferredPeripheralID != nil }

    /// - Parameter restoreIdentifier: opts into Core Bluetooth state
    ///   restoration. Use one fixed string per app, and create the source
    ///   at launch; nil (the default) keeps the old non-restoring behavior.
    public init(restoreIdentifier: String? = nil) {
        var localCont: AsyncStream<Int>.Continuation!
        self.samples = AsyncStream { localCont = $0 }
        var localDetailedCont: AsyncStream<HeartRateSample>.Continuation!
        self.detailedSamples = AsyncStream { localDetailedCont = $0 }
        super.init()
        self.continuation = localCont
        self.detailedContinuation = localDetailedCont
        self.central = CBCentralManager(delegate: self, queue: .main,
                                        options: Self.centralOptions(restoreIdentifier: restoreIdentifier))
    }

    /// Internal for tests.
    static func centralOptions(restoreIdentifier: String?) -> [String: Any]? {
        #if os(macOS)
        return nil
        #else
        guard let restoreIdentifier else { return nil }
        return [CBCentralManagerOptionRestoreIdentifierKey: restoreIdentifier]
        #endif
    }

    /// Of the peripherals iOS restored, the remembered strap, else the first.
    /// Generic so tests needn't construct a `CBPeripheral`. Internal for tests.
    static func pickRestored<P>(_ candidates: [P], id: (P) -> UUID, preferred: UUID?) -> P? {
        candidates.first { id($0) == preferred } ?? candidates.first
    }

    public nonisolated(nonsending) func start() async throws {
        wantsConnection = true
        attemptStart()
    }

    public func stop() {
        wantsConnection = false
        if central.state == .poweredOn {
            central.stopScan()
            if let p = connectingPeripheral {
                central.cancelPeripheralConnection(p)
            }
            if let c = connected {
                central.cancelPeripheralConnection(c)
            }
        }
        connectingPeripheral = nil
    }

    /// Discover nearby straps without auto-connecting to any of them, so the
    /// user can pick theirs (by name / RSSI) from `discoveries` and `select` it.
    /// Unlike `start()`, this never connects to the first strap it hears, and
    /// auto-connect stays off until `stopScanning()` or `select(_:)`.
    public func scan() {
        wantsScan = true
        guard central.state == .poweredOn else { return }
        central.scanForPeripherals(withServices: [heartRateServiceUUID],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    /// Stop discovery while leaving any live connection intact. `stop()` by
    /// contrast tears the connection down as well.
    public func stopScanning() {
        wantsScan = false
        guard central.state == .poweredOn else { return }
        central.stopScan()
    }

    public func select(_ peripheral: CBPeripheral) {
        preferredPeripheralID = peripheral.identifier
        wantsConnection = true
        connectingPeripheral = peripheral
        connect(peripheral)
    }

    /// Forget the remembered strap and disconnect, so the next start() scans
    /// fresh instead of reconnecting the old device.
    public func forgetDevice() {
        preferredPeripheralID = nil
        stop()
        discovered.removeAll()
        discoveries.removeAll()
    }

    private func attemptStart() {
        guard central.state == .poweredOn, wantsConnection else { return }
        if connected != nil || connectingPeripheral != nil { return }
        if let id = preferredPeripheralID,
           let p = central.retrievePeripherals(withIdentifiers: [id]).first {
            connectingPeripheral = p
            connect(p)
        } else {
            central.scanForPeripherals(withServices: [heartRateServiceUUID])
        }
    }

    private func connect(_ p: CBPeripheral) {
        wantsScan = false
        central.stopScan()
        p.delegate = self
        central.connect(p, options: nil)
    }
}

extension BLEHeartRateSource: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        state = central.state
        if central.state == .poweredOn {
            if wantsScan && !wantsConnection { scan() }
            resumeRestoredPeripheral()
            attemptStart()
        }
    }

    #if !os(macOS)
    /// Called before `centralManagerDidUpdateState` on a launch that restores
    /// state. Only records what came back: peripherals can't be commanded
    /// until the central is powered on.
    public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        guard let peripheral = Self.pickRestored(restored, id: \.identifier, preferred: preferredPeripheralID) else { return }
        peripheral.delegate = self
        wantsConnection = true
        needsRestoreResume = true
        if preferredPeripheralID == nil { preferredPeripheralID = peripheral.identifier }
        if peripheral.state == .connected {
            connected = peripheral
        } else {
            connectingPeripheral = peripheral
        }
    }
    #endif

    /// Re-subscribes a strap that was still connected when the app was
    /// relaunched, and re-issues a connect the system dropped while it was
    /// down. A pending connect is left alone: it completes on its own.
    private func resumeRestoredPeripheral() {
        guard needsRestoreResume else { return }
        needsRestoreResume = false
        if let peripheral = connected, peripheral.state == .connected {
            peripheral.discoverServices([heartRateServiceUUID])
        } else if let peripheral = connectingPeripheral, peripheral.state == .disconnected {
            central.connect(peripheral, options: nil)
        }
    }

    public func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        if !discovered.contains(where: { $0.identifier == peripheral.identifier }) {
            discovered.append(peripheral)
        }
        let seenAt = Date()
        if let index = discoveries.firstIndex(where: { $0.id == peripheral.identifier }) {
            discoveries[index] = HRDiscovery(id: peripheral.identifier, name: peripheral.name, rssi: RSSI.intValue, lastSeen: seenAt)
        } else {
            discoveries.append(HRDiscovery(id: peripheral.identifier, name: peripheral.name, rssi: RSSI.intValue, lastSeen: seenAt))
        }
        guard wantsConnection, !wantsScan, connected == nil, connectingPeripheral == nil else { return }
        if preferredPeripheralID == nil || preferredPeripheralID == peripheral.identifier {
            if preferredPeripheralID == nil {
                preferredPeripheralID = peripheral.identifier
            }
            connectingPeripheral = peripheral
            connect(peripheral)
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connected = peripheral
        connectingPeripheral = nil
        peripheral.discoverServices([heartRateServiceUUID])
    }

    public func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        connectingPeripheral = nil
        if wantsConnection {
            attemptStart()
        }
    }

    public func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        connected = nil
        connectingPeripheral = nil
        if wantsConnection, preferredPeripheralID == peripheral.identifier {
            connectingPeripheral = peripheral
            central.connect(peripheral, options: nil)
        }
    }
}

extension BLEHeartRateSource: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let svc = peripheral.services?.first(where: { $0.uuid == heartRateServiceUUID }) else { return }
        peripheral.discoverCharacteristics([heartRateMeasurementCharUUID], for: svc)
    }

    public func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard let ch = service.characteristics?.first(where: { $0.uuid == heartRateMeasurementCharUUID }) else { return }
        peripheral.setNotifyValue(true, for: ch)
    }

    public func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard characteristic.uuid == heartRateMeasurementCharUUID,
              let data = characteristic.value, !data.isEmpty else { return }
        let bpm = parseHeartRate(data)
        continuation?.yield(bpm)
        if let sample = HeartRateMeasurementParser.parse(data, uptime: Date().timeIntervalSince(startUptime)) {
            detailedContinuation?.yield(sample)
        }
    }

    private func parseHeartRate(_ data: Data) -> Int {
        Self.parseHeartRateMeasurement(data)
    }

    /// BLE Heart Rate Measurement (0x2A37): flags bit 0 selects UInt8 vs
    /// UInt16 little-endian BPM. Internal for tests.
    static func parseHeartRateMeasurement(_ data: Data) -> Int {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else { return 0 }
        let flags = bytes[0]
        let is16Bit = (flags & 0x01) != 0
        if is16Bit, bytes.count >= 3 {
            return Int(UInt16(bytes[1]) | (UInt16(bytes[2]) << 8))
        } else if bytes.count >= 2 {
            return Int(bytes[1])
        }
        return 0
    }
}
