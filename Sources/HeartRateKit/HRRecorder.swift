//
//  HRRecorder.swift
//  HeartRateKit
//
//  Fans a HeartRateSource into UI-friendly state: latest BPM, a rolling
//  60s window, and per-session capture with min/avg/max stats. From bounce.
//

import Foundation
import Combine

@MainActor
public final class HRRecorder: ObservableObject {

    @Published public private(set) var latestBpm: Int?
    @Published public private(set) var recent: [(t: Date, bpm: Int)] = []
    @Published public private(set) var sessionSamples: [(t: Date, bpm: Int)] = []
    @Published public private(set) var isRecording: Bool = false

    private var task: Task<Void, Never>?
    private let recentWindow: TimeInterval = 60

    public func beginSession() {
        sessionSamples.removeAll()
        isRecording = true
    }

    public func endSession() -> SessionStats? {
        isRecording = false
        guard !sessionSamples.isEmpty else { return nil }
        let bpms = sessionSamples.map { $0.bpm }
        let avg = bpms.reduce(0, +) / bpms.count
        return SessionStats(
            min: bpms.min() ?? 0,
            avg: avg,
            max: bpms.max() ?? 0,
            count: bpms.count
        )
    }

    public func attach(_ source: HeartRateSource) {
        task?.cancel()
        let stream = source.samples
        task = Task { [weak self] in
            for await bpm in stream {
                await self?.ingest(bpm)
            }
        }
    }

    public func detach() {
        task?.cancel()
        task = nil
    }

    private func ingest(_ bpm: Int) {
        let now = Date()
        latestBpm = bpm
        recent.append((now, bpm))
        let cutoff = now.addingTimeInterval(-recentWindow)
        recent.removeAll { $0.t < cutoff }
        if isRecording {
            sessionSamples.append((now, bpm))
        }
    }

    public init() {}

    public struct SessionStats {
        public let min: Int
        public let avg: Int
        public let max: Int
        public let count: Int
    }
}
