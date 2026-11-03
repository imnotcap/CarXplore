import MapKit
import SwiftUI

/// Fanen "Fremskridt": trofæer (mål + seværdigheder) og ranglisten mod venner.
struct ProgressScreen: View {
    @EnvironmentObject private var game: GameStore
    @EnvironmentObject private var friends: FriendsStore
    @EnvironmentObject private var location: LocationService

    enum Section: String, CaseIterable { case trophies = "Trofæer", leaderboard = "Rangliste" }
    enum Filter: String, CaseIterable { case all = "Alle", unlocked = "Oplåste", locked = "Låste" }

    @State private var section: Section = .trophies
    @State private var filter: Filter = .all

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    private var achievements: [Achievement] {
        game.achievements(friendCount: friends.friends.count)
    }

    private var unlockedCount: Int {
        achievements.filter(\.isUnlocked).count + game.unlocked.count
    }

    private var totalCount: Int {
        achievements.count + game.landmarks.count
    }

    private func passes(_ unlocked: Bool) -> Bool {
        switch filter {
        case .all: true
        case .unlocked: unlocked
        case .locked: !unlocked
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AppHeader(initials: Theme.initials(friends.me?.displayName ?? "Mig"))

                    HStack(spacing: 8) {
                        ForEach(Section.allCases, id: \.self) { s in
                            ChipButton(title: s.rawValue, isSelected: section == s) { section = s }
                        }
                    }

                    switch section {
                    case .trophies: trophies
                    case .leaderboard: LeaderboardView()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(ScreenBackground())
            .navigationDestination(for: Friend.self) { FriendDetailView(friend: $0) }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    @ViewBuilder
    private var trophies: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScreenTitle(text: "Trofæer")
            Text("\(unlockedCount) ud af \(totalCount) oplåst")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            NeonProgressBar(value: Double(unlockedCount) / Double(max(totalCount, 1)), height: 6,
                            gradient: Theme.logoGradient)
        }

        HStack(spacing: 8) {
            ForEach(Filter.allCases, id: \.self) { f in
                ChipButton(title: f.rawValue, isSelected: filter == f) { filter = f }
            }
        }
        .frame(maxWidth: .infinity)

        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(achievements.filter { passes($0.isUnlocked) }) { a in
                TrophyCard(title: a.title, detail: a.detail, symbol: a.symbol, isUnlocked: a.isUnlocked,
                           progress: a.isUnlocked ? nil : (fraction: a.fraction, text: a.progressText),
                           accent: Theme.cyan)
            }
        }

        Text("SEVÆRDIGHEDER")
            .font(.system(size: 20, weight: .heavy).italic())
            .foregroundStyle(.white)
            .padding(.top, 8)

        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(game.landmarks.filter { passes(game.unlocked[$0.id] != nil) }) { landmark in
                let isUnlocked = game.unlocked[landmark.id] != nil
                TrophyCard(
                    title: landmark.name,
                    detail: isUnlocked ? "\(landmark.city) · +\(landmark.rarity.points.formatted()) XP"
                                       : "\(landmark.rarity.title) · \(distanceText(to: landmark))",
                    symbol: landmark.symbol,
                    isUnlocked: isUnlocked,
                    progress: nil,
                    accent: landmark.rarity.color
                )
            }
        }
    }

    private func distanceText(to landmark: Landmark) -> String {
        guard let here = location.lastLocation?.coordinate else { return landmark.city }
        let km = Geo.distance(here, landmark.coordinate) / 1000
        return "\(km.formatted(.number.precision(.fractionLength(0)))) km væk"
    }
}

/// Et kort i trofæ-gitteret: glødende ikon, titel, beskrivelse og evt. fremskridt.
struct TrophyCard: View {
    let title: String
    let detail: String
    let symbol: String
    let isUnlocked: Bool
    let progress: (fraction: Double, text: String)?
    let accent: Color

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(isUnlocked ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(Theme.lockedBadge))
                    .overlay(Circle().strokeBorder(.white.opacity(isUnlocked ? 0.6 : 0.2), lineWidth: 2))
                    .shadow(color: isUnlocked ? accent.opacity(0.6) : .clear, radius: 14)
                Image(systemName: symbol)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white.opacity(isUnlocked ? 1 : 0.55))
            }
            .frame(width: 78, height: 78)
            .padding(.top, 6)

            Text(title.uppercased())
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            if isUnlocked {
                Label(detail, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            } else {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
            }

            if let progress {
                VStack(spacing: 3) {
                    NeonProgressBar(value: progress.fraction, height: 4, gradient: Theme.logoGradient)
                    Text(progress.text)
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.horizontal, 6)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .top)
        .padding(12)
        .glassCard(cornerRadius: 18, highlighted: isUnlocked)
        .overlay(alignment: .topTrailing) {
            if !isUnlocked {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(10)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(isUnlocked ? "oplåst" : "låst"), \(detail)")
    }
}

/// Ranglisten: mig og mine venner sorteret efter XP.
struct LeaderboardView: View {
    @EnvironmentObject private var game: GameStore
    @EnvironmentObject private var friends: FriendsStore

    private struct Entry: Identifiable {
        let id: String
        let name: String
        let initials: String
        let detail: String
        let score: Int
        let friend: Friend?
    }

    private var entries: [Entry] {
        let myName = friends.me?.displayName ?? "Dig"
        let me = Entry(
            id: "me", name: "\(myName) (dig)", initials: Theme.initials(myName),
            detail: "Niveau \(game.level.number) · \(game.exploredAreaKm2.formatted(.number.precision(.fractionLength(1)))) km²",
            score: game.score, friend: nil)
        let others = friends.friends.map { f in
            Entry(id: f.id.uuidString, name: f.name, initials: f.initials,
                  detail: "Niveau \(Level(score: f.score).number) · \(f.exploredKm2.formatted(.number.precision(.fractionLength(1)))) km²",
                  score: f.score, friend: f)
        }
        return ([me] + others).sorted { $0.score > $1.score }
    }

    private let medals: [Color] = [
        Color(red: 0.95, green: 0.76, blue: 0.29),
        Color(red: 0.78, green: 0.80, blue: 0.84),
        Color(red: 0.83, green: 0.60, blue: 0.42),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScreenTitle(text: "Rangliste")
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                if let friend = entry.friend {
                    NavigationLink(value: friend) { row(index: index, entry: entry) }
                        .buttonStyle(.plain)
                } else {
                    row(index: index, entry: entry)
                }
            }
        }
    }

    private func row(index: Int, entry: Entry) -> some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(index < 3 ? Color.black : .white)
                .frame(width: 30, height: 30)
                .background(index < 3 ? medals[index] : Color.white.opacity(0.12), in: Circle())
            AvatarView(initials: entry.initials, size: 40,
                       ring: entry.friend?.isDriving == true ? Theme.mint : .white.opacity(0.4))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.name).font(.headline)
                    if entry.friend?.isDriving == true {
                        Image(systemName: "car.fill").font(.caption).foregroundStyle(Theme.mint)
                    }
                }
                Text(entry.detail).font(.caption).foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Text("\(entry.score.formatted()) XP")
                .font(.headline.monospacedDigit())
            if entry.friend != nil {
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.secondaryText)
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .glassCard(cornerRadius: 16, highlighted: entry.friend == nil)
    }
}

struct FriendDetailView: View {
    let friend: Friend

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                AvatarView(initials: friend.initials, size: 84,
                           ring: friend.isDriving ? Theme.mint : .white.opacity(0.5))
                VStack(spacing: 4) {
                    Text(friend.name).font(.title2.bold())
                    Text("Niveau \(Level(score: friend.score).number) · \(Level(score: friend.score).title)")
                        .foregroundStyle(Theme.secondaryText)
                }

                if let coordinate = friend.coordinate {
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)))) {
                        Marker(friend.name, systemImage: friend.isDriving ? "car.fill" : "person.fill",
                               coordinate: coordinate)
                            .tint(Theme.cyan)
                    }
                    .mapStyle(.standard(emphasis: .muted))
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }

                VStack(spacing: 0) {
                    stat("Bil", friend.car.isEmpty ? "–" : friend.car)
                    stat("Status", friend.isDriving ? "Kører nu" : "I skyen")
                    if let lastSeen = friend.lastSeen {
                        stat("Sidst set", lastSeen.formatted(.relative(presentation: .named)))
                    }
                    stat("Udforsket", "\(friend.exploredKm2.formatted(.number.precision(.fractionLength(1)))) km²")
                    stat("Trofæer", "\(friend.trophies)")
                    stat("XP", friend.score.formatted())
                }
                .glassCard()
            }
            .foregroundStyle(.white)
            .padding(16)
        }
        .background(ScreenBackground())
        .navigationTitle(friend.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.secondaryText)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
