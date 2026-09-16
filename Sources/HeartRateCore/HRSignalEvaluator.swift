//
//  HRSignalEvaluator.swift
//  HeartRateCore
//
//  Classifies sensor signal health from sample cadence and contact status,
//  independent of any transport.
//

import Foundation

public enum HRSignalState: Sendable, Equatable {
    case good
    case noContact
    case stale
    case disconnected
}

public struct HRSignalEvaluator {
    private let noContactAfter: TimeInterval
    private let staleAfter: TimeInterval

    private var lastGoodContactAt: Date?
    private var lastSampleAt: Date?

    public init(noContactAfter: TimeInterval = 3, staleAfter: TimeInterval = 5) {
        self.noContactAfter = noContactAfter
        self.staleAfter = staleAfter
    }

    public mutating func ingest(_ sample: HeartRateSample) {
        lastSampleAt = sample.timestamp
        if sample.contact != .notDetected {
            lastGoodContactAt = sample.timestamp
        }
    }

    public func state(now: Date, connected: Bool) -> HRSignalState {
        guard connected else { return .disconnected }
        guard let lastSampleAt else { return .disconnected }
        if now.timeIntervalSince(lastSampleAt) >= staleAfter { return .stale }
        if let lastGoodContactAt, now.timeIntervalSince(lastGoodContactAt) >= noContactAfter {
            return .noContact
        }
        return .good
    }
}
