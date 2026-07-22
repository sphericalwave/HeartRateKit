//
//  BLEHeartRateSource.swift
//  HeartRateKit
//
//  Bluetooth LE Heart Rate Profile (service 0x180D, measurement 0x2A37).
//  Remembers the preferred strap and auto-reconnects. From the
//  bounce/breathe lineage (byte-identical there).
//

import Foundation
import CoreBluetooth
import Combine

private let heartRateServiceUUID = CBUUID(string: "180D")
private let heartRateMeasurementCharUUID = CBUUID(string: "2A37")

public final class BLEHeartRateSource: NSObject, HeartRateSource, ObservableObject {

    @Published public private(set) var discovered: [CBPeripheral] = []
    @Published public private(set) var connected: CBPeripheral?
    @Published public private(set) var state: CBManagerState = .unknown

    private var central: CBCentralManager!
    private var continuation: AsyncStream<Int>.Continuation?
    public let samples: AsyncStream<Int>

    private var wantsConnection = false
    private var connectingPeripheral: CBPeripheral?

    private var preferredPeripheralID: UUID? {
        get {
            guard let s = UserDefaults.standard.string(forKey: "ble.preferredPeripheralID") else { return nil }
            return UUID(uuidString: s)
        }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: "ble.preferredPeripheralID") }
    }

    public override init() {
        var localCont: AsyncStream<Int>.Continuation!
        self.samples = AsyncStream { localCont = $0 }
        super.init()
        self.continuation = localCont
        self.central = CBCentralManager(delegate: self, queue: .main)
    }

    public func start() async throws {
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

    /// Stop discovery while leaving any live connection intact. `stop()` by
    /// contrast tears the connection down as well.
    public func stopScanning() {
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
        central.stopScan()
        p.delegate = self
        central.connect(p, options: nil)
    }
}

extension BLEHeartRateSource: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        state = central.state
        if central.state == .poweredOn {
            attemptStart()
        }
    }

    public func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        if !discovered.contains(where: { $0.identifier == peripheral.identifier }) {
            discovered.append(peripheral)
        }
        guard wantsConnection, connected == nil, connectingPeripheral == nil else { return }
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
