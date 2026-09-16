//
//  HeartRateMeasurementParser.swift
//  HeartRateCore
//
//  Full decode of the BLE Heart Rate Measurement characteristic (0x2A37).
//  Flags byte: bit0 value format (0 UInt8, 1 UInt16 LE); bit1 sensor contact
//  detected; bit2 sensor contact feature supported; bit3 energy expended
//  present (UInt16 LE, kJ); bit4 RR-intervals present (repeated UInt16 LE,
//  units of 1/1024 s). Never crashes on malformed input — returns nil.
//

import Foundation

public enum HeartRateMeasurementParser {

    public static func parse(_ data: Data, timestamp: Date = Date(), uptime: TimeInterval) -> HeartRateSample? {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else { return nil }

        let flags = bytes[0]
        let is16Bit = (flags & 0x01) != 0
        let contactSupported = (flags & 0x04) != 0
        let contactDetected = (flags & 0x02) != 0
        let energyPresent = (flags & 0x08) != 0
        let rrPresent = (flags & 0x10) != 0

        var offset = 1
        let bpm: Int
        if is16Bit {
            guard bytes.count >= offset + 2 else { return nil }
            bpm = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            offset += 2
        } else {
            guard bytes.count >= offset + 1 else { return nil }
            bpm = Int(bytes[offset])
            offset += 1
        }

        var energyExpended: Int?
        if energyPresent {
            guard bytes.count >= offset + 2 else { return nil }
            energyExpended = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            offset += 2
        }

        var rrIntervals: [Double] = []
        if rrPresent {
            guard (bytes.count - offset) % 2 == 0, bytes.count > offset else { return nil }
            while offset + 1 < bytes.count {
                let raw = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
                rrIntervals.append(Double(raw) / 1024.0)
                offset += 2
            }
        }

        let contact: ContactStatus = contactSupported ? (contactDetected ? .detected : .notDetected) : .unsupported

        return HeartRateSample(
            bpm: bpm,
            contact: contact,
            rrIntervals: rrIntervals,
            energyExpended: energyExpended,
            timestamp: timestamp,
            uptime: uptime
        )
    }
}
