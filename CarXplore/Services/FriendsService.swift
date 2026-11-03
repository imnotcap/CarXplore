import Foundation

enum FriendsError: LocalizedError {
    case invalidCode
    case alreadyAdded

    var errorDescription: String? {
        switch self {
        case .invalidCode: "Koden skal være 6 tegn."
        case .alreadyAdded: "I er allerede venner."
        }
    }
}

/// Grænseflade mod backenden for venner. `MockFriendsService` er en
/// lokal attrap. En rigtig version kan bygges med CloudKit, Firebase
/// eller Supabase, så venners position og fremskridt synkroniseres.
protocol FriendsService: Sendable {
    func fetchFriends() async throws -> [Friend]
    func addFriend(code: String) async throws -> Friend
}

actor MockFriendsService: FriendsService {
    private var friends = Friend.samples
    private var addedCodes: Set<String> = []

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
        guard !addedCodes.contains(code) else { throw FriendsError.alreadyAdded }
        addedCodes.insert(code)
        let friend = Friend(
            id: UUID(), name: "Kører \(code)", car: "Ukendt bil",
            exploredKm2: Double.random(in: 5...300), trophies: Int.random(in: 0...6),
            trophyPoints: Int.random(in: 0...150),
            lastLatitude: 55.2 + Double.random(in: 0...1.2),
            lastLongitude: 9.5 + Double.random(in: 0...2.8),
            lastSeen: Date(), isDriving: Bool.random()
        )
        friends.append(friend)
        return friend
    }
}

@MainActor
final class FriendsStore: ObservableObject {
    @Published private(set) var friends: [Friend] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    /// Min egen vennekode, som jeg kan dele med andre.
    let myCode: String
    private let service: FriendsService

    init(service: FriendsService, defaults: UserDefaults = .standard) {
        self.service = service
        if let code = defaults.string(forKey: "friendCode") {
            myCode = code
        } else {
            let code = Self.makeCode()
            defaults.set(code, forKey: "friendCode")
            myCode = code
        }
    }

    static func makeCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in alphabet.randomElement()! })
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            friends = try await service.fetchFriends()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func add(code: String) async -> Bool {
        do {
            let friend = try await service.addFriend(code: code)
            friends.append(friend)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
