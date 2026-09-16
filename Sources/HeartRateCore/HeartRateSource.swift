//
//  HeartRateSource.swift
//  HeartRateKit
//
//  A live stream of heart-rate readings (BPM). Implementations: BLE strap,
//  HealthKit anchored query, or an app-provided bridge (e.g. paired watch).
//

import Foundation

public protocol HeartRateSource: AnyObject {
    var samples: AsyncStream<Int> { get }
    func start() async throws
    func stop()
}
