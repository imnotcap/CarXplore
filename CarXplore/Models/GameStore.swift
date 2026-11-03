import CoreLocation
import Foundation
import UIKit

/// Holder spillerens fremskridt: udforskede celler, trofæer og kørselsstatistik.
/// Gemmes lokalt som JSON i Application Support.
@MainActor
final class GameStore: ObservableObject {
    /// Hvor bred en stribe (radius i meter) der afsløres omkring bilen.
    static let revealRadius: CLLocationDistance = 150
    /// Dårligere GPS-præcision end dette ignoreres.
    static let maxAccuracy: CLLocationAccuracy = 65
    /// Spring længere end dette udfyldes ikke (GPS-fejl, færger, fly).
    static let maxInterpolationGap: CLLocationDistance = 3_000
    /// "Dit lokalområde" er en cirkel med denne radius omkring det første sted, du kørte.
    static let localAreaRadius: CLLocationDistance = 10_000

    @Published private(set) var explored: Set<CellID> = []
    @Published private(set) var unlocked: [String: Date] = [:]
    /// Øges hver gang tågen ændrer sig. Kortet bruger den til at vide, hvornår det skal tegne igen.
    @Published private(set) var revision = 0
    /// Senest oplåste seværdighed. Vises som banner på kortet.
    @Published var recentUnlock: Landmark?

    @Published private(set) var totalKm: Double = 0
    @Published private(set) var nightKm: Double = 0
    @Published private(set) var tripCount = 0
    @Published private(set) var home: CLLocationCoordinate2D?
    @Published private(set) var localExploredCells = 0
    /// Den aktuelle turs rute. Vises som neonstreg på kortet.
    @Published private(set) var tripPath: [CLLocationCoordinate2D] = []

    let landmarks: [Landmark]

    private var lastCoordinate: CLLocationCoordinate2D?
    private let fileURL: URL
    private let notifiesUser: Bool
    private var saveTask: Task<Void, Never>?

    init(
        landmarks: [Landmark] = LandmarkCatalog.all,
        fileURL: URL = GameStore.defaultFileURL,
        notifiesUser: Bool = true
    ) {
        self.landmarks = landmarks
        self.fileURL = fileURL
        self.notifiesUser = notifiesUser
        load()
    }

    // MARK: - Statistik

    var exploredAreaKm2: Double {
        explored.reduce(0) { $0 + $1.areaKm2 }
    }

    var trophyPoints: Int {
        landmarks.filter { unlocked[$0.id] != nil }.reduce(0) { $0 + $1.rarity.points }
    }

    /// Point = 10 pr. udforsket km² + trofæpoint.
    var score: Int {
        Int(exploredAreaKm2 * 10) + trophyPoints
    }

    var level: Level { Level(score: score) }

    /// Hvor stor en del (0–100 %) af lokalområdet der er låst op.
    var localAreaPercent: Double {
        guard let home else { return 0 }
        let cellArea = CellID(home).areaKm2
        let totalArea = Double.pi * pow(Self.localAreaRadius / 1000, 2)
        return min(100, Double(localExploredCells) * cellArea / totalArea * 100)
    }

    // MARK: - Kørsel

    func beginTrip() {
        tripCount += 1
        tripPath = []
        lastCoordinate = nil
        scheduleSave()
    }

    /// Kaldes når en tur stoppes, så næste tur ikke forbindes med en lige streg.
    func endTrip() {
        lastCoordinate = nil
        saveNow()
    }

    func record(_ locations: [CLLocation]) {
        var cells = explored
        var added: [CellID] = []
        var path: [CLLocationCoordinate2D] = []
        for location in locations {
            guard location.horizontalAccuracy >= 0,
                  location.horizontalAccuracy <= Self.maxAccuracy else { continue }
            reveal(location, into: &cells, added: &added)
            path.append(location.coordinate)
        }
        guard !path.isEmpty else { return }
        tripPath.append(contentsOf: path)
        if !added.isEmpty {
            localExploredCells += countLocal(added)
            explored = cells
            revision &+= 1
        }
        scheduleSave()
    }

    private func reveal(_ location: CLLocation, into cells: inout Set<CellID>, added: inout [CellID]) {
        let coordinate = location.coordinate
        if home == nil { home = coordinate }

        var points = [coordinate]
        if let last = lastCoordinate {
            let distance = Geo.distance(last, coordinate)
            if distance <= Self.maxInterpolationGap {
                points = Geo.interpolate(from: last, to: coordinate, step: 50)
                totalKm += distance / 1000
                if Self.isNight(location.timestamp) { nightKm += distance / 1000 }
            }
        }
        lastCoordinate = coordinate

        for point in points {
            for cell in Geo.cells(around: point, radius: Self.revealRadius) where cells.insert(cell).inserted {
                added.append(cell)
            }
            checkLandmarks(near: point)
        }
    }

    static func isNight(_ date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour >= 22 || hour < 5
    }

    private func countLocal<S: Sequence>(_ cells: S) -> Int where S.Element == CellID {
        guard let home else { return 0 }
        let metersPerDegreeLon = Geo.metersPerDegreeLat * cos(home.latitude * .pi / 180)
        let r2 = Self.localAreaRadius * Self.localAreaRadius
        var count = 0
        for cell in cells {
            let c = cell.center
            let dy = (c.latitude - home.latitude) * Geo.metersPerDegreeLat
            let dx = (c.longitude - home.longitude) * metersPerDegreeLon
            if dx * dx + dy * dy <= r2 { count += 1 }
        }
        return count
    }

    private func checkLandmarks(near coordinate: CLLocationCoordinate2D) {
        for landmark in landmarks where unlocked[landmark.id] == nil {
            if Geo.distance(landmark.coordinate, coordinate) <= landmark.unlockRadius {
                unlock(landmark)
            }
        }
    }

    private func unlock(_ landmark: Landmark) {
        unlocked[landmark.id] = Date()
        recentUnlock = landmark
        scheduleSave()
        guard notifiesUser else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Notifier.trophyUnlocked(landmark)
    }

    func reset() {
        explored = []
        unlocked = [:]
        totalKm = 0
        nightKm = 0
        tripCount = 0
        home = nil
        localExploredCells = 0
        tripPath = []
        lastCoordinate = nil
        revision &+= 1
        saveNow()
    }

    // MARK: - Lagring

    private struct SaveData: Codable {
        var cells: [CellID]
        var unlocked: [String: Date]
        // Tilføjet i v0.2. Valgfrie, så ældre gemte filer stadig kan læses.
        var totalKm: Double?
        var nightKm: Double?
        var tripCount: Int?
        var homeLatitude: Double?
        var homeLongitude: Double?
    }

    nonisolated static var defaultFileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("progress.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode(SaveData.self, from: data) else { return }
        explored = Set(saved.cells)
        unlocked = saved.unlocked
        totalKm = saved.totalKm ?? 0
        nightKm = saved.nightKm ?? 0
        tripCount = saved.tripCount ?? 0
        if let lat = saved.homeLatitude, let lon = saved.homeLongitude {
            home = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        localExploredCells = countLocal(explored)
        revision &+= 1
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        let data = SaveData(
            cells: Array(explored), unlocked: unlocked,
            totalKm: totalKm, nightKm: nightKm, tripCount: tripCount,
            homeLatitude: home?.latitude, homeLongitude: home?.longitude
        )
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(data).write(to: fileURL, options: .atomic)
        } catch {
            print("CarXplore: kunne ikke gemme fremskridt: \(error)")
        }
    }
}
