import SwiftUI

@main
struct CarXploreApp: App {
    @StateObject private var game = GameStore()
    @StateObject private var location = LocationService()
    @StateObject private var friends = FriendsStore(service: MockFriendsService())

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
            // Hent venners position jævnligt, mens appen er åben.
            while !Task.isCancelled {
                await friends.refresh()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { game.saveNow() }
        }
    }
}
