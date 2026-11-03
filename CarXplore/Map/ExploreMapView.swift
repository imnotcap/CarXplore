import MapKit
import SwiftUI

// MARK: - Annotationer og overlays

final class LandmarkAnnotation: NSObject, MKAnnotation {
    let landmark: Landmark
    let isUnlocked: Bool
    /// Netop låst op. Vises med "250M RADIUS OPLÅST!".
    let isRecent: Bool
    var coordinate: CLLocationCoordinate2D { landmark.coordinate }
    var title: String? { isUnlocked ? landmark.name : "???" }
    var subtitle: String? { isUnlocked ? landmark.city : "Kør herhen for at låse op" }

    init(landmark: Landmark, isUnlocked: Bool, isRecent: Bool) {
        self.landmark = landmark
        self.isUnlocked = isUnlocked
        self.isRecent = isRecent
    }
}

/// Den lysende ring om en oplåst seværdighed (det ryddede område).
final class UnlockedAreaCircle: MKCircle {}

final class FriendAnnotation: NSObject, MKAnnotation {
    let friend: Friend
    let coordinate: CLLocationCoordinate2D
    var title: String? { friend.name }

    init(friend: Friend, coordinate: CLLocationCoordinate2D) {
        self.friend = friend
        self.coordinate = coordinate
    }
}

/// Turens rute. Tegnes to gange: en bred, svag glød og en skarp kerne.
final class RoutePolyline: MKPolyline {
    var isGlow = false
}

/// Kommandoer fra SwiftUI-knapperne til kortet (zoom, nord op, vis ven).
struct MapCommand: Equatable {
    enum Kind: Equatable {
        case zoomIn
        case zoomOut
        case resetHeading
        case focus(latitude: Double, longitude: Double, span: Double = 0.04)
    }

    let id = UUID()
    let kind: Kind
}

// MARK: - Annotation views

/// Bilen, der viser din egen position ("Mig").
final class CarAnnotationView: MKAnnotationView {
    static let reuseID = "car"

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 56, height: 72)
        backgroundColor = .clear

        let glow = UIView(frame: CGRect(x: 6, y: 0, width: 44, height: 44))
        glow.backgroundColor = UIColor(Theme.cyan).withAlphaComponent(0.22)
        glow.layer.cornerRadius = 22
        glow.layer.borderColor = UIColor(Theme.cyan).cgColor
        glow.layer.borderWidth = 2
        glow.layer.shadowColor = UIColor(Theme.cyan).cgColor
        glow.layer.shadowRadius = 10
        glow.layer.shadowOpacity = 0.9
        glow.layer.shadowOffset = .zero
        addSubview(glow)

        let car = UIImageView(image: UIImage(systemName: "car.fill"))
        car.tintColor = .white
        car.contentMode = .scaleAspectFit
        car.frame = CGRect(x: 10, y: 10, width: 24, height: 24)
        glow.addSubview(car)

        let label = UILabel(frame: CGRect(x: 0, y: 48, width: 56, height: 20))
        label.text = "Mig"
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowRadius = 3
        label.layer.shadowOpacity = 0.8
        label.layer.shadowOffset = .zero
        addSubview(label)

        centerOffset = CGPoint(x: 0, y: 14)
        displayPriority = .required
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) bruges ikke") }
}

/// En ven som rund avatar med navn og status.
final class FriendAnnotationView: MKAnnotationView {
    static let reuseID = "friend"

    private let avatar = UILabel()
    private let nameLabel = UILabel()
    private let statusLabel = UILabel()

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 96, height: 92)
        backgroundColor = .clear
        canShowCallout = false

        avatar.frame = CGRect(x: 25, y: 0, width: 46, height: 46)
        avatar.textAlignment = .center
        avatar.font = .systemFont(ofSize: 17, weight: .bold)
        avatar.textColor = .white
        avatar.backgroundColor = UIColor(Theme.blue)
        avatar.layer.cornerRadius = 23
        avatar.layer.masksToBounds = true
        avatar.layer.borderWidth = 2.5
        addSubview(avatar)

        for (label, y, size, weight) in [(nameLabel, 50.0, 15.0, UIFont.Weight.semibold),
                                         (statusLabel, 69.0, 12.0, UIFont.Weight.regular)] {
            label.frame = CGRect(x: 0, y: y, width: 96, height: 18)
            label.textAlignment = .center
            label.font = .systemFont(ofSize: size, weight: weight)
            label.textColor = .white
            label.layer.shadowColor = UIColor.black.cgColor
            label.layer.shadowRadius = 3
            label.layer.shadowOpacity = 0.9
            label.layer.shadowOffset = .zero
            addSubview(label)
        }
        statusLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        centerOffset = CGPoint(x: 0, y: 23)
        displayPriority = .defaultHigh
        configure()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) bruges ikke") }

    override var annotation: (any MKAnnotation)? {
        didSet { configure() }
    }

    private func configure() {
        guard let friend = (annotation as? FriendAnnotation)?.friend else { return }
        avatar.text = friend.initials
        avatar.layer.borderColor = UIColor(friend.isDriving ? Theme.mint : Color.white.opacity(0.6)).cgColor
        nameLabel.text = friend.name.split(separator: " ").first.map(String.init) ?? friend.name
        statusLabel.text = friend.isDriving ? "(Kører nu)" : "(I skyen)"
    }
}

/// Seværdighed: guldtrofæ når den er låst op, grå lås ellers.
final class LandmarkAnnotationView: MKAnnotationView {
    static let reuseID = "landmark"

    private let badge = UIView()
    private let icon = UIImageView()
    private let nameLabel = UILabel()

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 170, height: 84)
        backgroundColor = .clear
        canShowCallout = true

        badge.layer.borderWidth = 2
        badge.layer.shadowOffset = .zero
        addSubview(badge)
        icon.contentMode = .scaleAspectFit
        icon.tintColor = .white
        badge.addSubview(icon)

        nameLabel.frame = CGRect(x: 0, y: 56, width: 170, height: 22)
        nameLabel.textAlignment = .center
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.minimumScaleFactor = 0.7
        nameLabel.layer.shadowColor = UIColor.black.cgColor
        nameLabel.layer.shadowRadius = 3
        nameLabel.layer.shadowOpacity = 0.9
        nameLabel.layer.shadowOffset = .zero
        addSubview(nameLabel)

        // Badgets centrum (y = 25) ligger præcis på koordinaten.
        centerOffset = CGPoint(x: 0, y: 17)
        displayPriority = .required
        configure()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) bruges ikke") }

    override var annotation: (any MKAnnotation)? {
        didSet { configure() }
    }

    private func configure() {
        guard let a = annotation as? LandmarkAnnotation else { return }
        if a.isUnlocked {
            badge.frame = CGRect(x: 60, y: 0, width: 50, height: 50)
            badge.backgroundColor = UIColor(Theme.gold)
            badge.layer.borderColor = UIColor.white.withAlphaComponent(0.85).cgColor
            badge.layer.shadowColor = UIColor(Theme.gold).cgColor
            badge.layer.shadowRadius = 14
            badge.layer.shadowOpacity = 0.95
            icon.image = UIImage(systemName: "trophy.fill")
            icon.frame = CGRect(x: 12, y: 12, width: 26, height: 26)
            nameLabel.isHidden = false
            if a.isRecent {
                nameLabel.text = "\(Int(a.landmark.unlockRadius))M RADIUS OPLÅST!"
                nameLabel.font = .systemFont(ofSize: 14, weight: .heavy)
                nameLabel.textColor = UIColor(Theme.cyan)
            } else {
                nameLabel.text = a.landmark.name
                nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
                nameLabel.textColor = .white
            }
        } else {
            badge.frame = CGRect(x: 68, y: 8, width: 34, height: 34)
            badge.backgroundColor = UIColor(white: 0.32, alpha: 1)
            badge.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
            badge.layer.shadowOpacity = 0
            icon.image = UIImage(systemName: "lock.fill")
            icon.frame = CGRect(x: 9, y: 9, width: 16, height: 16)
            nameLabel.isHidden = true
        }
        badge.layer.cornerRadius = badge.frame.width / 2
    }
}

// MARK: - Kortet

/// MKMapView med sky-tåge, neonrute, seværdigheder og venner.
/// (SwiftUI's `Map` kan endnu ikke tegne et brugerdefineret overlay som tågen.)
struct ExploreMapView: UIViewRepresentable {
    let explored: Set<CellID>
    let revision: Int
    let landmarks: [Landmark]
    let unlocked: Set<String>
    let friends: [Friend]
    let recentUnlockID: String?
    let tripPath: [CLLocationCoordinate2D]
    let command: MapCommand?
    @Binding var followUser: Bool
    @Binding var heading: Double

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = .dark
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = configuration
        map.showsUserLocation = true
        map.showsCompass = false
        map.register(CarAnnotationView.self, forAnnotationViewWithReuseIdentifier: CarAnnotationView.reuseID)
        map.register(FriendAnnotationView.self, forAnnotationViewWithReuseIdentifier: FriendAnnotationView.reuseID)
        map.register(LandmarkAnnotationView.self, forAnnotationViewWithReuseIdentifier: LandmarkAnnotationView.reuseID)
        // Start over Danmark, indtil vi kender brugerens position.
        map.setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 55.9, longitude: 10.9),
            span: MKCoordinateSpan(latitudeDelta: 4, longitudeDelta: 5)), animated: false)
        map.addOverlay(FogOverlay(), level: .aboveLabels)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onFollowChanged = { follow in
            DispatchQueue.main.async { followUser = follow }
        }
        coordinator.onHeadingChanged = { value in
            DispatchQueue.main.async { heading = value }
        }

        if coordinator.renderedRevision != revision {
            coordinator.renderedRevision = revision
            coordinator.cells = explored
            coordinator.fogRenderer?.update(cells: explored)
        }

        coordinator.syncRoute(on: map, path: tripPath)
        coordinator.syncAnnotations(on: map, landmarks: landmarks, unlocked: unlocked,
                                    recentUnlockID: recentUnlockID, friends: friends)

        if let command, command.id != coordinator.lastCommandID {
            coordinator.lastCommandID = command.id
            coordinator.perform(command, on: map)
        }

        if followUser, map.userTrackingMode == .none {
            map.setUserTrackingMode(.follow, animated: true)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var fogRenderer: FogRenderer?
        var cells: Set<CellID> = []
        var renderedRevision = -1
        var lastCommandID: UUID?
        var onFollowChanged: ((Bool) -> Void)?
        var onHeadingChanged: ((Double) -> Void)?
        private var annotationSignature: Int?
        private var routeCount = -1
        private var routeOverlays: [RoutePolyline] = []
        private var areaOverlays: [UnlockedAreaCircle] = []
        private var lastReportedHeading = 0.0

        func perform(_ command: MapCommand, on map: MKMapView) {
            let camera = map.camera.copy() as! MKMapCamera
            switch command.kind {
            case .zoomIn:
                camera.centerCoordinateDistance = max(150, camera.centerCoordinateDistance / 2)
                map.setCamera(camera, animated: true)
            case .zoomOut:
                camera.centerCoordinateDistance = min(20_000_000, camera.centerCoordinateDistance * 2)
                map.setCamera(camera, animated: true)
            case .resetHeading:
                camera.heading = 0
                map.setCamera(camera, animated: true)
            case let .focus(latitude, longitude, span):
                map.setUserTrackingMode(.none, animated: false)
                map.setRegion(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                    span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)), animated: true)
            }
        }

        func syncRoute(on map: MKMapView, path: [CLLocationCoordinate2D]) {
            guard path.count != routeCount else { return }
            routeCount = path.count
            map.removeOverlays(routeOverlays)
            routeOverlays = []
            guard path.count > 1 else { return }
            for isGlow in [true, false] {
                let line = RoutePolyline(coordinates: path, count: path.count)
                line.isGlow = isGlow
                routeOverlays.append(line)
            }
            map.addOverlays(routeOverlays, level: .aboveLabels)
        }

        func syncAnnotations(on map: MKMapView, landmarks: [Landmark], unlocked: Set<String>,
                             recentUnlockID: String?, friends: [Friend]) {
            var hasher = Hasher()
            hasher.combine(landmarks.map(\.id))
            hasher.combine(unlocked)
            hasher.combine(recentUnlockID)
            hasher.combine(friends)
            let signature = hasher.finalize()
            guard signature != annotationSignature else { return }
            annotationSignature = signature

            map.removeOverlays(areaOverlays)
            areaOverlays = landmarks.filter { unlocked.contains($0.id) }.map {
                UnlockedAreaCircle(center: $0.coordinate, radius: $0.unlockRadius)
            }
            map.addOverlays(areaOverlays, level: .aboveLabels)

            map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })
            map.addAnnotations(landmarks.map {
                LandmarkAnnotation(landmark: $0, isUnlocked: unlocked.contains($0.id),
                                   isRecent: $0.id == recentUnlockID)
            })
            map.addAnnotations(friends.compactMap { friend in
                friend.coordinate.map { FriendAnnotation(friend: friend, coordinate: $0) }
            })
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            if overlay is FogOverlay {
                let renderer = FogRenderer(overlay: overlay)
                renderer.update(cells: cells)
                fogRenderer = renderer
                return renderer
            }
            if let circle = overlay as? UnlockedAreaCircle {
                let renderer = MKCircleRenderer(circle: circle)
                renderer.fillColor = UIColor(Theme.cyan).withAlphaComponent(0.14)
                renderer.strokeColor = UIColor(Theme.cyan).withAlphaComponent(0.9)
                renderer.lineWidth = 3
                return renderer
            }
            if let route = overlay as? RoutePolyline {
                let renderer = MKPolylineRenderer(polyline: route)
                renderer.lineCap = .round
                renderer.lineJoin = .round
                if route.isGlow {
                    renderer.strokeColor = UIColor(Theme.cyan).withAlphaComponent(0.28)
                    renderer.lineWidth = 16
                } else {
                    renderer.strokeColor = UIColor(red: 0.55, green: 0.92, blue: 1, alpha: 1)
                    renderer.lineWidth = 5
                }
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool) {
            onFollowChanged?(mode != .none)
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            let heading = mapView.camera.heading
            if abs(heading - lastReportedHeading) > 2 {
                lastReportedHeading = heading
                onHeadingChanged?(heading)
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            switch annotation {
            case is MKUserLocation:
                return mapView.dequeueReusableAnnotationView(withIdentifier: CarAnnotationView.reuseID, for: annotation)
            case is FriendAnnotation:
                return mapView.dequeueReusableAnnotationView(withIdentifier: FriendAnnotationView.reuseID, for: annotation)
            case is LandmarkAnnotation:
                return mapView.dequeueReusableAnnotationView(withIdentifier: LandmarkAnnotationView.reuseID, for: annotation)
            default:
                return nil
            }
        }
    }
}
