import CoreLocation
import SwiftUI

struct MapScreen: View {
    @EnvironmentObject private var game: GameStore
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var friends: FriendsStore
    @State private var followUser = true
    @State private var heading = 0.0
    @State private var command: MapCommand?
    @State private var search = ""
    @FocusState private var searchFocused: Bool

    /// Et søgeresultat: en ven eller en seværdighed.
    private struct SearchResult: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let initials: String?
        let symbol: String
        let ring: Color
        let coordinate: CLLocationCoordinate2D?
    }

    private var searchResults: [SearchResult] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        let friendHits = friends.friends.filter { $0.name.localizedCaseInsensitiveContains(query) }.map { f in
            SearchResult(id: f.id.uuidString, title: f.name,
                         subtitle: f.coordinate == nil ? "Position skjult" : f.isDriving ? "Kører nu" : "I skyen",
                         initials: f.initials, symbol: "location.fill",
                         ring: f.isDriving ? Theme.mint : .white.opacity(0.5), coordinate: f.coordinate)
        }
        let landmarkHits = game.landmarks.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.city.localizedCaseInsensitiveContains(query)
        }.map { l in
            let isUnlocked = game.unlocked[l.id] != nil
            return SearchResult(id: l.id, title: l.name,
                                subtitle: "\(l.city) · \(isUnlocked ? "Låst op" : "+\(l.rarity.points.formatted()) XP")",
                                initials: nil, symbol: isUnlocked ? "trophy.fill" : "lock.fill",
                                ring: isUnlocked ? Theme.gold : .white.opacity(0.4), coordinate: l.coordinate)
        }
        return Array((friendHits + landmarkHits).prefix(5))
    }

    private var activeCaption: String {
        let driving = friends.friends.filter(\.isDriving).count
        return "\(friends.friends.count) venner · \(driving) kører nu"
    }

    var body: some View {
        ZStack {
            ExploreMapView(
                explored: game.explored,
                revision: game.revision,
                landmarks: game.landmarks,
                unlocked: Set(game.unlocked.keys),
                friends: friends.friends,
                recentUnlockID: game.recentUnlock?.id,
                tripPath: game.tripPath,
                command: command,
                followUser: $followUser,
                heading: $heading
            )
            .ignoresSafeArea()

            // Mørke toninger foroven og forneden, så teksten kan læses over kortet.
            VStack(spacing: 0) {
                LinearGradient(colors: [Theme.background.opacity(0.92), Theme.background.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 280)
                Spacer()
                LinearGradient(colors: [Theme.background.opacity(0), Theme.background.opacity(0.85)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 220)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 10) {
                AppHeader(initials: Theme.initials(friends.me?.displayName ?? "Mig"))

                Text("KØR FOR AT LÅSE VERDEN OP")
                    .font(.system(size: 15, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.92))

                levelChip
                searchBar

                if searchResults.isEmpty {
                    Text(activeCaption)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    results
                }

                Spacer()

                HStack {
                    Spacer()
                    mapControls
                }

                if let landmark = game.recentUnlock {
                    TrophyUnlockedCard(landmark: landmark) {
                        game.recentUnlock = nil
                        followUser = true
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    TripCard(
                        percent: game.localAreaPercent,
                        km: game.totalKm,
                        isTracking: location.isTracking,
                        toggle: toggleTrip
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .animation(.spring(duration: 0.4), value: game.recentUnlock)
        .onChange(of: game.recentUnlock?.id) {
            // Flyv hen til seværdigheden, så man ser den ryddede cirkel.
            if let landmark = game.recentUnlock {
                command = MapCommand(kind: .focus(latitude: landmark.latitude, longitude: landmark.longitude,
                                                  span: landmark.unlockRadius / 25_000))
            }
        }
        .onAppear {
            if location.authorization == .notDetermined { location.requestWhenInUse() }
        }
    }

    private func toggleTrip() {
        if location.isTracking {
            location.stopTrip()
            game.endTrip()
        } else {
            game.beginTrip()
            location.startTrip()
            followUser = true
        }
    }

    // MARK: Dele

    private var levelChip: some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.mint).frame(width: 7, height: 7)
            Text("Niveau \(game.level.number)")
            Text("•").foregroundStyle(Theme.secondaryText)
            Text(game.level.title)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassCard(cornerRadius: 14)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.secondaryText)
            TextField("", text: $search, prompt: Text("Søg på kortet…").foregroundStyle(Theme.secondaryText))
                .focused($searchFocused)
                .foregroundStyle(.white)
                .submitLabel(.search)
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.secondaryText)
                }
                .accessibilityLabel("Ryd søgning")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .glassCard(cornerRadius: 14)
    }

    private var results: some View {
        VStack(spacing: 0) {
            ForEach(searchResults) { result in
                Button {
                    if let c = result.coordinate {
                        command = MapCommand(kind: .focus(latitude: c.latitude, longitude: c.longitude))
                    }
                    search = ""
                    searchFocused = false
                } label: {
                    HStack(spacing: 12) {
                        if let initials = result.initials {
                            AvatarView(initials: initials, size: 34, ring: result.ring)
                        } else {
                            Image(systemName: result.symbol)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(Color.white.opacity(0.1), in: Circle())
                                .overlay(Circle().strokeBorder(result.ring, lineWidth: 2))
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(result.title).font(.subheadline.weight(.semibold))
                            Text(result.subtitle)
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        Image(systemName: "location.fill")
                            .foregroundStyle(Theme.cyan)
                            .opacity(result.coordinate == nil ? 0.3 : 1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(result.coordinate == nil)
            }
        }
        .glassCard(cornerRadius: 14)
    }

    private var mapControls: some View {
        VStack(spacing: 10) {
            Button {
                command = MapCommand(kind: .resetHeading)
            } label: {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.danger)
                    .rotationEffect(.degrees(-heading))
                    .frame(width: 46, height: 46)
            }
            .glassCard(cornerRadius: 12)
            .accessibilityLabel("Drej kortet mod nord")

            VStack(spacing: 0) {
                Button {
                    command = MapCommand(kind: .zoomIn)
                } label: {
                    Image(systemName: "plus").frame(width: 46, height: 46)
                }
                .accessibilityLabel("Zoom ind")
                Divider().frame(width: 30).overlay(Color.white.opacity(0.2))
                Button {
                    command = MapCommand(kind: .zoomOut)
                } label: {
                    Image(systemName: "minus").frame(width: 46, height: 46)
                }
                .accessibilityLabel("Zoom ud")
            }
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(.white)
            .glassCard(cornerRadius: 12)

            Button {
                followUser = true
            } label: {
                Image(systemName: followUser ? "location.fill" : "scope")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(followUser ? Theme.cyan : .white)
                    .frame(width: 46, height: 46)
            }
            .glassCard(cornerRadius: 12)
            .accessibilityLabel("Følg min position")
        }
    }
}

/// Bundkortet med fremskridt og Start/Stop-knappen.
private struct TripCard: View {
    let percent: Double
    let km: Double
    let isTracking: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Oplåst: \(percent.formatted(.number.precision(.fractionLength(1)))) %")
                    .font(.headline)
                NeonProgressBar(value: percent / 100)
                HStack(spacing: 10) {
                    Image(systemName: "road.lanes")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("KM KØRT:")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.secondaryText)
                        Text("\(Int(km).formatted()) km")
                            .font(.headline)
                    }
                }
            }
            .foregroundStyle(.white)

            Button(action: toggle) {
                HStack(spacing: 10) {
                    Text(isTracking ? "STOP TUR" : "START TUR")
                        .font(.system(size: 18, weight: .heavy))
                    Image(systemName: isTracking ? "stop.fill" : "play.fill")
                        .font(.system(size: 18, weight: .bold))
                }
                .foregroundStyle(Color(red: 0.03, green: 0.08, blue: 0.12))
                .frame(maxWidth: .infinity, minHeight: 76)
                .background(isTracking ? Theme.stopGradient : Theme.actionGradient,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: (isTracking ? Theme.danger : Theme.cyan).opacity(0.5), radius: 12)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .glassCard(cornerRadius: 22)
    }
}

/// "TROFÆ LÅST OP!": vises når en seværdighed låses op, indtil man trykker Fortsæt.
private struct TrophyUnlockedCard: View {
    let landmark: Landmark
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "trophy.fill")
                Text("TROFÆ LÅST OP!")
            }
            .font(.system(size: 24, weight: .heavy))
            .foregroundStyle(Theme.gold)
            .shadow(color: Theme.gold.opacity(0.5), radius: 8)

            Text(landmark.name.uppercased())
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text("Du har låst \(landmark.name) op og ryddet tågen i en \(Int(landmark.unlockRadius))m radius!")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("+\(landmark.rarity.points.formatted()) XP")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(Theme.gold)

            Button(action: onContinue) {
                Text("FORTSÆT")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Color(red: 0.03, green: 0.08, blue: 0.12))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Theme.actionGradient, in: Capsule())
                    .shadow(color: Theme.cyan.opacity(0.5), radius: 12)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .glassCard(cornerRadius: 22, highlighted: true)
        .padding(.horizontal, 24)
    }
}
