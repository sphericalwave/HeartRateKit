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
    /// Runs on the caller's actor rather than the global executor, so an
    /// `@MainActor` owner can start a source it also reads without sending
    /// it across isolation domains (BLE drives a main-queue central).
    nonisolated(nonsending) func start() async throws
    func stop()
}
