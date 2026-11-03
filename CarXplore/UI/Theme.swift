import SwiftUI

/// Farver og fælles komponenter til det mørke "neon over skyerne"-look.
enum Theme {
    static let background = Color(red: 0.035, green: 0.07, blue: 0.13)
    static let panel = Color(red: 0.07, green: 0.11, blue: 0.18)
    static let cyan = Color(red: 0.20, green: 0.80, blue: 1.0)
    static let blue = Color(red: 0.18, green: 0.48, blue: 1.0)
    static let mint = Color(red: 0.30, green: 1.0, blue: 0.62)
    static let danger = Color(red: 1.0, green: 0.36, blue: 0.40)
    static let gold = Color(red: 1.0, green: 0.78, blue: 0.28)
    static let secondaryText = Color.white.opacity(0.68)

    static let logoGradient = LinearGradient(colors: [blue, cyan], startPoint: .leading, endPoint: .trailing)
    static let actionGradient = LinearGradient(colors: [mint, cyan], startPoint: .leading, endPoint: .trailing)
    static let stopGradient = LinearGradient(colors: [danger, Color(red: 1, green: 0.58, blue: 0.32)],
                                             startPoint: .leading, endPoint: .trailing)
    static let unlockedBadge = LinearGradient(colors: [cyan, blue], startPoint: .top, endPoint: .bottom)
    static let lockedBadge = LinearGradient(colors: [Color(white: 0.45), Color(white: 0.28)],
                                            startPoint: .top, endPoint: .bottom)

    static func initials(_ name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

/// Mørk baggrund med et svagt blåt skær foroven.
struct ScreenBackground: View {
    var body: some View {
        ZStack {
            Theme.background
            RadialGradient(colors: [Theme.blue.opacity(0.28), .clear],
                           center: .top, startRadius: 10, endRadius: 480)
        }
        .ignoresSafeArea()
    }
}

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 18
    var highlighted = false

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(highlighted ? Theme.cyan.opacity(0.85) : Color.white.opacity(0.12),
                                  lineWidth: highlighted ? 1.5 : 1)
            )
            .shadow(color: highlighted ? Theme.cyan.opacity(0.35) : .clear, radius: 12)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 18, highlighted: Bool = false) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, highlighted: highlighted))
    }
}

struct LogoView: View {
    var size: CGFloat = 30

    var body: some View {
        (Text("Car").foregroundStyle(Theme.logoGradient)
            + Text("X").foregroundStyle(Theme.cyan)
            + Text("plore").foregroundStyle(.white))
            .font(.system(size: size, weight: .heavy).italic())
            .shadow(color: Theme.cyan.opacity(0.35), radius: 8)
            .accessibilityLabel("CarXplore")
    }
}

struct AvatarView: View {
    let initials: String
    var size: CGFloat = 36
    var ring: Color = Theme.cyan

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [Theme.blue, Color(red: 0.35, green: 0.25, blue: 0.85)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Circle())
            .overlay(Circle().strokeBorder(ring, lineWidth: 2))
    }
}

/// Logo-linjen øverst på alle faner.
struct AppHeader: View {
    let initials: String

    var body: some View {
        HStack {
            Image(systemName: "car.circle")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Theme.cyan)
                .accessibilityHidden(true)
            Spacer()
            LogoView()
            Spacer()
            AvatarView(initials: initials)
        }
    }
}

struct NeonProgressBar: View {
    let value: Double
    var height: CGFloat = 8
    var gradient: LinearGradient = Theme.actionGradient

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule()
                    .fill(gradient)
                    .frame(width: max(height, geo.size.width * min(max(value, 0), 1)))
                    .shadow(color: Theme.mint.opacity(0.5), radius: 4)
            }
        }
        .frame(height: height)
        .accessibilityValue("\(Int(value * 100)) procent")
    }
}

/// Lille pille-knap til filtre ("Alle", "Oplåste" …).
struct ChipButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? Color.black : .white)
                .background {
                    if isSelected {
                        Capsule().fill(Theme.unlockedBadge)
                    } else {
                        Capsule().fill(Color.white.opacity(0.08))
                    }
                }
                .overlay(Capsule().strokeBorder(Color.white.opacity(isSelected ? 0 : 0.18)))
        }
        .buttonStyle(.plain)
    }
}

/// Stor overskrift i kursiv versaler, fx "TROFÆER".
struct ScreenTitle: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 34, weight: .heavy).italic())
            .foregroundStyle(.white)
    }
}
