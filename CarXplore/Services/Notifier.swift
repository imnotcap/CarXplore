import UserNotifications

/// Lokale notifikationer, fx når et trofæ låses op, mens appen er i baggrunden.
enum Notifier {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func trophyUnlocked(_ landmark: Landmark) {
        let content = UNMutableNotificationContent()
        content.title = "Nyt trofæ! 🏆"
        content.body = "Du har låst \(landmark.name) op (+\(landmark.rarity.points) point)"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "trophy-\(landmark.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
