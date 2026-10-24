import XCTest
import CoreBluetooth
@testable import HeartRateKit

final class BLEStateRestorationTests: XCTestCase {

    func testNoRestoreIdentifierMeansNoOptions() {
        XCTAssertNil(BLEHeartRateSource.centralOptions(restoreIdentifier: nil))
    }

    func testRestoreIdentifierIsPassedToTheCentral() {
        let options = BLEHeartRateSource.centralOptions(restoreIdentifier: "app.hr")
        #if os(macOS)
        // Core Bluetooth has no state restoration on macOS.
        XCTAssertNil(options)
        #else
        XCTAssertEqual(options?[CBCentralManagerOptionRestoreIdentifierKey] as? String, "app.hr")
        #endif
    }

    func testPicksTheRememberedStrapAmongRestoredPeripherals() {
        let a = UUID(), b = UUID()
        XCTAssertEqual(BLEHeartRateSource.pickRestored([a, b], id: { $0 }, preferred: b), b)
    }

    func testFallsBackToTheFirstRestoredPeripheral() {
        let a = UUID(), b = UUID()
        XCTAssertEqual(BLEHeartRateSource.pickRestored([a, b], id: { $0 }, preferred: nil), a)
        XCTAssertEqual(BLEHeartRateSource.pickRestored([a, b], id: { $0 }, preferred: UUID()), a)
    }

    func testNothingRestored() {
        XCTAssertNil(BLEHeartRateSource.pickRestored([UUID](), id: { $0 }, preferred: UUID()))
    }
}
