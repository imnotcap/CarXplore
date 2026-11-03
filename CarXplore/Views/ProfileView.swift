import CoreLocation
import SwiftUI
import UIKit

struct ProfileView: View {
    @EnvironmentObject private var game: GameStore
    @EnvironmentObject private var location: LocationService
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            List {
                Section("Statistik") {
                    LabeledContent("Udforsket areal",
                                   value: "\(game.exploredAreaKm2.formatted(.number.precision(.fractionLength(2)))) km²")
                    LabeledContent("Udforskede felter", value: "\(game.explored.count)")
                    LabeledContent("Trofæer", value: "\(game.unlocked.count) af \(game.landmarks.count)")
                    LabeledContent("Point i alt", value: "\(game.score)")
                }

                Section {
                    LabeledContent("Lokation", value: authorizationText)
                    if location.authorization == .authorizedWhenInUse {
                        Button("Tillad 'Altid' for kørsel i baggrunden") { location.requestAlways() }
                    }
                    if location.authorization == .denied || location.authorization == .restricted {
                        Button("Åbn Indstillinger") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                } header: {
                    Text("Tilladelser")
                } footer: {
                    Text("Tågen forsvinder kun, mens en tur er startet. Med 'Altid' fortsætter appen, selvom skærmen slukkes.")
                }

                Section {
                    Button("Nulstil fremskridt", role: .destructive) { confirmReset = true }
                }
            }
            .navigationTitle("Profil")
            .confirmationDialog("Vil du slette alt dit fremskridt?", isPresented: $confirmReset,
                                titleVisibility: .visible) {
                Button("Slet alt", role: .destructive) { game.reset() }
            }
        }
    }

    private var authorizationText: String {
        switch location.authorization {
        case .authorizedAlways: "Altid"
        case .authorizedWhenInUse: "Når appen bruges"
        case .denied: "Afvist"
        case .restricted: "Begrænset"
        case .notDetermined: "Ikke spurgt endnu"
        @unknown default: "Ukendt"
        }
    }
}
