import SwiftUI

@main
struct CarXploreApp: App {
    @StateObject private var game = GameStore()
    @StateObject private var location = LocationService()
    @StateObject private var friends = FriendsStore.makeDefault()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(game)
                .environmentObject(location)
                .environmentObject(friends)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var game: GameStore
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var friends: FriendsStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            MapScreen()
                .tabItem { Label("Kort", systemImage: "map") }
            TrophiesView()
                .tabItem { Label("Trofæer", systemImage: "trophy") }
            FriendsView()
                .tabItem { Label("Venner", systemImage: "person.2") }
            ProfileView()
                .tabItem { Label("Profil", systemImage: "person.crop.circle") }
        }
        .onAppear {
            let store = game
            location.onLocations = { [weak store] locations in
                store?.record(locations)
            }
            Notifier.requestPermission()
        }
        .task {
            // Send mit fremskridt og hent venners, jævnligt mens appen er åben.
            await friends.loadProfile()
            while !Task.isCancelled {
                await friends.sync(currentStatus)
                try? await Task.sleep(for: .seconds(location.isTracking ? 15 : 60))
            }
        }
        .onChange(of: location.isTracking) {
            Task { await friends.sync(currentStatus) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { game.saveNow() }
        }
    }

    private var currentStatus: PlayerStatus {
        let coordinate = location.isTracking ? location.lastLocation?.coordinate : nil
        return PlayerStatus(
            exploredKm2: game.exploredAreaKm2,
            trophies: game.unlocked.count,
            trophyPoints: game.trophyPoints,
            isDriving: location.isTracking,
            latitude: coordinate?.latitude,
            longitude: coordinate?.longitude
        )
    }
}
