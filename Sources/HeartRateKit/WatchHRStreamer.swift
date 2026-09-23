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
    private var hrQuery: HKAnchoredObjectQuery?
    private var sawSample = false

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
            sawSample = false
            startHeartRateQuery()
            startAutoStop()
            startSilenceWatchdog()
        } catch {
            lastError = "Workout start failed: \(error.localizedDescription)"
        }
    }

    public func stop() {
        guard isStreaming else { return }
        isStreaming = false
        autoStop?.cancel()
        autoStop = nil
        if let hrQuery {
            store.stop(hrQuery)
            self.hrQuery = nil
        }
        workoutSession?.end()
        // Discarded, never finished: this is a heart-rate feed, not a workout
        // the wearer asked to record. finishWorkout() wrote one to Health with
        // every sample the session had collected.
        builder?.discardWorkout()
        builder = nil
        workoutSession = nil
    }

    /// Reads heart rate straight from HealthKit rather than waiting for the
    /// workout builder to hand it over. The builder reports nothing at all
    /// when it has nothing — no error, no samples — which is indistinguishable
    /// from a watch that isn't being worn. A query says which.
    private func startHeartRateQuery() {
        let type = HKQuantityType(.heartRate)
        let unit = HKUnit.count().unitDivided(by: .minute())
        // Only samples taken from now on; older ones would replay a stale bpm.
        let predicate = HKQuery.predicateForSamples(withStart: Date(), end: nil, options: .strictStartDate)
        let handler: (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) -> Void = { [weak self] _, samples, _, _, error in
            guard let self else { return }
            if let error {
                Task { @MainActor in self.lastError = "Heart rate unavailable: \(error.localizedDescription)" }
                return
            }
            guard let sample = (samples as? [HKQuantitySample])?.last else { return }
            let bpm = Int(sample.quantity.doubleValue(for: unit).rounded())
            Task { @MainActor in
                self.sawSample = true
                self.forward(bpm: bpm)
            }
        }
        let query = HKAnchoredObjectQuery(type: type,
                                          predicate: predicate,
                                          anchor: nil,
                                          limit: HKObjectQueryNoLimit,
                                          resultsHandler: handler)
        query.updateHandler = handler
        store.execute(query)
        hrQuery = query
    }

    /// A workout session that yields nothing for half a minute means the watch
    /// isn't on a wrist, or heart-rate access was refused — say so instead of
    /// showing "Streaming" against an empty reading.
    private func startSilenceWatchdog() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard let self, self.isStreaming, !self.sawSample else { return }
            await MainActor.run {
                self.lastError = "No readings — wear the watch, and allow heart rate in Health"
            }
        }
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

// The session exists to make the watch sample heart rate densely and to keep
// the app alive while it does; the readings themselves come from the query.
extension WatchHRStreamer: HKLiveWorkoutBuilderDelegate {
    public func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                               didCollectDataOf collectedTypes: Set<HKSampleType>) {}

    public func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
#endif
