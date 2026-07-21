//
//  WatchHeartRateSource.swift
//  HeartRateKit
//
//  iOS-side HeartRateSource that receives live BPM from a paired Apple Watch
//  over WatchConnectivity (the watch runs WatchHRStreamer). Selecting the
//  resolution pushes it to the watch via applicationContext.
//

#if os(iOS)
import Foundation
import WatchConnectivity

public final class WatchHeartRateSource: NSObject, HeartRateSource, WCSessionDelegate {

    public let samples: AsyncStream<Int>
    private var continuation: AsyncStream<Int>.Continuation?
    private var resolution: HRResolution = .high

    public override init() {
        var cont: AsyncStream<Int>.Continuation!
        self.samples = AsyncStream { cont = $0 }
        super.init()
        self.continuation = cont
    }

    public func start() async throws {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
        pushContext(streaming: true)
    }

    public func stop() {
        pushContext(streaming: false)
    }

    /// Change the watch's forwarding density.
    public func setResolution(_ r: HRResolution) {
        resolution = r
        pushContext(streaming: true)
    }

    private func pushContext(streaming: Bool) {
        guard WCSession.isSupported() else { return }
        let ctx: [String: Any] = [
            "streaming": streaming,
            "resolution": resolution.rawValue,
        ]
        try? WCSession.default.updateApplicationContext(ctx)
    }

    private func ingest(_ message: [String: Any]) {
        if let bpm = WatchHRMessage.decodeBpm(message) {
            continuation?.yield(bpm)
        }
    }

    // MARK: WCSessionDelegate

    public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        ingest(message)
    }

    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        ingest(userInfo)
    }

    public func session(_ session: WCSession,
                        activationDidCompleteWith activationState: WCSessionActivationState,
                        error: Error?) {}

    public func sessionDidBecomeInactive(_ session: WCSession) {}

    public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
#endif
