//
//  HeartRateSample.swift
//  HeartRateCore
//
//  A fully decoded BLE Heart Rate Measurement (0x2A37), beyond the plain
//  bpm carried by `HeartRateSource.samples`.
//

import Foundation

public enum ContactStatus: Sendable, Codable, Hashable {
    case unsupported
    case notDetected
    case detected
}

public struct HeartRateSample: Sendable, Codable, Hashable {
    public let bpm: Int
    public let contact: ContactStatus
    /// RR intervals in seconds, oldest first.
    public let rrIntervals: [Double]
    /// Energy expended in kJ since the last reset, when present.
    public let energyExpended: Int?
    /// Wall-clock capture time, for persistence and display.
    public let timestamp: Date
    /// Monotonic capture time, for session-relative math immune to clock changes.
    public let uptime: TimeInterval

    public init(
        bpm: Int,
        contact: ContactStatus,
        rrIntervals: [Double],
        energyExpended: Int?,
        timestamp: Date,
        uptime: TimeInterval
    ) {
        self.bpm = bpm
        self.contact = contact
        self.rrIntervals = rrIntervals
        self.energyExpended = energyExpended
        self.timestamp = timestamp
        self.uptime = uptime
    }
}

/// A `HeartRateSource` that can additionally provide the fully decoded
/// measurement. Additive: existing sources keep working via `samples` alone.
public protocol DetailedHeartRateSource: HeartRateSource {
    var detailedSamples: AsyncStream<HeartRateSample> { get }
}
