import MapKit
import SwiftUI

// MARK: - Annotationer og overlays

final class LandmarkAnnotation: NSObject, MKAnnotation {
    let landmark: Landmark
    let isUnlocked: Bool
    var coordinate: CLLocationCoordinate2D { landmark.coordinate }
    var title: String? { isUnlocked ? landmark.name : "???" }
    var subtitle: String? { isUnlocked ? landmark.city : "Kør herhen for at låse op" }

    init(landmark: Landmark, isUnlocked: Bool) {
        self.landmark = landmark
        self.isUnlocked = isUnlocked
    }
}

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
        case focus(latitude: Double, longitude: Double)
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

// MARK: - Kortet

/// MKMapView med sky-tåge, neonrute, seværdigheder og venner.
/// (SwiftUI's `Map` kan endnu ikke tegne et brugerdefineret overlay som tågen.)
struct ExploreMapView: UIViewRepresentable {
    let explored: Set<CellID>
    let revision: Int
    let landmarks: [Landmark]
    let unlocked: Set<String>
    let friends: [Friend]
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
        map.register(MKMarkerAnnotationView.self,
                     forAnnotationViewWithReuseIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier)
        map.register(CarAnnotationView.self, forAnnotationViewWithReuseIdentifier: CarAnnotationView.reuseID)
        map.register(FriendAnnotationView.self, forAnnotationViewWithReuseIdentifier: FriendAnnotationView.reuseID)
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
        coordinator.syncAnnotations(on: map, landmarks: landmarks, unlocked: unlocked, friends: friends)

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
            case let .focus(latitude, longitude):
                map.setUserTrackingMode(.none, animated: false)
                map.setRegion(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)), animated: true)
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

        func syncAnnotations(on map: MKMapView, landmarks: [Landmark], unlocked: Set<String>, friends: [Friend]) {
            var hasher = Hasher()
            hasher.combine(landmarks.map(\.id))
            hasher.combine(unlocked)
            hasher.combine(friends)
            let signature = hasher.finalize()
            guard signature != annotationSignature else { return }
            annotationSignature = signature

            map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })
            map.addAnnotations(landmarks.map { LandmarkAnnotation(landmark: $0, isUnlocked: unlocked.contains($0.id)) })
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
            case let a as LandmarkAnnotation:
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier, for: annotation)
                guard let marker = view as? MKMarkerAnnotationView else { return view }
                marker.canShowCallout = true
                marker.glyphImage = UIImage(systemName: a.isUnlocked ? "trophy.fill" : "lock.fill")
                marker.markerTintColor = a.isUnlocked ? UIColor(a.landmark.rarity.color) : UIColor(white: 0.35, alpha: 1)
                marker.displayPriority = .required
                return marker
            default:
                return nil
            }
        }
    }
}
