//
//  CompactHRChart.swift
//  HeartRateKit
//
//  A compact (~64pt) sparkline of recent heart rate — no axes or labels, a
//  thin tinted line. Reusable across sessions/screens where a full-height
//  charted readout would waste space.
//

import SwiftUI
import Charts

public struct CompactHRChart: View {

    public struct Point: Identifiable {
        public let t: Date
        public let bpm: Int
        public init(t: Date, bpm: Int) {
            self.t = t
            self.bpm = bpm
        }
        public var id: TimeInterval { t.timeIntervalSince1970 }
    }

    private let points: [Point]
    private let tint: Color
    private let height: CGFloat

    public init(points: [Point], tint: Color = .pink, height: CGFloat = 64) {
        self.points = points
        self.tint = tint
        self.height = height
    }

    /// Convenience for `HRRecorder.recent` / `.sessionSamples`.
    public init(recent: [(t: Date, bpm: Int)], tint: Color = .pink, height: CGFloat = 64) {
        self.init(points: recent.map { Point(t: $0.t, bpm: $0.bpm) }, tint: tint, height: height)
    }

    public var body: some View {
        Chart(points) { p in
            LineMark(
                x: .value("t", p.t),
                y: .value("bpm", p.bpm)
            )
            .foregroundStyle(tint)
            .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: domain)
        .frame(height: height)
    }

    private var domain: ClosedRange<Int> {
        let bpms = points.map(\.bpm)
        guard let lo = bpms.min(), let hi = bpms.max() else { return 50...120 }
        return max(0, lo - 5)...(hi + 5)
    }
}
