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

    private let store = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var throttle = HRThrottle(resolution: .high)

    public override init() { super.init() }

    public func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let hr = HKQuantityType(.heartRate)
        try? await store.requestAuthorization(toShare: [], read: [hr])
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
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            builder.delegate = self
            self.workoutSession = session
            self.builder = builder
            let now = Date()
            session.startActivity(with: now)
            builder.beginCollection(withStart: now) { _, _ in }
            isStreaming = true
        } catch {
            print("WatchHRStreamer start failed: \(error)")
        }
    }

    public func stop() {
        guard isStreaming else { return }
        isStreaming = false
        workoutSession?.end()
        builder?.endCollection(withEnd: Date()) { [weak self] _, _ in
            self?.builder?.finishWorkout { _, _ in }
        }
        workoutSession = nil
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
