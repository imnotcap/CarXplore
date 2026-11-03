import Foundation
import Supabase

/// URL og anon-nøgle til Supabase. De sættes i `Secrets.xcconfig` (se README)
/// og havner i Info.plist som `SupabaseURL` og `SupabaseAnonKey`.
struct SupabaseConfig {
    let url: URL
    let anonKey: String

    static func fromBundle(_ bundle: Bundle = .main) -> SupabaseConfig? {
        guard let urlString = bundle.object(forInfoDictionaryKey: "SupabaseURL") as? String,
              let key = bundle.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String,
              !urlString.isEmpty, !key.isEmpty,
              !urlString.contains("$("), !key.contains("$("),
              let url = URL(string: urlString) else { return nil }
        return SupabaseConfig(url: url, anonKey: key)
    }
}

/// Venne-backend på Supabase. Al logik ligger i Postgres-funktionerne i
/// `supabase/migrations`. Her kalder vi dem bare.
///
/// Login sker anonymt første gang (kontoen gemmes i nøgleringen). Senere
/// kan "Log ind med Apple" kobles på samme konto med `linkIdentity`.
final class SupabaseFriendsService: FriendsService {
    private let client: SupabaseClient

    init(config: SupabaseConfig) {
        client = SupabaseClient(supabaseURL: config.url, supabaseKey: config.anonKey)
    }

    private func ensureSignedIn() async throws {
        if (try? await client.auth.session) != nil { return }
        do {
            _ = try await client.auth.signInAnonymously()
        } catch {
            throw FriendsError.notSignedIn
        }
    }

    /// Kører et kald og oversætter serverens fejlkoder til pæne fejl.
    @discardableResult
    private func call<T>(_ body: () async throws -> T) async throws -> T {
        try await ensureSignedIn()
        do {
            return try await body()
        } catch let error as PostgrestError {
            switch error.message {
            case let m where m.contains("invalid_code"): throw FriendsError.invalidCode
            case let m where m.contains("own_code"): throw FriendsError.ownCode
            case let m where m.contains("already_friends"): throw FriendsError.alreadyFriends
            case let m where m.contains("not_authenticated"): throw FriendsError.notSignedIn
            default: throw FriendsError.server(error.message)
            }
        }
    }

    // MARK: FriendsService

    func myProfile() async throws -> MyProfile {
        try await call {
            let rows: [MyProfile] = try await client.rpc("my_profile").execute().value
            guard let me = rows.first else { throw FriendsError.notSignedIn }
            return me
        }
    }

    func updateProfile(displayName: String, car: String, shareLocation: Bool) async throws -> MyProfile {
        try await call {
            let params = UpdateProfileParams(displayName: displayName, car: car, shareLocation: shareLocation)
            let rows: [MyProfile] = try await client.rpc("update_profile", params: params).execute().value
            guard let me = rows.first else { throw FriendsError.notSignedIn }
            return me
        }
    }

    func updateStatus(_ status: PlayerStatus) async throws {
        try await call {
            _ = try await client.rpc("update_status", params: UpdateStatusParams(status)).execute()
        }
    }

    func fetchFriends() async throws -> [Friend] {
        try await call {
            let rows: [FriendRow] = try await client.rpc("get_friends").execute().value
            return rows.map(\.friend)
        }
    }

    func addFriend(code: String) async throws -> Friend {
        try await call {
            let rows: [FriendRow] = try await client
                .rpc("add_friend", params: ["p_code": code.trimmingCharacters(in: .whitespacesAndNewlines)])
                .execute().value
            guard let row = rows.first else { throw FriendsError.invalidCode }
            return row.friend
        }
    }

    func removeFriend(id: UUID) async throws {
        try await call {
            _ = try await client.rpc("remove_friend", params: ["p_friend_id": id]).execute()
        }
    }
}

// MARK: - DTO'er (navne matcher SQL-funktionerne)

private struct UpdateProfileParams: Encodable, Sendable {
    let displayName: String
    let car: String
    let shareLocation: Bool

    enum CodingKeys: String, CodingKey {
        case displayName = "p_display_name"
        case car = "p_car"
        case shareLocation = "p_share_location"
    }
}

private struct UpdateStatusParams: Encodable, Sendable {
    let exploredKm2: Double
    let trophies: Int
    let trophyPoints: Int
    let isDriving: Bool
    let lat: Double?
    let lon: Double?

    init(_ s: PlayerStatus) {
        exploredKm2 = s.exploredKm2
        trophies = s.trophies
        trophyPoints = s.trophyPoints
        isDriving = s.isDriving
        lat = s.latitude
        lon = s.longitude
    }

    enum CodingKeys: String, CodingKey {
        case exploredKm2 = "p_explored_km2"
        case trophies = "p_trophies"
        case trophyPoints = "p_trophy_points"
        case isDriving = "p_is_driving"
        case lat = "p_lat"
        case lon = "p_lon"
    }
}

private struct FriendRow: Decodable {
    let id: UUID
    let displayName: String
    let car: String
    let exploredKm2: Double
    let trophies: Int
    let trophyPoints: Int
    let isDriving: Bool
    let lastLat: Double?
    let lastLon: Double?
    let lastSeen: Date?

    enum CodingKeys: String, CodingKey {
        case id, car, trophies
        case displayName = "display_name"
        case exploredKm2 = "explored_km2"
        case trophyPoints = "trophy_points"
        case isDriving = "is_driving"
        case lastLat = "last_lat"
        case lastLon = "last_lon"
        case lastSeen = "last_seen"
    }

    var friend: Friend {
        Friend(id: id, name: displayName, car: car, exploredKm2: exploredKm2, trophies: trophies,
               trophyPoints: trophyPoints, lastLatitude: lastLat, lastLongitude: lastLon,
               lastSeen: lastSeen, isDriving: isDriving)
    }
}
