//
//  WatchHRShared.swift
//  HeartRateKit
//
//  Pure, cross-platform pieces shared by the watch streamer (watchOS) and the
//  phone-side receiver (iOS): a sample-rate resolution + throttle, and the
//  WatchConnectivity message codec. No HealthKit / WatchConnectivity imports so
//  these are unit-testable on any platform.
//

import Foundation

/// How densely the watch forwards heart-rate samples to the phone.
public enum HRResolution: String, Sendable, CaseIterable, Identifiable {
    case high
    case low

    public var id: String { rawValue }
    public var label: String { self == .high ? "High" : "Low" }

    /// Minimum seconds between forwarded samples. High = every sample.
    public var minInterval: TimeInterval { self == .high ? 0 : 5 }
}

/// Rate-limits forwarding to at most one sample per `resolution.minInterval`.
public struct HRThrottle {
    private let minInterval: TimeInterval
    private var lastForwarded: Date?

    public init(resolution: HRResolution) {
        self.minInterval = resolution.minInterval
    }

    /// Whether a sample observed at `time` should be forwarded. Mutating: on a
    /// `true` result it records `time` as the new baseline.
    public mutating func shouldForward(at time: Date = Date()) -> Bool {
        if let last = lastForwarded, time.timeIntervalSince(last) < minInterval {
            return false
        }
        lastForwarded = time
        return true
    }
}

/// Encodes/decodes the `[String: Any]` WatchConnectivity payload for one HR reading.
public enum WatchHRMessage {
    public static let bpmKey = "bpm"
    public static let timeKey = "t"

    public static func encode(bpm: Int, at time: Date = Date()) -> [String: Any] {
        [bpmKey: bpm, timeKey: time.timeIntervalSince1970]
    }

    public static func decodeBpm(_ dict: [String: Any]) -> Int? {
        dict[bpmKey] as? Int
    }

    public static func decode(_ dict: [String: Any]) -> (bpm: Int, time: Date)? {
        guard let bpm = dict[bpmKey] as? Int else { return nil }
        let time = (dict[timeKey] as? TimeInterval).map { Date(timeIntervalSince1970: $0) } ?? Date()
        return (bpm, time)
    }
}
