//
//  MockHeartRateSource.swift
//  HeartRateCore
//
//  Scripted HR playback for Simulator Mode and UI tests — no CoreBluetooth,
//  no simulator hardware required. Public and unconditional (not #if DEBUG)
//  so Release-config UI tests and host-app Simulator Mode can use it.
//

import Foundation

public final class MockHeartRateSource: HeartRateSource {

    public enum Profile: Sendable {
        /// Constant bpm.
        case steady(bpm: Int)
        /// Linear ramp from `from` to `to` over `duration`, then holds at `to`.
        case ramp(from: Int, to: Int, duration: TimeInterval)
        /// Steady baseline with a brief spike above it.
        case spike(baseline: Int, peak: Int, at: TimeInterval, duration: TimeInterval)
        /// Steady baseline with a signal dropout (no samples emitted) window.
        case dropout(bpm: Int, from: TimeInterval, duration: TimeInterval)
    }

    private let profile: Profile
    private let interval: TimeInterval
    private var continuation: AsyncStream<Int>.Continuation?
    public let samples: AsyncStream<Int>
    private var task: Task<Void, Never>?
    private let clock: () -> Date

    public init(profile: Profile, interval: TimeInterval = 1, clock: @escaping () -> Date = Date.init) {
        self.profile = profile
        self.interval = interval
        self.clock = clock
        var localCont: AsyncStream<Int>.Continuation!
        self.samples = AsyncStream { localCont = $0 }
        self.continuation = localCont
    }

    public func start() async throws {
        let start = clock()
        task = Task { [profile, interval, continuation, clock] in
            while !Task.isCancelled {
                let elapsed = clock().timeIntervalSince(start)
                if let bpm = Self.bpm(for: profile, elapsed: elapsed) {
                    continuation?.yield(bpm)
                }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        continuation?.finish()
    }

    static func bpm(for profile: Profile, elapsed: TimeInterval) -> Int? {
        switch profile {
        case .steady(let bpm):
            return bpm
        case .ramp(let from, let to, let duration):
            guard duration > 0 else { return to }
            let fraction = min(max(elapsed / duration, 0), 1)
            return from + Int((Double(to - from) * fraction).rounded())
        case .spike(let baseline, let peak, let at, let duration):
            if elapsed >= at, elapsed < at + duration { return peak }
            return baseline
        case .dropout(let bpm, let from, let duration):
            if elapsed >= from, elapsed < from + duration { return nil }
            return bpm
        }
    }
}
