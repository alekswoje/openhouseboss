import SwiftUI

// Foyer / OpenHouseBoss — Linear / AI brand tokens (style-ai).
// Flat dark surfaces, electric cyan accent, sans-only typography.
enum FoyerTheme {
    // Surfaces — flat dark ramp (cool gray-blue)
    static let bgDeep   = Color(red: 0.031, green: 0.035, blue: 0.043)   // #08090b
    static let bg       = Color(red: 0.043, green: 0.051, blue: 0.063)   // #0b0d10
    static let bgCard   = Color(red: 0.063, green: 0.075, blue: 0.090)   // #101317
    static let bgElev   = Color(red: 0.086, green: 0.102, blue: 0.125)   // #161a20
    static let bgElev2  = Color(red: 0.110, green: 0.129, blue: 0.157)   // #1c2128

    // Lines
    static let border        = Color.white.opacity(0.06)
    static let borderStrong  = Color.white.opacity(0.14)
    static let hairline      = Color.white.opacity(0.06)

    // Primary accent — electric cyan (replaces the editorial gold)
    static let gold       = Color(red: 0.647, green: 0.953, blue: 0.988)  // #a5f3fc
    static let goldBright = Color(red: 0.812, green: 0.980, blue: 0.996)  // #cffafe
    static let goldDeep   = Color(red: 0.404, green: 0.910, blue: 0.976)  // #67e8f9
    static let goldSoft   = Color(red: 0.647, green: 0.953, blue: 0.988, opacity: 0.10)

    // Text — cool grays
    static let cream     = Color(red: 0.929, green: 0.929, blue: 0.949)   // #ededf2
    static let creamDim  = Color(red: 0.722, green: 0.722, blue: 0.769)   // #b8b8c4
    static let textDim   = Color(red: 0.541, green: 0.541, blue: 0.588)   // #8a8a96
    static let textMuted = Color(red: 0.353, green: 0.353, blue: 0.392)   // #5a5a64

    // Status accents — coral red + soft mint per style-ai
    static let terracotta     = Color(red: 0.973, green: 0.443, blue: 0.443)  // #f87171
    static let terracottaSoft = Color(red: 0.973, green: 0.443, blue: 0.443, opacity: 0.12)
    static let sage           = Color(red: 0.525, green: 0.937, blue: 0.675)  // #86efac
    static let sageSoft       = Color(red: 0.525, green: 0.937, blue: 0.675, opacity: 0.12)
}

// Eyebrow — mono-cap label. In style-mono the eyebrow uses the muted text
// color (per `.style-mono .eyebrow { color: var(--text-muted); }`).
struct Eyebrow: View {
    let text: String
    var color: Color = FoyerTheme.textMuted

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .tracking(2.0)
            .foregroundStyle(color)
    }
}

// Tag pill — buyer (white), seller (orange), browser (green).
struct TagPill: View {
    enum Kind { case buyer, seller, browser
        var color: Color {
            switch self {
            case .buyer: return FoyerTheme.gold
            case .seller: return FoyerTheme.terracotta
            case .browser: return FoyerTheme.sage
            }
        }
        var soft: Color {
            switch self {
            case .buyer: return FoyerTheme.goldSoft
            case .seller: return FoyerTheme.terracottaSoft
            case .browser: return FoyerTheme.sageSoft
            }
        }
        init?(_ raw: String) {
            switch raw.lowercased() {
            case "buyer": self = .buyer
            case "seller": self = .seller
            case "browser": self = .browser
            default: return nil
            }
        }
    }

    let kind: Kind
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(kind.color).frame(width: 5, height: 5)
            Text(text.uppercased())
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .foregroundStyle(kind.color)
        .background(kind.soft, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(kind.color, lineWidth: 1))
    }
}

// Hairline — the 1px subtle divider.
struct Hairline: View {
    var body: some View { Rectangle().fill(FoyerTheme.hairline).frame(height: 1) }
}

// Crest — cyan F outlined in cyan + Foyer wordmark (style-ai treatment).
struct Crest: View {
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: size * 0.4) {
            Text("F")
                .font(.system(size: size * 0.75, weight: .semibold))
                .foregroundStyle(FoyerTheme.gold)
                .frame(width: size * 1.3, height: size * 1.3)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(FoyerTheme.gold, lineWidth: 1))
            Text("Foyer")
                .font(.system(size: size, weight: .semibold))
                .tracking(-size * 0.02)
                .foregroundStyle(FoyerTheme.cream)
        }
    }
}

// Display heading helper — sans, tight tracking. In style-mono there is no
// serif and no italic; the design relies on weight + negative letter-spacing.
extension Text {
    func foyerDisplay(_ size: CGFloat, italic: Bool = false) -> some View {
        self
            .font(.system(size: size, weight: .medium))
            .tracking(-size * 0.045)
    }

    // Accent — used where editorial used italic-serif gold flourishes.
    // In mono it's the same family, same weight, same color as display text,
    // distinguished only by the negative tracking and (often) being inline.
    func foyerAccent(_ size: CGFloat) -> some View {
        self
            .font(.system(size: size, weight: .medium))
            .tracking(-size * 0.045)
    }
}

// Primary cyan button — dark text on bright cyan fill.
struct FoyerPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(FoyerTheme.bgDeep)
            .padding(.vertical, 16)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity)
            .background(configuration.isPressed ? FoyerTheme.goldDeep : FoyerTheme.gold)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// Ghost / outline button — transparent fill, hairline border.
struct FoyerGhostButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .tracking(1.0)
            .textCase(.uppercase)
            .foregroundStyle(FoyerTheme.cream)
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(FoyerTheme.borderStrong, lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(configuration.isPressed ? FoyerTheme.goldSoft : Color.clear)
                    )
            )
    }
}
