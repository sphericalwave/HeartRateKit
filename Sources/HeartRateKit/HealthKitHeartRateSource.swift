//
//  HealthKitHeartRateSource.swift
//  HeartRateKit
//
//  Live BPM via an HKAnchoredObjectQuery from now onward. From breathe.
//

import Foundation
#if canImport(HealthKit)
import HealthKit

public final class HealthKitHeartRateSource: HeartRateSource {

    private let store = HKHealthStore()
    private var anchor: HKQueryAnchor?
    private var query: HKAnchoredObjectQuery?
    private var continuation: AsyncStream<Int>.Continuation?
    public let samples: AsyncStream<Int>

    public init() {
        var localCont: AsyncStream<Int>.Continuation!
        self.samples = AsyncStream { localCont = $0 }
        self.continuation = localCont
    }

    public func start() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let hrType = HKQuantityType(.heartRate)
        try await store.requestAuthorization(toShare: [], read: [hrType])
        let unit = HKUnit.count().unitDivided(by: .minute())
        let predicate = HKQuery.predicateForSamples(withStart: Date(), end: nil, options: .strictStartDate)
        let q = HKAnchoredObjectQuery(
            type: hrType,
            predicate: predicate,
            anchor: anchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, newAnchor, _ in
            self?.anchor = newAnchor
            self?.emit(samples, unit: unit)
        }
        q.updateHandler = { [weak self] _, samples, _, newAnchor, _ in
            self?.anchor = newAnchor
            self?.emit(samples, unit: unit)
        }
        store.execute(q)
        query = q
    }

    private func emit(_ samples: [HKSample]?, unit: HKUnit) {
        guard let qs = samples as? [HKQuantitySample] else { return }
        for s in qs {
            let bpm = Int(s.quantity.doubleValue(for: unit).rounded())
            continuation?.yield(bpm)
        }
    }

    public func stop() {
        if let q = query { store.stop(q) }
        query = nil
        continuation?.finish()
    }
}
#endif
