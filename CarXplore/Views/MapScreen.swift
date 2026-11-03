import SwiftUI

struct MapScreen: View {
    @EnvironmentObject private var game: GameStore
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var friends: FriendsStore
    @State private var followUser = true

    var body: some View {
        ZStack(alignment: .top) {
            ExploreMapView(
                explored: game.explored,
                revision: game.revision,
                landmarks: game.landmarks,
                unlocked: Set(game.unlocked.keys),
                friends: friends.friends,
                followUser: $followUser
            )
            .ignoresSafeArea(edges: .top)

            VStack(spacing: 12) {
                StatsBar()
                if let landmark = game.recentUnlock {
                    UnlockBanner(landmark: landmark)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .overlay(alignment: .bottom) { controls }
        .animation(.spring(duration: 0.4), value: game.recentUnlock)
        .task(id: game.recentUnlock?.id) {
            guard game.recentUnlock != nil else { return }
            try? await Task.sleep(for: .seconds(5))
            game.recentUnlock = nil
        }
        .onAppear {
            if location.authorization == .notDetermined { location.requestWhenInUse() }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                if location.isTracking {
                    location.stopTrip()
                    game.endTrip()
                } else {
                    location.startTrip()
                    followUser = true
                }
            } label: {
                Label(location.isTracking ? "Stop tur" : "Start tur",
                      systemImage: location.isTracking ? "stop.fill" : "car.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(location.isTracking ? .red : .accentColor)
            .clipShape(Capsule())

            Button {
                followUser = true
            } label: {
                Image(systemName: followUser ? "location.fill" : "location")
                    .font(.title3)
                    .frame(width: 50, height: 50)
            }
            .background(.regularMaterial, in: Circle())
        }
        .padding()
    }
}

private struct StatsBar: View {
    @EnvironmentObject private var game: GameStore

    var body: some View {
        HStack {
            stat(value: game.exploredAreaKm2.formatted(.number.precision(.fractionLength(1))),
                 label: "km² udforsket", icon: "cloud.sun")
            Divider().frame(height: 30)
            stat(value: "\(game.unlocked.count)/\(game.landmarks.count)", label: "trofæer", icon: "trophy")
            Divider().frame(height: 30)
            stat(value: "\(game.score)", label: "point", icon: "star")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func stat(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 2) {
            Label(value, systemImage: icon)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct UnlockBanner: View {
    let landmark: Landmark

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.title)
                .foregroundStyle(landmark.rarity.color)
            VStack(alignment: .leading, spacing: 2) {
                Text("Nyt trofæ!").font(.caption).foregroundStyle(.secondary)
                Text(landmark.name).font(.headline)
                Text("\(landmark.rarity.title) · +\(landmark.rarity.points) point")
                    .font(.caption)
                    .foregroundStyle(landmark.rarity.color)
            }
            Spacer()
        }
        .padding()
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(landmark.rarity.color, lineWidth: 2))
    }
}
