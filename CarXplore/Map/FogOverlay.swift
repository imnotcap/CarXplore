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

    /// Grundfarven under skyerne.
    private static let fogColor = UIColor(red: 0.40, green: 0.45, blue: 0.53, alpha: 1).cgColor

    /// En flisbar sky-tekstur (256×256), tegnet af bløde hvide klatter.
    /// Klatterne tegnes også forskudt ±256 px, så kanterne passer sammen.
    private static let cloudTexture: CGImage? = {
        let size = 256
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 0.55),
                         CGColor(red: 1, green: 1, blue: 1, alpha: 0.18),
                         CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray,
                locations: [0, 0.6, 1]) else { return nil }

        var seed: UInt64 = 0x5EED_CA7
        func random() -> CGFloat {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return CGFloat(seed >> 33) / CGFloat(UInt64(1) << 31)
        }

        for _ in 0..<80 {
            let x = random() * CGFloat(size)
            let y = random() * CGFloat(size)
            let radius = 16 + random() * 52
            for dx: CGFloat in [-256, 0, 256] {
                for dy: CGFloat in [-256, 0, 256] {
                    let center = CGPoint(x: x + dx, y: y + dy)
                    ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                           endCenter: center, endRadius: radius, options: [])
                }
            }
        }
        return ctx.makeImage()
    }()
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
        alpha = 0.96
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

        // To lag skyer i forskellig størrelse giver dybde. Størrelsen følger
        // zoomniveauet, så skyerne ser ens ud på skærmen, og flisningen starter i
        // verdens origo, så skyerne ligger stille, når man panorerer.
        if let texture = Self.cloudTexture {
            for scale: CGFloat in [1.4, 3.1] {
                let side = 256 / zoomScale * scale
                context.draw(texture, in: CGRect(x: 0, y: 0, width: side, height: side), byTiling: true)
            }
        }

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
