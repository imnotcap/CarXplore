import SwiftUI

/// Fanen "Garage": din bil, dit niveau og din kørselsstatistik.
struct GarageScreen: View {
    @EnvironmentObject private var game: GameStore
    @EnvironmentObject private var friends: FriendsStore

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AppHeader(initials: Theme.initials(friends.me?.displayName ?? "Mig"))
                ScreenTitle(text: "Garage")

                carCard

                LazyVGrid(columns: columns, spacing: 14) {
                    StatTile(symbol: "road.lanes", value: "\(Int(game.totalKm).formatted()) km", label: "Kørt i alt")
                    StatTile(symbol: "flag.checkered", value: game.tripCount.formatted(), label: "Ture")
                    StatTile(symbol: "cloud.sun.fill",
                             value: "\(game.exploredAreaKm2.formatted(.number.precision(.fractionLength(1)))) km²",
                             label: "Udforsket")
                    StatTile(symbol: "scope",
                             value: "\(game.localAreaPercent.formatted(.number.precision(.fractionLength(1)))) %",
                             label: "Af lokalområdet")
                    StatTile(symbol: "moon.stars.fill", value: "\(Int(game.nightKm).formatted()) km", label: "Natkørsel")
                    StatTile(symbol: "trophy.fill", value: "\(game.unlocked.count)/\(game.landmarks.count)",
                             label: "Seværdigheder")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(ScreenBackground())
    }

    private var carCard: some View {
        let level = game.level
        let car = friends.me?.car ?? ""
        return VStack(spacing: 14) {
            ZStack {
                Ellipse()
                    .fill(Theme.cyan.opacity(0.25))
                    .frame(width: 220, height: 40)
                    .blur(radius: 14)
                    .offset(y: 38)
                Image(systemName: "car.side.fill")
                    .font(.system(size: 92))
                    .foregroundStyle(Theme.logoGradient)
                    .shadow(color: Theme.cyan.opacity(0.6), radius: 16)
            }
            .frame(height: 130)
            .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text(car.isEmpty ? "Din bil" : car)
                    .font(.title2.weight(.heavy))
                if car.isEmpty {
                    Text("Sæt din bil under Profil")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Niveau \(level.number) · \(level.title)")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(game.score.formatted()) point")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                }
                NeonProgressBar(value: level.progress)
                if let next = level.nextAt {
                    Text("\((next - game.score).formatted()) point til niveau \(level.number + 1)")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .glassCard(cornerRadius: 22, highlighted: true)
    }
}

private struct StatTile: View {
    let symbol: String
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.cyan)
                .frame(width: 38, height: 38)
                .background(Theme.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard(cornerRadius: 16)
        .accessibilityElement(children: .combine)
    }
}
