import CoreLocation
import Foundation

struct Friend: Identifiable, Hashable {
    let id: UUID
    var name: String
    var car: String
    var exploredKm2: Double
    var trophies: Int
    var trophyPoints: Int
    var lastLatitude: Double?
    var lastLongitude: Double?
    var lastSeen: Date?
    var isDriving: Bool

    var score: Int { Int(exploredKm2 * 100) + trophyPoints }

    var coordinate: CLLocationCoordinate2D? {
        guard let lastLatitude, let lastLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: lastLatitude, longitude: lastLongitude)
    }

    var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
}

extension Friend {
    static let samples: [Friend] = [
        Friend(id: UUID(), name: "Mads Jensen", car: "VW Golf", exploredKm2: 182.4, trophies: 5,
               trophyPoints: 5_500, lastLatitude: 55.2405, lastLongitude: 11.7695,
               lastSeen: Date(), isDriving: true),
        Friend(id: UUID(), name: "Sofie Larsen", car: "Tesla Model 3", exploredKm2: 421.9, trophies: 9,
               trophyPoints: 12_000, lastLatitude: 55.6761, lastLongitude: 12.5683,
               lastSeen: Date().addingTimeInterval(-3_600), isDriving: false),
        Friend(id: UUID(), name: "Jonas Nielsen", car: "Toyota Yaris", exploredKm2: 64.2, trophies: 2,
               trophyPoints: 1_500, lastLatitude: 55.4038, lastLongitude: 10.4024,
               lastSeen: Date().addingTimeInterval(-86_400), isDriving: false),
    ]
}
