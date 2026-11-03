import CoreLocation
import SwiftUI

struct TrophiesView: View {
    @EnvironmentObject private var game: GameStore
    @EnvironmentObject private var location: LocationService

    private var unlockedLandmarks: [Landmark] {
        game.landmarks
            .filter { game.unlocked[$0.id] != nil }
            .sorted { (game.unlocked[$0.id] ?? .distantPast) > (game.unlocked[$1.id] ?? .distantPast) }
    }

    private var lockedLandmarks: [Landmark] {
        let locked = game.landmarks.filter { game.unlocked[$0.id] == nil }
        guard let here = location.lastLocation?.coordinate else { return locked }
        return locked.sorted { Geo.distance($0.coordinate, here) < Geo.distance($1.coordinate, here) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(game.unlocked.count) af \(game.landmarks.count) seværdigheder")
                            .font(.headline)
                        ProgressView(value: Double(game.unlocked.count),
                                     total: Double(max(game.landmarks.count, 1)))
                        Text("\(game.trophyPoints) trofæpoint")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                if !unlockedLandmarks.isEmpty {
                    Section("Låst op") {
                        ForEach(unlockedLandmarks) { landmark in
                            TrophyRow(landmark: landmark, unlockedAt: game.unlocked[landmark.id], distance: nil)
                        }
                    }
                }

                Section("Mangler") {
                    ForEach(lockedLandmarks) { landmark in
                        TrophyRow(
                            landmark: landmark,
                            unlockedAt: nil,
                            distance: location.lastLocation.map { Geo.distance(landmark.coordinate, $0.coordinate) }
                        )
                    }
                }
            }
            .navigationTitle("Trofæer")
        }
    }
}

private struct TrophyRow: View {
    let landmark: Landmark
    let unlockedAt: Date?
    let distance: CLLocationDistance?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: unlockedAt != nil ? landmark.symbol : "lock.fill")
                .font(.title2)
                .frame(width: 44, height: 44)
                .foregroundStyle(unlockedAt != nil ? .white : .secondary)
                .background(unlockedAt != nil ? landmark.rarity.color : Color(.systemGray5),
                            in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(landmark.name).font(.headline)
                Text(landmark.city).font(.subheadline).foregroundStyle(.secondary)
                if let unlockedAt {
                    Text("Låst op \(unlockedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                } else if let distance {
                    Text("\((distance / 1000).formatted(.number.precision(.fractionLength(0...1)))) km væk")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing) {
                Text("+\(landmark.rarity.points)").font(.headline.monospacedDigit())
                Text(landmark.rarity.title).font(.caption2).foregroundStyle(landmark.rarity.color)
            }
        }
    }
}
