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
    /// What the phone wants the watch doing. Held because activation is
    /// asynchronous — a context pushed before it completes is dropped, so the
    /// intent is replayed once the session is up.
    private var wantsStreaming = false

    public override init() {
        var cont: AsyncStream<Int>.Continuation!
        self.samples = AsyncStream { cont = $0 }
        super.init()
        self.continuation = cont
    }

    public func start() async throws {
        guard WCSession.isSupported() else { return }
        wantsStreaming = true
        let s = WCSession.default
        s.delegate = self
        if s.activationState != .activated { s.activate() }
        pushContext(streaming: true)
    }

    public func stop() {
        wantsStreaming = false
        pushContext(streaming: false)
    }

    /// Whether a watch is paired with the app installed — the difference
    /// between "waiting for a reading" and "there's nothing to wait for".
    public var isWatchAppAvailable: Bool {
        guard WCSession.isSupported() else { return false }
        let s = WCSession.default
        return s.isPaired && s.isWatchAppInstalled
    }

    /// Change the watch's forwarding density.
    public func setResolution(_ r: HRResolution) {
        resolution = r
        pushContext(streaming: true)
    }

    private func pushContext(streaming: Bool) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        // Before activation completes this throws and the intent is lost;
        // `session(_:activationDidCompleteWith:)` replays it instead.
        guard session.activationState == .activated else { return }
        try? session.updateApplicationContext(
            WatchHRContext.encode(streaming: streaming, resolution: resolution)
        )
        // applicationContext only holds the latest value and is delivered on
        // the watch's schedule; a reachable watch gets it immediately.
        if session.isReachable {
            session.sendMessage(WatchHRContext.encode(streaming: streaming, resolution: resolution),
                                replyHandler: nil,
                                errorHandler: nil)
        }
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
                        error: Error?) {
        guard activationState == .activated else { return }
        pushContext(streaming: wantsStreaming)
    }

    public func sessionDidBecomeInactive(_ session: WCSession) {}

    public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
#endif
