import CoreLocation
import SwiftUI

enum Rarity: String, Codable, CaseIterable, Hashable {
    case common, rare, epic, legendary

    /// XP for at låse en seværdighed af denne sjældenhed op.
    var points: Int {
        switch self {
        case .common: 500
        case .rare: 1_000
        case .epic: 2_500
        case .legendary: 5_000
        }
    }

    var title: String {
        switch self {
        case .common: "Almindelig"
        case .rare: "Sjælden"
        case .epic: "Episk"
        case .legendary: "Legendarisk"
        }
    }

    var color: Color {
        switch self {
        case .common: .gray
        case .rare: .blue
        case .epic: .purple
        case .legendary: .orange
        }
    }
}

/// En seværdighed, der giver et trofæ, når man kører forbi den.
struct Landmark: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let city: String
    let latitude: Double
    let longitude: Double
    /// SF Symbol-navn
    let symbol: String
    let rarity: Rarity
    /// Hvor tæt på (i meter) man skal komme for at låse den op.
    var unlockRadius: CLLocationDistance = 250

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
