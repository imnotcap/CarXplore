import CoreLocation
import SwiftUI
import UIKit

/// Fanen "Profil": dig, dine venner, vennekode, tilladelser.
struct ProfileView: View {
    @EnvironmentObject private var game: GameStore
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var friends: FriendsStore

    @State private var displayName = ""
    @State private var car = ""
    @State private var shareLocation = true
    @State private var codeInput = ""
    @State private var confirmReset = false
    @State private var friendToRemove: Friend?

    private var profileChanged: Bool {
        guard let me = friends.me else { return false }
        return displayName != me.displayName || car != me.car || shareLocation != me.shareLocation
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AppHeader(initials: Theme.initials(friends.me?.displayName ?? "Mig"))
                ScreenTitle(text: "Profil")

                profileCard
                friendsCard
                permissionsCard

                Button(role: .destructive) {
                    confirmReset = true
                } label: {
                    Text("Nulstil fremskridt")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .glassCard(cornerRadius: 14)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(ScreenBackground())
        .onAppear(perform: loadProfileFields)
        .onChange(of: friends.me) { loadProfileFields() }
        .confirmationDialog("Vil du slette alt dit fremskridt?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Slet alt", role: .destructive) { game.reset() }
        }
        .confirmationDialog(
            "Fjern \(friendToRemove?.name ?? "ven")?",
            isPresented: Binding(get: { friendToRemove != nil }, set: { if !$0 { friendToRemove = nil } }),
            titleVisibility: .visible
        ) {
            Button("Fjern ven", role: .destructive) {
                if let friend = friendToRemove {
                    Task { await friends.remove(friend) }
                }
            }
        }
        .alert("Fejl", isPresented: Binding(
            get: { friends.errorMessage != nil },
            set: { if !$0 { friends.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(friends.errorMessage ?? "")
        }
    }

    // MARK: Kort

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                AvatarView(initials: Theme.initials(displayName.isEmpty ? "Mig" : displayName), size: 60)
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName.isEmpty ? "Ny kører" : displayName).font(.title3.bold())
                    Text("Niveau \(game.level.number) · \(game.level.title)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            field("Dit navn", text: $displayName)
            field("Din bil, fx VW Golf", text: $car)

            Toggle("Del min position med venner", isOn: $shareLocation)
                .tint(Theme.mint)

            Text("Venner kan altid se dit navn, din bil og dine point. Din position deles kun under en tur, og kun hvis det er slået til.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)

            if profileChanged {
                Button {
                    Task {
                        await friends.updateProfile(displayName: displayName, car: car, shareLocation: shareLocation)
                    }
                } label: {
                    Text("Gem profil")
                        .font(.headline)
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Theme.actionGradient, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .glassCard()
    }

    private var friendsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("VENNER").font(.system(size: 18, weight: .heavy).italic())

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Din vennekode").font(.caption).foregroundStyle(Theme.secondaryText)
                    Text(friends.myCode)
                        .font(.system(size: 24, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Theme.cyan)
                }
                Spacer()
                ShareLink(item: "Kør om kap med mig på CarXplore! Min vennekode er \(friends.myCode)") {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.1), in: Circle())
                }
                .accessibilityLabel("Del din vennekode")
            }

            HStack(spacing: 10) {
                field("Vens kode, fx K7PQ2M", text: $codeInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button {
                    let code = codeInput
                    Task { if await friends.add(code: code) { codeInput = "" } }
                } label: {
                    Text("Tilføj")
                        .font(.headline)
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .background(Theme.unlockedBadge, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(codeInput.trimmingCharacters(in: .whitespaces).count != 6)
                .opacity(codeInput.trimmingCharacters(in: .whitespaces).count != 6 ? 0.5 : 1)
            }

            if friends.friends.isEmpty {
                Text("Ingen venner endnu. Del din kode!")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                ForEach(friends.friends) { friend in
                    HStack(spacing: 12) {
                        AvatarView(initials: friend.initials, size: 38,
                                   ring: friend.isDriving ? Theme.mint : .white.opacity(0.4))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(friend.name).font(.subheadline.weight(.semibold))
                            Text(friend.isDriving ? "Kører nu" : "I skyen")
                                .font(.caption)
                                .foregroundStyle(friend.isDriving ? Theme.mint : Theme.secondaryText)
                        }
                        Spacer()
                        Button {
                            friendToRemove = friend
                        } label: {
                            Image(systemName: "person.badge.minus")
                                .foregroundStyle(Theme.secondaryText)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Fjern \(friend.name)")
                    }
                }
            }

            if friends.isDemo {
                Text("Demo-tilstand: vennerne er testdata, fordi appen ikke er forbundet til en server.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(16)
        .glassCard()
    }

    private var permissionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Lokation")
                Spacer()
                Text(authorizationText).foregroundStyle(Theme.secondaryText)
            }
            if location.authorization == .authorizedWhenInUse {
                Button("Tillad 'Altid' for kørsel i baggrunden") { location.requestAlways() }
                    .foregroundStyle(Theme.cyan)
            }
            if location.authorization == .denied || location.authorization == .restricted {
                Button("Åbn Indstillinger") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .foregroundStyle(Theme.cyan)
            }
            Text("Tågen forsvinder kun, mens en tur er startet. Med 'Altid' fortsætter appen, selvom skærmen slukkes.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(16)
        .glassCard()
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundStyle(Theme.secondaryText))
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.12)))
    }

    private func loadProfileFields() {
        guard let me = friends.me else { return }
        displayName = me.displayName
        car = me.car
        shareLocation = me.shareLocation
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
