import CoreLocation
import XCTest
@testable import CarXplore

final class GeoTests: XCTestCase {
    func testCellRoundTrip() {
        let coordinate = CLLocationCoordinate2D(latitude: 55.2299, longitude: 11.7609)
        let cell = CellID(coordinate)
        XCTAssertEqual(CellID(cell.center), cell)
        XCTAssertLessThan(Geo.distance(cell.center, coordinate), 100)
    }

    func testNegativeCoordinatesFloor() {
        let cell = CellID(CLLocationCoordinate2D(latitude: -33.8688, longitude: -0.0005))
        XCTAssertEqual(cell.lat, -33869)
        XCTAssertEqual(cell.lon, -1)
    }

    func testCellsAroundIncludesCenterAndRespectsRadius() {
        let coordinate = CLLocationCoordinate2D(latitude: 55.68, longitude: 12.57)
        let cells = Geo.cells(around: coordinate, radius: 150)
        XCTAssertTrue(cells.contains(CellID(coordinate)))
        XCTAssertGreaterThan(cells.count, 5)
        for cell in cells where cell != CellID(coordinate) {
            XCTAssertLessThanOrEqual(Geo.distance(cell.center, coordinate), 160)
        }
    }

    func testInterpolationStepSize() {
        let a = CLLocationCoordinate2D(latitude: 55.0, longitude: 11.0)
        let b = CLLocationCoordinate2D(latitude: 55.01, longitude: 11.0) // ca. 1,1 km
        let points = Geo.interpolate(from: a, to: b, step: 50)
        XCTAssertEqual(points.count, 23)
        XCTAssertEqual(points.last?.latitude ?? 0, b.latitude, accuracy: 1e-9)
    }
}
