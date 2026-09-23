//
//  WatchHRStreamer.swift
//  HeartRateKit
//
//  watchOS-side live HR: runs an HKWorkoutSession (mindAndBody) so the watch
//  samples HR densely, then forwards readings to the paired iPhone over
//  WatchConnectivity, rate-limited by the chosen HRResolution.
//

#if os(watchOS)
import Foundation
import HealthKit
import WatchConnectivity

public final class WatchHRStreamer: NSObject, ObservableObject {

    @Published public private(set) var latestBpm: Int?
    @Published public private(set) var isStreaming = false
    /// Why the last start attempt failed, for a host to show. A watch has no
    /// console to read, so swallowing this left "Idle" as the only symptom.
    @Published public private(set) var lastError: String?
    /// Whether HealthKit has granted heart-rate reads. A workout session
    /// starts happily without it and then reports no samples at all.
    @Published public private(set) var isAuthorized = false

    private let store = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var throttle = HRThrottle(resolution: .high)
    private var autoStop: Task<Void, Never>?

    /// A session left running all day is charged to the wearer's Activity
    /// rings the whole time, so streaming stops on its own after this. The
    /// host can raise it, but not to "forever".
    public var maxDuration: TimeInterval = 60 * 60

    public override init() { super.init() }

    @discardableResult
    public func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            lastError = "No health data on this device"
            return false
        }
        let hr = HKQuantityType(.heartRate)
        do {
            try await store.requestAuthorization(toShare: [], read: [hr])
            // A read grant is deliberately not reported by authorizationStatus
            // (it would leak what the user hid), so the request completing
            // without error is as much as can be known before samples arrive.
            isAuthorized = true
            return true
        } catch {
            lastError = "Health permission failed: \(error.localizedDescription)"
            isAuthorized = false
            return false
        }
    }

    public func setResolution(_ r: HRResolution) {
        throttle = HRThrottle(resolution: r)
    }

    public func start() {
        guard !isStreaming else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .mindAndBody
        config.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            let dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            // Heart rate is all this is for. The default collection set also
            // gathers energy and distance, which then rode along into Health
            // as if the wearer had worked out for as long as the app was open.
            dataSource.disableCollection(for: HKQuantityType(.activeEnergyBurned))
            dataSource.disableCollection(for: HKQuantityType(.basalEnergyBurned))
            dataSource.disableCollection(for: HKQuantityType(.distanceWalkingRunning))
            builder.dataSource = dataSource
            builder.delegate = self
            self.workoutSession = session
            self.builder = builder
            let now = Date()
            session.startActivity(with: now)
            builder.beginCollection(withStart: now) { _, _ in }
            isStreaming = true
            lastError = nil
            startAutoStop()
        } catch {
            lastError = "Workout start failed: \(error.localizedDescription)"
        }
    }

    public func stop() {
        guard isStreaming else { return }
        isStreaming = false
        autoStop?.cancel()
        autoStop = nil
        workoutSession?.end()
        // Discarded, never finished: this is a heart-rate feed, not a workout
        // the wearer asked to record. finishWorkout() wrote one to Health with
        // every sample the session had collected.
        builder?.discardWorkout()
        builder = nil
        workoutSession = nil
    }

    private func startAutoStop() {
        autoStop?.cancel()
        let limit = maxDuration
        autoStop = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(limit * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                self.lastError = "Stopped after \(Int(limit / 60)) min"
                self.stop()
            }
        }
    }

    private func forward(bpm: Int) {
        guard throttle.shouldForward() else { return }
        latestBpm = bpm
        let payload = WatchHRMessage.encode(bpm: bpm)
        let wc = WCSession.default
        if wc.isReachable {
            wc.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            wc.transferUserInfo(payload)
        }
    }
}

extension WatchHRStreamer: HKLiveWorkoutBuilderDelegate {
    public func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                               didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let hrType = HKQuantityType(.heartRate)
        guard collectedTypes.contains(hrType),
              let stats = workoutBuilder.statistics(for: hrType),
              let q = stats.mostRecentQuantity() else { return }
        let unit = HKUnit.count().unitDivided(by: .minute())
        forward(bpm: Int(q.doubleValue(for: unit).rounded()))
    }

    public func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
#endif
