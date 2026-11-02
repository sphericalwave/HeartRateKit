//
//  HRV.swift
//  HeartRateCore
//
//  Heart-rate variability from beat-to-beat (RR) intervals. Pure functions,
//  so a host can compute live and session values from whatever RR it kept.
//

import Foundation

public enum HRV {

    /// RR intervals outside this range (seconds) are dropped as artifacts:
    /// 0.3 s = 200 bpm, 2.0 s = 30 bpm.
    public static let plausibleRR: ClosedRange<Double> = 0.3...2.0

    /// A beat that differs from the previous one by more than this fraction is
    /// treated as an artifact (a missed or extra beat) and its successive
    /// differences are skipped.
    public static let maxRelativeChange = 0.2

    /// Root mean square of successive differences, in milliseconds. Nil when
    /// fewer than two clean successive differences remain.
    ///
    /// - Parameter rr: RR intervals in seconds, oldest first.
    public static func rmssd(_ rr: [Double]) -> Double? {
        let clean = rr.filter { plausibleRR.contains($0) }
        guard clean.count >= 2 else { return nil }
        var sumSquares = 0.0
        var n = 0
        for (prev, next) in zip(clean, clean.dropFirst()) {
            let diff = next - prev
            guard abs(diff) / prev <= maxRelativeChange else { continue }
            sumSquares += diff * diff
            n += 1
        }
        guard n >= 2 else { return nil }
        return (sumSquares / Double(n)).squareRoot() * 1000
    }
}
