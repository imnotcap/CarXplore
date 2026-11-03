import Foundation

/// Niveau ud fra point, fx "Niveau 4 · Opdagelsesrejsende".
struct Level: Equatable {
    static let thresholds = [0, 50, 150, 400, 800, 1_500, 3_000, 6_000]
    static let titles = [
        "Søndagskører", "Pendler", "Eventyrer", "Opdagelsesrejsende",
        "Vejkriger", "Kortlægger", "Globetrotter", "Legende",
    ]

    let number: Int
    let title: String
    let score: Int
    /// Point der skal til for næste niveau (nil på højeste niveau).
    let nextAt: Int?

    init(score: Int) {
        let index = Self.thresholds.lastIndex { score >= $0 } ?? 0
        self.number = index + 1
        self.title = Self.titles[index]
        self.score = score
        self.nextAt = index + 1 < Self.thresholds.count ? Self.thresholds[index + 1] : nil
    }

    /// 0–1 mod næste niveau.
    var progress: Double {
        guard let nextAt else { return 1 }
        let start = Self.thresholds[number - 1]
        return Double(score - start) / Double(nextAt - start)
    }
}

/// Et trofæ, der låses op ved at nå et mål (km, ture, procent …).
struct Achievement: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let progress: Double
    let goal: Double
    let unit: String

    var isUnlocked: Bool { progress >= goal }
    var fraction: Double { min(max(progress / goal, 0), 1) }

    var progressText: String {
        let shown = Int(min(progress, goal).rounded(.down))
        return "\(shown.formatted()) / \(Int(goal).formatted()) \(unit)"
    }
}

extension GameStore {
    func achievements(friendCount: Int) -> [Achievement] {
        [
            Achievement(id: "fog-breaker", title: "Tågebryder", detail: "Oplås 10 % af dit lokalområde",
                        symbol: "cloud.sun.fill", progress: localAreaPercent, goal: 10, unit: "%"),
            Achievement(id: "road-enthusiast", title: "Vej-entusiast", detail: "Gennemfør 25 ture",
                        symbol: "road.lanes", progress: Double(tripCount), goal: 25, unit: "ture"),
            Achievement(id: "friend-finder", title: "Ven finder", detail: "Find din første ven i skyerne",
                        symbol: "person.2.fill", progress: Double(friendCount), goal: 1, unit: "ven"),
            Achievement(id: "globetrotter", title: "Globetrotter", detail: "Kør i alt 1.000 km",
                        symbol: "globe.europe.africa.fill", progress: totalKm, goal: 1_000, unit: "km"),
            Achievement(id: "night-owl", title: "Natuglen", detail: "Kør 50 km om natten",
                        symbol: "moon.stars.fill", progress: nightKm, goal: 50, unit: "km"),
            Achievement(id: "map-eater", title: "Kort-sluger", detail: "Oplås 50 % af dit lokalområde",
                        symbol: "map.fill", progress: localAreaPercent, goal: 50, unit: "%"),
            Achievement(id: "landmark-hunter", title: "Seværdighedsjæger", detail: "Lås 5 seværdigheder op",
                        symbol: "mappin.and.ellipse", progress: Double(unlocked.count), goal: 5, unit: "steder"),
            Achievement(id: "explorer", title: "Kortlægger", detail: "Udforsk 100 km²",
                        symbol: "square.grid.3x3.fill", progress: exploredAreaKm2, goal: 100, unit: "km²"),
        ]
    }
}
