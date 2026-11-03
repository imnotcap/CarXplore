import CoreLocation

/// Verden er delt op i et gitter af celler på 0,001° × 0,001°
/// (ca. 111 m nord-syd og ca. 64 m øst-vest i Danmark).
/// En celle er "udforsket", når man har kørt tæt nok forbi den.
struct CellID: Hashable, Codable {
    static let degrees = 0.001

    let lat: Int32
    let lon: Int32

    init(lat: Int32, lon: Int32) {
        self.lat = lat
        self.lon = lon
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        lat = Int32((coordinate.latitude / Self.degrees).rounded(.down))
        lon = Int32((coordinate.longitude / Self.degrees).rounded(.down))
    }

    var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: (Double(lat) + 0.5) * Self.degrees,
            longitude: (Double(lon) + 0.5) * Self.degrees
        )
    }

    /// Cellens omtrentlige areal i km².
    var areaKm2: Double {
        let height = Geo.metersPerDegreeLat * Self.degrees / 1000
        let width = height * cos(center.latitude * .pi / 180)
        return height * width
    }
}

enum Geo {
    static let metersPerDegreeLat = 111_320.0

    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    /// Punkter med højst `step` meters mellemrum fra `a` (ekskl.) til `b` (inkl.).
    /// Bruges til at udfylde hullerne, når GPS'en kun melder sig hver 20.–50. meter.
    static func interpolate(
        from a: CLLocationCoordinate2D,
        to b: CLLocationCoordinate2D,
        step: CLLocationDistance
    ) -> [CLLocationCoordinate2D] {
        let total = distance(a, b)
        let count = max(1, Int((total / step).rounded(.up)))
        return (1...count).map { i in
            let t = Double(i) / Double(count)
            return CLLocationCoordinate2D(
                latitude: a.latitude + (b.latitude - a.latitude) * t,
                longitude: a.longitude + (b.longitude - a.longitude) * t
            )
        }
    }

    /// Alle celler hvis centrum ligger inden for `radius` meter af `coordinate`.
    /// Cellen man står i er altid med.
    static func cells(around coordinate: CLLocationCoordinate2D, radius: CLLocationDistance) -> [CellID] {
        let center = CellID(coordinate)
        let metersPerDegreeLon = metersPerDegreeLat * max(cos(coordinate.latitude * .pi / 180), 0.01)
        let dLat = Int32((radius / metersPerDegreeLat / CellID.degrees).rounded(.up))
        let dLon = Int32((radius / metersPerDegreeLon / CellID.degrees).rounded(.up))

        var result = [center]
        for y in (center.lat - dLat)...(center.lat + dLat) {
            for x in (center.lon - dLon)...(center.lon + dLon) {
                let cell = CellID(lat: y, lon: x)
                if cell == center { continue }
                let c = cell.center
                let dy = (c.latitude - coordinate.latitude) * metersPerDegreeLat
                let dx = (c.longitude - coordinate.longitude) * metersPerDegreeLon
                if dx * dx + dy * dy <= radius * radius {
                    result.append(cell)
                }
            }
        }
        return result
    }
}
