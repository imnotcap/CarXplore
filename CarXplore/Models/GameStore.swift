import CoreLocation
import Foundation
import UIKit

/// Holder spillerens fremskridt: udforskede celler og oplåste trofæer.
/// Gemmes lokalt som JSON i Application Support.
@MainActor
final class GameStore: ObservableObject {
    /// Hvor bred en stribe (radius i meter) der afsløres omkring bilen.
    static let revealRadius: CLLocationDistance = 150
    /// Dårligere GPS-præcision end dette ignoreres.
    static let maxAccuracy: CLLocationAccuracy = 65
    /// Spring længere end dette udfyldes ikke (GPS-fejl, færger, fly).
    static let maxInterpolationGap: CLLocationDistance = 3_000

    @Published private(set) var explored: Set<CellID> = []
    @Published private(set) var unlocked: [String: Date] = [:]
    /// Øges hver gang tågen ændrer sig. Kortet bruger den til at vide, hvornår det skal tegne igen.
    @Published private(set) var revision = 0
    /// Senest oplåste seværdighed. Vises som banner på kortet.
    @Published var recentUnlock: Landmark?

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

    // MARK: - Kørsel

    func record(_ locations: [CLLocation]) {
        var cells = explored
        let before = cells.count
        for location in locations {
            guard location.horizontalAccuracy >= 0,
                  location.horizontalAccuracy <= Self.maxAccuracy else { continue }
            reveal(at: location.coordinate, into: &cells)
        }
        if cells.count != before {
            explored = cells
            revision &+= 1
            scheduleSave()
        }
    }

    private func reveal(at coordinate: CLLocationCoordinate2D, into cells: inout Set<CellID>) {
        var points = [coordinate]
        if let last = lastCoordinate,
           Geo.distance(last, coordinate) <= Self.maxInterpolationGap {
            points = Geo.interpolate(from: last, to: coordinate, step: 50)
        }
        lastCoordinate = coordinate

        for point in points {
            cells.formUnion(Geo.cells(around: point, radius: Self.revealRadius))
            checkLandmarks(near: point)
        }
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

    /// Kaldes når en tur stoppes, så næste tur ikke forbindes med en lige streg.
    func endTrip() {
        lastCoordinate = nil
        saveNow()
    }

    func reset() {
        explored = []
        unlocked = [:]
        lastCoordinate = nil
        revision &+= 1
        saveNow()
    }

    // MARK: - Lagring

    private struct SaveData: Codable {
        var cells: [CellID]
        var unlocked: [String: Date]
    }

    static var defaultFileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("progress.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode(SaveData.self, from: data) else { return }
        explored = Set(saved.cells)
        unlocked = saved.unlocked
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
        let data = SaveData(cells: Array(explored), unlocked: unlocked)
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(data).write(to: fileURL, options: .atomic)
        } catch {
            print("CarXplore: kunne ikke gemme fremskridt: \(error)")
        }
    }
}
