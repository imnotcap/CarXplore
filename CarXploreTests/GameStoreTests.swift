import CoreLocation
import XCTest
@testable import CarXplore

@MainActor
final class GameStoreTests: XCTestCase {
    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("carxplore-test-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL)
        super.tearDown()
    }

    private func location(_ lat: Double, _ lon: Double, accuracy: Double = 10) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                   altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 10, timestamp: Date())
    }

    private func makeStore() -> GameStore {
        GameStore(fileURL: fileURL, notifiesUser: false)
    }

    func testDrivingRevealsCellsAlongRoute() {
        let store = makeStore()
        store.record([location(55.20, 11.70)])
        let afterFirst = store.explored.count
        XCTAssertGreaterThan(afterFirst, 0)

        // 1 km mod nord i ét hop: ruten imellem skal også afsløres.
        store.record([location(55.209, 11.70)])
        XCTAssertTrue(store.explored.contains(CellID(CLLocationCoordinate2D(latitude: 55.2045, longitude: 11.70))))
        XCTAssertGreaterThan(store.explored.count, afterFirst)
    }

    func testInaccurateLocationsAreIgnored() {
        let store = makeStore()
        store.record([location(55.20, 11.70, accuracy: 500)])
        XCTAssertTrue(store.explored.isEmpty)
    }

    func testLongJumpIsNotInterpolated() {
        let store = makeStore()
        store.record([location(55.0, 11.0)])
        store.record([location(56.0, 11.0)]) // 111 km
        let midway = CellID(CLLocationCoordinate2D(latitude: 55.5, longitude: 11.0))
        XCTAssertFalse(store.explored.contains(midway))
    }

    func testPassingLandmarkUnlocksTrophy() {
        let store = makeStore()
        XCTAssertTrue(store.unlocked.isEmpty)
        store.record([location(55.2300, 11.7612)]) // ved Næstved Rådhus
        XCTAssertNotNil(store.unlocked["naestved-raadhus"])
        XCTAssertEqual(store.recentUnlock?.id, "naestved-raadhus")
        XCTAssertGreaterThanOrEqual(store.score, Rarity.common.points)
    }

    func testProgressIsPersisted() {
        let store = makeStore()
        store.record([location(55.2300, 11.7612)])
        store.saveNow()

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.explored, store.explored)
        XCTAssertNotNil(reloaded.unlocked["naestved-raadhus"])
    }

    func testReset() {
        let store = makeStore()
        store.record([location(55.2300, 11.7612)])
        store.reset()
        XCTAssertTrue(store.explored.isEmpty)
        XCTAssertTrue(store.unlocked.isEmpty)
    }
}
