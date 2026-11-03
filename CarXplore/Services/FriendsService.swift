import CoreLocation
import Foundation

enum FriendsError: LocalizedError {
    case invalidCode
    case ownCode
    case alreadyFriends
    case notSignedIn
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidCode: "Der findes ingen kører med den kode."
        case .ownCode: "Det er din egen kode 🙂"
        case .alreadyFriends: "I er allerede venner."
        case .notSignedIn: "Kunne ikke logge ind. Tjek din internetforbindelse."
        case .server(let message): message
        }
    }
}

/// Min egen profil, som den ligger på serveren.
struct MyProfile: Codable, Hashable {
    var id: UUID
    var displayName: String
    var car: String
    var friendCode: String
    var shareLocation: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case car
        case friendCode = "friend_code"
        case shareLocation = "share_location"
    }
}

/// Det, appen sender til serveren med jævne mellemrum.
struct PlayerStatus: Sendable {
    var exploredKm2: Double
    var trophies: Int
    var trophyPoints: Int
    var isDriving: Bool
    var latitude: Double?
    var longitude: Double?
}

/// Grænseflade mod venne-backenden. `SupabaseFriendsService` er den
/// rigtige. `MockFriendsService` bruges, når der ikke er konfigureret
/// en server (fx i CI og ved første opstart).
protocol FriendsService: Sendable {
    func myProfile() async throws -> MyProfile
    func updateProfile(displayName: String, car: String, shareLocation: Bool) async throws -> MyProfile
    func updateStatus(_ status: PlayerStatus) async throws
    func fetchFriends() async throws -> [Friend]
    func addFriend(code: String) async throws -> Friend
    func removeFriend(id: UUID) async throws
}

// MARK: - Mock

actor MockFriendsService: FriendsService {
    private var friends = Friend.samples
    private var me: MyProfile

    init(defaults: UserDefaults = .standard) {
        let code: String
        if let saved = defaults.string(forKey: "mockFriendCode") {
            code = saved
        } else {
            code = Self.makeCode()
            defaults.set(code, forKey: "mockFriendCode")
        }
        me = MyProfile(id: UUID(), displayName: "Mig", car: "", friendCode: code, shareLocation: true)
    }

    static func makeCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in alphabet.randomElement()! })
    }

    func myProfile() async throws -> MyProfile { me }

    func updateProfile(displayName: String, car: String, shareLocation: Bool) async throws -> MyProfile {
        me.displayName = displayName
        me.car = car
        me.shareLocation = shareLocation
        return me
    }

    func updateStatus(_ status: PlayerStatus) async throws {}

    func fetchFriends() async throws -> [Friend] {
        try await Task.sleep(for: .milliseconds(300))
        // Lad venner der kører flytte sig en smule, så kortet føles levende.
        for i in friends.indices where friends[i].isDriving {
            friends[i].lastLatitude? += Double.random(in: -0.004...0.004)
            friends[i].lastLongitude? += Double.random(in: -0.006...0.006)
            friends[i].exploredKm2 += Double.random(in: 0...0.5)
            friends[i].lastSeen = Date()
        }
        return friends
    }

    func addFriend(code: String) async throws -> Friend {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 6 else { throw FriendsError.invalidCode }
        guard code != me.friendCode else { throw FriendsError.ownCode }
        let friend = Friend(
            id: UUID(), name: "Kører \(code)", car: "Ukendt bil",
            exploredKm2: Double.random(in: 5...300), trophies: Int.random(in: 0...6),
            trophyPoints: Int.random(in: 0...8_000),
            lastLatitude: 55.2 + Double.random(in: 0...1.2),
            lastLongitude: 9.5 + Double.random(in: 0...2.8),
            lastSeen: Date(), isDriving: Bool.random()
        )
        friends.append(friend)
        return friend
    }

    func removeFriend(id: UUID) async throws {
        friends.removeAll { $0.id == id }
    }
}

// MARK: - Store

@MainActor
final class FriendsStore: ObservableObject {
    @Published private(set) var friends: [Friend] = []
    @Published private(set) var me: MyProfile?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    /// true når der ikke er nogen rigtig server, og vennerne er testdata.
    let isDemo: Bool
    private let service: FriendsService

    init(service: FriendsService, isDemo: Bool) {
        self.service = service
        self.isDemo = isDemo
    }

    /// Bruger Supabase, hvis appen er konfigureret med nøgler, ellers testdata.
    static func makeDefault() -> FriendsStore {
        if let config = SupabaseConfig.fromBundle() {
            return FriendsStore(service: SupabaseFriendsService(config: config), isDemo: false)
        }
        return FriendsStore(service: MockFriendsService(), isDemo: true)
    }

    var myCode: String { me?.friendCode ?? "······" }

    func loadProfile() async {
        do {
            me = try await service.myProfile()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            friends = try await service.fetchFriends()
        } catch {
            // Fejl ved baggrundsopdatering vises ikke. Listen bliver bare stående.
            print("CarXplore: kunne ikke hente venner: \(error)")
        }
    }

    /// Sender mit fremskridt og henter derefter venner.
    func sync(_ status: PlayerStatus) async {
        if me == nil { await loadProfile() }
        do {
            try await service.updateStatus(status)
        } catch {
            print("CarXplore: kunne ikke sende status: \(error)")
        }
        await refresh()
    }

    @discardableResult
    func add(code: String) async -> Bool {
        do {
            let friend = try await service.addFriend(code: code)
            friends.removeAll { $0.id == friend.id }
            friends.append(friend)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func remove(_ friend: Friend) async {
        do {
            try await service.removeFriend(id: friend.id)
            friends.removeAll { $0.id == friend.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateProfile(displayName: String, car: String, shareLocation: Bool) async {
        do {
            me = try await service.updateProfile(displayName: displayName, car: car, shareLocation: shareLocation)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
