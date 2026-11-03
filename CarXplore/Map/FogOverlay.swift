import MapKit
import UIKit

/// Et overlay, der dækker hele verden. Selve tågen tegnes af `FogRenderer`.
final class FogOverlay: NSObject, MKOverlay {
    let coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    let boundingMapRect = MKMapRect.world
}

/// Tegner tåge over hele kortet og skærer bløde huller, hvor man har kørt.
///
/// MapKit kalder `draw` fra baggrundstråde, så cellerne ligger i et
/// låst øjebliksbillede. De er grupperet i "spande" på 0,1° × 0,1°, så
/// hver kortflise kun gennemløber de celler, der ligger i nærheden.
final class FogRenderer: MKOverlayRenderer {
    private struct Bucket: Hashable {
        let lat: Int32
        let lon: Int32
    }

    private static let bucketSize: Int32 = 100 // celler pr. spand-side (0,1°)
    /// Radius på hvert "hul" i meter. Lidt større end en halv celle, så hullerne flyder sammen.
    private static let holeRadius: CLLocationDistance = 110

    private static let fogColor = UIColor(red: 0.80, green: 0.84, blue: 0.90, alpha: 1).cgColor
    private static let holeGradient: CGGradient = {
        let colors = [
            CGColor(gray: 0, alpha: 1),
            CGColor(gray: 0, alpha: 1),
            CGColor(gray: 0, alpha: 0),
        ] as CFArray
        return CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: colors, locations: [0, 0.55, 1])!
    }()

    private let lock = NSLock()
    private var buckets: [Bucket: [CellID]] = [:]

    override init(overlay: any MKOverlay) {
        super.init(overlay: overlay)
        alpha = 0.92
    }

    func update(cells: Set<CellID>) {
        var newBuckets: [Bucket: [CellID]] = [:]
        for cell in cells {
            newBuckets[Self.bucket(for: cell), default: []].append(cell)
        }
        lock.lock()
        buckets = newBuckets
        lock.unlock()
        setNeedsDisplay()
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        context.setFillColor(Self.fogColor)
        context.fill(rect(for: mapRect))

        let midLatitude = MKMapPoint(x: mapRect.midX, y: mapRect.midY).coordinate.latitude
        let radiusMapPoints = Self.holeRadius * MKMapPointsPerMeterAtLatitude(midLatitude)
        let radius = rect(for: MKMapRect(x: 0, y: 0, width: radiusMapPoints, height: radiusMapPoints)).width
        let padded = mapRect.insetBy(dx: -radiusMapPoints, dy: -radiusMapPoints)

        context.setBlendMode(.destinationOut)
        for cell in cells(in: padded) {
            let mapPoint = MKMapPoint(cell.center)
            guard padded.contains(mapPoint) else { continue }
            let center = point(for: mapPoint)
            context.drawRadialGradient(
                Self.holeGradient,
                startCenter: center, startRadius: 0,
                endCenter: center, endRadius: radius,
                options: []
            )
        }
    }

    private func cells(in mapRect: MKMapRect) -> [CellID] {
        let northWest = MKMapPoint(x: mapRect.minX, y: mapRect.minY).coordinate
        let southEast = MKMapPoint(x: mapRect.maxX, y: mapRect.maxY).coordinate
        let minLat = Self.bucketIndex(southEast.latitude)
        let maxLat = Self.bucketIndex(northWest.latitude)
        let minLon = Self.bucketIndex(northWest.longitude)
        let maxLon = Self.bucketIndex(southEast.longitude)

        lock.lock()
        defer { lock.unlock() }

        let rangeCount = (Int(maxLat) - Int(minLat) + 1) * (Int(maxLon) - Int(minLon) + 1)
        if maxLat < minLat || maxLon < minLon || rangeCount > buckets.count {
            // Langt zoomet ud: billigere bare at tage alle spande.
            return buckets.values.flatMap { $0 }
        }
        var result: [CellID] = []
        for lat in minLat...maxLat {
            for lon in minLon...maxLon {
                if let cells = buckets[Bucket(lat: lat, lon: lon)] {
                    result.append(contentsOf: cells)
                }
            }
        }
        return result
    }

    private static func bucketIndex(_ degrees: Double) -> Int32 {
        Int32((degrees / (CellID.degrees * Double(bucketSize))).rounded(.down))
    }

    private static func bucket(for cell: CellID) -> Bucket {
        Bucket(lat: floorDiv(cell.lat, bucketSize), lon: floorDiv(cell.lon, bucketSize))
    }

    private static func floorDiv(_ value: Int32, _ divisor: Int32) -> Int32 {
        let q = value / divisor
        return (value % divisor != 0 && (value < 0) != (divisor < 0)) ? q - 1 : q
    }
}
