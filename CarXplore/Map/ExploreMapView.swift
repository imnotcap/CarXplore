import MapKit
import SwiftUI

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
    var subtitle: String? { friend.isDriving ? "Kører nu · \(friend.car)" : friend.car }

    init(friend: Friend, coordinate: CLLocationCoordinate2D) {
        self.friend = friend
        self.coordinate = coordinate
    }
}

/// MKMapView med tåge-overlay, seværdigheder og venner.
/// (SwiftUI's `Map` kan endnu ikke tegne et brugerdefineret overlay som tågen.)
struct ExploreMapView: UIViewRepresentable {
    let explored: Set<CellID>
    let revision: Int
    let landmarks: [Landmark]
    let unlocked: Set<String>
    let friends: [Friend]
    @Binding var followUser: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = true
        map.pointOfInterestFilter = .excludingAll
        map.register(MKMarkerAnnotationView.self,
                     forAnnotationViewWithReuseIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier)
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

        if coordinator.renderedRevision != revision {
            coordinator.renderedRevision = revision
            coordinator.cells = explored
            coordinator.fogRenderer?.update(cells: explored)
        }

        coordinator.syncAnnotations(on: map, landmarks: landmarks, unlocked: unlocked, friends: friends)

        if followUser, map.userTrackingMode == .none {
            map.setUserTrackingMode(.followWithHeading, animated: true)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var fogRenderer: FogRenderer?
        var cells: Set<CellID> = []
        var renderedRevision = -1
        var onFollowChanged: ((Bool) -> Void)?
        private var annotationSignature: Int?

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            if overlay is FogOverlay {
                let renderer = FogRenderer(overlay: overlay)
                renderer.update(cells: cells)
                fogRenderer = renderer
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool) {
            onFollowChanged?(mode != .none)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier, for: annotation)
            guard let marker = view as? MKMarkerAnnotationView else { return view }
            marker.canShowCallout = true
            marker.glyphText = nil
            marker.glyphImage = nil

            switch annotation {
            case let a as LandmarkAnnotation:
                marker.glyphImage = UIImage(systemName: a.isUnlocked ? "trophy.fill" : "lock.fill")
                marker.markerTintColor = a.isUnlocked ? UIColor(a.landmark.rarity.color) : .systemGray
                marker.displayPriority = .required
            case let a as FriendAnnotation:
                marker.glyphText = a.friend.initials
                marker.markerTintColor = a.friend.isDriving ? .systemGreen : .systemTeal
                marker.displayPriority = .defaultHigh
            default:
                break
            }
            return marker
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
    }
}
