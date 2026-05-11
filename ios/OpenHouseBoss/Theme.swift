import SwiftUI

// Foyer / OpenHouseBoss — Style 02 "Linear / AI startup" (cyan flat).
// Flat dark surfaces, electric cyan accent, sans-only typography (no serif,
// no italic). Keeps the v2 design's Liquid Glass primitives but swaps the
// palette/typography per the user's chosen style.
enum FoyerTheme {
    // Surfaces — flat dark (cool gray-blue)
    static let bgDeep   = Color(red: 0.031, green: 0.035, blue: 0.043)   // #08090b
    static let bg       = Color(red: 0.043, green: 0.051, blue: 0.063)   // #0b0d10
    static let bgCard   = Color(red: 0.063, green: 0.075, blue: 0.090)   // #101317
    static let bgElev   = Color(red: 0.086, green: 0.102, blue: 0.125)   // #161a20
    static let bgElev2  = Color(red: 0.110, green: 0.129, blue: 0.157)   // #1c2128

    // Lines — neutral white tints
    static let border        = Color.white.opacity(0.06)
    static let borderStrong  = Color.white.opacity(0.14)
    static let hairline      = Color.white.opacity(0.06)

    // Primary accent — electric cyan (kept as `gold` keyword for reuse)
    static let gold       = Color(red: 0.647, green: 0.953, blue: 0.988)  // #a5f3fc
    static let goldBright = Color(red: 0.812, green: 0.980, blue: 0.996)  // #cffafe
    static let goldDeep   = Color(red: 0.404, green: 0.910, blue: 0.976)  // #67e8f9
    static let goldSoft   = Color(red: 0.647, green: 0.953, blue: 0.988, opacity: 0.10)

    // Text — cool grays
    static let cream     = Color(red: 0.929, green: 0.929, blue: 0.949)   // #ededf2
    static let creamDim  = Color(red: 0.722, green: 0.722, blue: 0.769)   // #b8b8c4
    static let textDim   = Color(red: 0.541, green: 0.541, blue: 0.588)   // #8a8a96
    static let textMuted = Color(red: 0.353, green: 0.353, blue: 0.392)   // #5a5a64

    // Status accents — coral red + mint
    static let terracotta     = Color(red: 0.973, green: 0.443, blue: 0.443)  // #f87171
    static let terracottaSoft = Color(red: 0.973, green: 0.443, blue: 0.443, opacity: 0.12)
    static let sage           = Color(red: 0.525, green: 0.937, blue: 0.675)  // #86efac
    static let sageSoft       = Color(red: 0.525, green: 0.937, blue: 0.675, opacity: 0.12)

    // Dark ink color for buttons on cyan fills.
    static let inkOnGold = Color(red: 0.031, green: 0.035, blue: 0.043)     // matches bgDeep
}

// MARK: – Typography helpers (sans-only — style-ai)

// Eyebrow — mono cap label, muted by default.
struct Eyebrow: View {
    let text: String
    var color: Color = FoyerTheme.textMuted

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .tracking(1.6)
            .foregroundStyle(color)
    }
}

// Hairline — 0.5pt divider, neutral tint.
struct Hairline: View {
    var body: some View { Rectangle().fill(FoyerTheme.hairline).frame(height: 0.5) }
}

// Crest — sans "F" with a thin cyan outline + "Foyer" wordmark. Used in the
// iPad kiosk header. Kept here for cross-app reuse.
struct Crest: View {
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: size * 0.4) {
            Text("F")
                .font(.system(size: size * 0.75, weight: .semibold))
                .foregroundStyle(FoyerTheme.gold)
                .frame(width: size * 1.3, height: size * 1.3)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(FoyerTheme.gold, lineWidth: 1)
                )
            Text("Foyer")
                .font(.system(size: size, weight: .semibold))
                .tracking(-size * 0.02)
                .foregroundStyle(FoyerTheme.cream)
        }
    }
}

// Display heading helper — sans, tight tracking. Per .style-ai there is no
// serif and no italic; the look relies on weight + negative letter-spacing.
extension Text {
    func foyerDisplay(_ size: CGFloat) -> some View {
        self
            .font(.system(size: size, weight: .medium))
            .tracking(-size * 0.030)
    }

    // Accent — used where editorial used italic-serif gold flourishes.
    // Sans, medium, cyan — same family/weight as display text.
    func foyerAccent(_ size: CGFloat) -> some View {
        self
            .font(.system(size: size, weight: .medium))
            .tracking(-size * 0.030)
            .foregroundStyle(FoyerTheme.gold)
    }
}

// Tag pill — buyer (cyan), seller (coral), browser (mint).
struct TagPill: View {
    enum Kind { case buyer, seller, browser
        var color: Color {
            switch self {
            case .buyer:   return FoyerTheme.gold
            case .seller:  return FoyerTheme.terracotta
            case .browser: return FoyerTheme.sage
            }
        }
        var soft: Color {
            switch self {
            case .buyer:   return FoyerTheme.goldSoft
            case .seller:  return FoyerTheme.terracottaSoft
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
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.4)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .foregroundStyle(kind.color)
        .background(kind.soft, in: RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4).stroke(kind.color.opacity(0.50), lineWidth: 0.5)
        )
    }
}

// MARK: – Liquid Glass primitives (kept; flat-styled for AI look)

// Subtle ambient gradient backdrop — keeps the screen from feeling totally
// flat. Cool tints (cyan + bg-card) rather than the editorial warm tones.
struct WarmBg: View {
    enum Tone { case gold, live, cool, auth }
    var tone: Tone = .gold

    var body: some View {
        GeometryReader { geo in
            ZStack {
                switch tone {
                case .gold, .auth:
                    radial(FoyerTheme.gold.opacity(0.08),
                           center: .init(x: 0.18, y: 0.05), radius: geo.size.width * 0.85)
                case .live:
                    radial(FoyerTheme.terracotta.opacity(0.12),
                           center: .init(x: 0.50, y: -0.02), radius: geo.size.width * 0.95)
                    radial(FoyerTheme.gold.opacity(0.06),
                           center: .init(x: 0.10, y: 0.92), radius: geo.size.width * 0.7)
                case .cool:
                    radial(FoyerTheme.sage.opacity(0.06),
                           center: .init(x: 0.85, y: 0.05), radius: geo.size.width * 0.7)
                    radial(FoyerTheme.gold.opacity(0.05),
                           center: .init(x: 0.10, y: 0.92), radius: geo.size.width * 0.7)
                }
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    private func radial(_ color: Color, center: UnitPoint, radius: CGFloat) -> some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [color, color.opacity(0)],
                    center: center,
                    startRadius: 0,
                    endRadius: radius
                )
            )
    }
}

// GlassSurface — bgCard-tinted dark panel with a hairline border. Flatter
// than the editorial version (Linear's aesthetic favors clean panels over
// frosted glass).
struct GlassSurface<Content: View>: View {
    var cornerRadius: CGFloat = 12
    var strong: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(strong ? FoyerTheme.bgElev : FoyerTheme.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(strong ? FoyerTheme.borderStrong : FoyerTheme.border, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.40), radius: 24, x: 0, y: 18)
    }
}

// Chip — uppercase mono pill, active state in cyan.
struct GlassChip: View {
    let text: String
    var active: Bool = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button(action: { onTap?() }) {
            Text(text.uppercased())
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.4)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .foregroundStyle(active ? FoyerTheme.gold : FoyerTheme.creamDim)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(active ? FoyerTheme.goldSoft : FoyerTheme.bgElev)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(active
                                ? FoyerTheme.gold.opacity(0.50)
                                : FoyerTheme.border, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}

// Status pill — small uppercase mono indicator.
struct StatusPill: View {
    enum Tone { case gold, live, sage, glass }
    let text: String
    var tone: Tone = .gold
    var pulsing: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if pulsing {
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                    .shadow(color: color, radius: 4)
                    .modifier(PulseAnimation())
            }
            Text(text.uppercased())
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.4)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .foregroundStyle(color)
        .background(bg, in: RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4).stroke(color.opacity(0.42), lineWidth: 0.5)
        )
    }

    private var color: Color {
        switch tone {
        case .gold:  return FoyerTheme.gold
        case .live:  return FoyerTheme.terracotta
        case .sage:  return FoyerTheme.sage
        case .glass: return FoyerTheme.creamDim
        }
    }
    private var bg: Color {
        switch tone {
        case .gold:  return FoyerTheme.goldSoft
        case .live:  return FoyerTheme.terracottaSoft
        case .sage:  return FoyerTheme.sageSoft
        case .glass: return FoyerTheme.bgElev
        }
    }
}

// Editorial back row — circular chevron + slash-separated trail. In AI style
// every crumb is sans-medium (last crumb cream, prior crumbs muted-mono).
struct BackBar<Trailing: View>: View {
    let crumbs: [String]
    var onBack: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(FoyerTheme.bgElev)
                        Circle().stroke(FoyerTheme.border, lineWidth: 0.5)
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(FoyerTheme.gold)
                    }
                    .frame(width: 32, height: 32)
                    HStack(spacing: 8) {
                        ForEach(Array(crumbs.enumerated()), id: \.offset) { i, c in
                            if i > 0 {
                                Text("/")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(FoyerTheme.textMuted)
                            }
                            if i == crumbs.count - 1 {
                                Text(c)
                                    .font(.system(size: 14, weight: .medium))
                                    .tracking(-0.3)
                                    .foregroundStyle(FoyerTheme.cream)
                                    .lineLimit(1)
                            } else {
                                Text(c.uppercased())
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .tracking(1.6)
                                    .foregroundStyle(FoyerTheme.textMuted)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

extension BackBar where Trailing == EmptyView {
    init(crumbs: [String], onBack: @escaping () -> Void) {
        self.init(crumbs: crumbs, onBack: onBack, trailing: { EmptyView() })
    }
}

// MARK: – Buttons

// Cyan-fill primary button — dark text on bright cyan.
struct FoyerPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(FoyerTheme.inkOnGold)
            .padding(.vertical, 17)
            .frame(maxWidth: .infinity)
            .background(configuration.isPressed ? FoyerTheme.goldDeep : FoyerTheme.gold)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .shadow(color: FoyerTheme.gold.opacity(0.25), radius: 10, x: 0, y: 6)
    }
}

// Ghost / outline button — bg-elev fill, hairline border.
struct FoyerGhostButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .tracking(1.0)
            .textCase(.uppercase)
            .foregroundStyle(FoyerTheme.cream)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed ? FoyerTheme.bgElev2 : FoyerTheme.bgElev)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(FoyerTheme.borderStrong, lineWidth: 0.5)
            )
    }
}

// Coral-fill button — used for "End session" only.
struct FoyerDangerButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(.white)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .background(configuration.isPressed
                        ? FoyerTheme.terracotta.opacity(0.85)
                        : FoyerTheme.terracotta)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .shadow(color: FoyerTheme.terracotta.opacity(0.35), radius: 10, x: 0, y: 6)
    }
}

// MARK: – Animation helpers

// Pulse — the live-dot heartbeat shared across status pills + recording UI.
struct PulseAnimation: ViewModifier {
    @State private var on: Bool = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(on ? 0.6 : 1)
            .opacity(on ? 0.5 : 1)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

// Concentric pulse ring — emanates outward, used around the recording mic.
struct PulseRing: View {
    var color: Color = FoyerTheme.gold
    var delay: Double = 0
    @State private var on = false

    var body: some View {
        Circle()
            .stroke(color, lineWidth: 1)
            .scaleEffect(on ? 1.9 : 0.9)
            .opacity(on ? 0 : 0.85)
            .animation(.easeOut(duration: 2.2).repeatForever(autoreverses: false).delay(delay), value: on)
            .onAppear { on = true }
    }
}
