import XCTest
import HeartRateKit

/// Mirrors how apps hold a source: a `@MainActor` model that keeps it and
/// starts it from a Task. Compiled in Swift 6 mode, this fails to build
/// ("sending value of non-Sendable type 'any HeartRateSource'") unless
/// `start()` runs on the caller's actor.
@MainActor
private final class Owner {
    let source: HeartRateSource
    init(source: HeartRateSource) { self.source = source }

    func activate() async {
        await Task { [source] in try? await source.start() }.value
    }
}

final class MainActorOwnerTests: XCTestCase {

    @MainActor
    func testMainActorOwnerStartsSourceOnMainActor() async {
        let mock = MockHeartRateSource(profile: .steady(bpm: 120), interval: 0.01)
        let owner = Owner(source: mock)
        await owner.activate()
        var it = mock.samples.makeAsyncIterator()
        let first = await it.next()
        XCTAssertEqual(first, 120)
        mock.stop()
    }
}
