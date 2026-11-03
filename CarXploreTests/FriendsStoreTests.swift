import XCTest
@testable import CarXplore

@MainActor
final class FriendsStoreTests: XCTestCase {
    private func makeStore() -> FriendsStore {
        let defaults = UserDefaults(suiteName: "carxplore-tests-\(UUID().uuidString)")!
        return FriendsStore(service: MockFriendsService(defaults: defaults), isDemo: true)
    }

    func testLoadsProfileWithFriendCode() async {
        let store = makeStore()
        await store.loadProfile()
        XCTAssertEqual(store.myCode.count, 6)
    }

    func testAddAndRemoveFriend() async {
        let store = makeStore()
        await store.refresh()
        let before = store.friends.count

        let added = await store.add(code: "abc234")
        XCTAssertTrue(added)
        XCTAssertEqual(store.friends.count, before + 1)

        await store.remove(store.friends.last!)
        XCTAssertEqual(store.friends.count, before)
    }

    func testCannotAddOwnCode() async {
        let store = makeStore()
        await store.loadProfile()
        let added = await store.add(code: store.myCode)
        XCTAssertFalse(added)
        XCTAssertNotNil(store.errorMessage)
    }

    func testUpdateProfile() async {
        let store = makeStore()
        await store.loadProfile()
        await store.updateProfile(displayName: "Anna", car: "Golf", shareLocation: false)
        XCTAssertEqual(store.me?.displayName, "Anna")
        XCTAssertEqual(store.me?.shareLocation, false)
    }
}
