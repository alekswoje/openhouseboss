import AuthenticationServices
import SwiftUI
import UIKit

@main
struct OpenHouseBossApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(FoyerTheme.gold)
        }
    }
}

// One enum for every routed screen — keeps the NavigationStack typed so we
// can mutate the path imperatively (e.g. "after End session, replace the
// stack with just Summary so Back goes straight home").
enum AppRoute: Hashable {
    case picker                               // listings picker — entry to recording
    case editListing(id: String?)             // nil = create new
    case live
    case summary                              // fresh in-flight session
    case pastSession(id: String)              // pulled from /sessions list
    case visitorDetail(VisitorResult)
    case followup(VisitorResult)
    case visitorsAll
    case kiosk
    case scriptDetail(scriptId: String)
    case scriptEdit
}

enum HomeTab: Hashable, CaseIterable {
    case sessions, visitors, scripts, profile

    var label: String {
        switch self {
        case .sessions: return "Sessions"
        case .visitors: return "Leads"
        case .scripts:  return "Scripts"
        case .profile:  return "Profile"
        }
    }
    var icon: String {
        switch self {
        case .sessions: return "house"
        case .visitors: return "person.2"
        case .scripts:  return "doc.text"
        case .profile:  return "gearshape"
        }
    }
}

// Shared app-level router. Holds the navigation path so any screen can
// imperatively replace it (e.g. after End session) and the active home tab
// so the tab bar can switch the home shell's content.
@MainActor
@Observable
final class AppRouter {
    var path: [AppRoute] = []
    var tab: HomeTab = .sessions

    func push(_ route: AppRoute) { path.append(route) }
    func pop() { if !path.isEmpty { path.removeLast() } }
    func popToRoot() { path.removeAll() }

    // After End session: collapse the stack so Back from Summary goes to
    // Sessions (skipping the Live screen).
    func endSessionShowSummary() {
        path = [.summary]
    }
}

// Routes to the iPhone agent flow or the iPad-landscape agent surface based
// on the device's horizontal size class. Sits behind an auth gate — the
// AuthStore tries to restore a Keychain-saved JWT on launch; if there's no
// valid session, LoginView takes over.
struct RootView: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var router = AppRouter()
    @State private var auth = AuthStore.shared
    @State private var splashDone = false

    var body: some View {
        ZStack {
            FoyerTheme.bgDeep.ignoresSafeArea()
            content

            if !splashDone {
                SplashView()
                    .transition(.opacity)
                    .onAppear {
                        // Kick off auth-restore + first prefetches in the
                        // background so the splash isn't dead time.
                        Task {
                            await auth.restore()
                            if auth.isSignedIn {
                                await SessionStore.shared.refreshSessions()
                                await SessionStore.shared.refreshScripts()
                            }
                        }
                        Task {
                            try? await Task.sleep(for: .milliseconds(1400))
                            await MainActor.run {
                                withAnimation(.easeOut(duration: 0.35)) {
                                    splashDone = true
                                }
                            }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if auth.isSignedIn {
            Group {
                if UIDevice.current.userInterfaceIdiom == .pad && hSize == .regular {
                    IPadAgentApp()
                } else {
                    NavigationStack(path: $router.path) {
                        HomeShell()
                            .navigationDestination(for: AppRoute.self) { route in
                                destination(for: route)
                            }
                    }
                    .environment(router)
                }
            }
            .transition(.opacity)
        } else if !auth.loading {
            LoginView()
                .transition(.opacity)
        } else {
            // While we're still verifying the saved token. Splash is up too,
            // so this is invisible — but rendering an empty view keeps the
            // ZStack stable across the loading → signed-in transition.
            Color.clear
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .picker:                      ListingsPickerView()
        case .editListing(let id):         ListingEditView(listingId: id)
        case .live:                        LiveView()
        case .summary:                     SummaryView()
        case .pastSession(let id):         SummaryView(pastSessionId: id)
        case .visitorDetail(let v):        VisitorDetailView(visitor: v)
        case .followup(let v):             FollowupView(visitor: v)
        case .visitorsAll:                 AllVisitorsView()
        case .kiosk:                       KioskSignInView()
        case .scriptDetail(let id):        ScriptDetailView(scriptId: id)
        case .scriptEdit:                  ScriptEditView()
        }
    }
}

// MARK: – Animated splash

// Shown on cold start while the first /sessions and /scripts fetches are in
// flight. Three layered animations: a slow radial bloom in the background,
// the wordmark fading in with a slight slide, and a gold underline that
// draws across once the title settles. Sits on top of RootView for ~1.4s,
// then crossfades out.
struct SplashView: View {
    @State private var bloom = false
    @State private var titleIn = false
    @State private var underlineWidth: CGFloat = 0
    @State private var pulse = false

    var body: some View {
        ZStack {
            FoyerTheme.bgDeep.ignoresSafeArea()

            // Background gold bloom — soft radial gradient that fades in
            // and slowly grows. Anchored just above center so the wordmark
            // sits in the warm part of the gradient.
            RadialGradient(
                colors: [
                    FoyerTheme.gold.opacity(0.30),
                    FoyerTheme.gold.opacity(0.10),
                    .clear,
                ],
                center: .center,
                startRadius: 10,
                endRadius: bloom ? 320 : 60
            )
            .opacity(bloom ? 1 : 0)
            .ignoresSafeArea()
            .animation(.easeOut(duration: 1.2), value: bloom)

            VStack(spacing: 18) {
                Spacer()

                // Glowing brand mark — same F that runs the loading state
                // throughout the app, so the splash is unmistakably ours.
                FoyerBrandMark(size: 92, cornerRadius: 20)
                    .shadow(color: FoyerTheme.gold.opacity(0.5), radius: 18, y: 0)
                    .opacity(titleIn ? 1 : 0)
                    .scaleEffect(titleIn ? 1.0 : 0.86)

                // Wordmark — large editorial serif.
                Text("Foyer")
                    .foyerDisplay(72)
                    .foregroundStyle(FoyerTheme.cream)
                    .opacity(titleIn ? 1 : 0)
                    .offset(y: titleIn ? 0 : 10)

                // Gold underline that draws across once the title lands.
                Capsule()
                    .fill(FoyerTheme.gold)
                    .frame(width: underlineWidth, height: 2)
                    .shadow(color: FoyerTheme.gold.opacity(0.6), radius: 6, y: 0)

                Spacer()

                // Pulsing dot at the bottom — "we're loading" without a
                // spinner, on-brand. Subtle scale + opacity cycle.
                Circle()
                    .fill(FoyerTheme.gold)
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulse ? 1.4 : 0.8)
                    .opacity(pulse ? 0.4 : 1.0)
                    .padding(.bottom, 56)
            }
        }
        .onAppear {
            // Stagger the three motions so they read as one continuous
            // gesture rather than firing simultaneously.
            withAnimation(.easeOut(duration: 0.9)) { bloom = true }
            withAnimation(.easeOut(duration: 0.7).delay(0.15)) { titleIn = true }
            withAnimation(.easeOut(duration: 0.8).delay(0.45)) { underlineWidth = 140 }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
            // Pre-warm the iOS keyboard subsystem. Without this, the first
            // time any TextField in the app gets focus, the keyboard takes
            // 5-15s to appear on the simulator (well-known issue). Briefly
            // creating a UITextField and toggling first-responder forces
            // the keyboard layer to load while the splash is up — by the
            // time the agent taps a kiosk field later, the keyboard is hot.
            DispatchQueue.main.async {
                let dummy = UITextField()
                let scene = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }.first
                let window = scene?.windows.first(where: \.isKeyWindow) ?? UIWindow()
                window.addSubview(dummy)
                dummy.becomeFirstResponder()
                dummy.resignFirstResponder()
                dummy.removeFromSuperview()
            }
        }
    }
}

// MARK: – Login (Google Sign-In)

// Pre-auth landing inside the app. Editorial styling — gold radial bloom,
// glowing-F mark, serif "Foyer" wordmark, single Continue-with-Google
// button. The whole screen is choreographed: the bloom grows in first,
// the mark fades + scales up, the wordmark slides up, a gold underline
// draws across, the tagline appears, then the button rises into place
// and starts a slow ambient glow pulse so it never feels static.
// Tapping the button hands off to AuthStore.signInWithGoogle which opens
// an ASWebAuthenticationSession on the backend's /auth/google/start.
struct LoginView: View {
    @State private var auth = AuthStore.shared
    @State private var isSigningIn = false

    // Choreography flags — each one drives one of the staggered animations.
    @State private var bloom = false
    @State private var markIn = false
    @State private var titleIn = false
    @State private var underlineWidth: CGFloat = 0
    @State private var taglineIn = false
    @State private var ctaIn = false
    @State private var glowPulse = false

    var body: some View {
        ZStack {
            FoyerTheme.bgDeep.ignoresSafeArea()

            // Animated gold bloom — grows from a tight halo to a wide
            // radial wash as the screen settles. Matches the splash so
            // the transition into login feels like one continuous moment.
            RadialGradient(
                colors: [
                    FoyerTheme.gold.opacity(0.28),
                    FoyerTheme.gold.opacity(0.10),
                    .clear,
                ],
                center: .center,
                startRadius: 10,
                endRadius: bloom ? 480 : 80
            )
            .opacity(bloom ? 1 : 0)
            .ignoresSafeArea()
            .animation(.easeOut(duration: 1.4), value: bloom)

            VStack {
                Spacer()
                VStack(spacing: 18) {
                    FoyerBrandMark(size: 88, cornerRadius: 18)
                        .shadow(color: FoyerTheme.gold.opacity(0.45),
                                radius: glowPulse ? 28 : 14,
                                x: 0,
                                y: 0)
                        .scaleEffect(markIn ? 1.0 : 0.86)
                        .opacity(markIn ? 1 : 0)

                    Text("Foyer")
                        .foyerDisplay(72)
                        .foregroundStyle(FoyerTheme.cream)
                        .opacity(titleIn ? 1 : 0)
                        .offset(y: titleIn ? 0 : 14)

                    Capsule()
                        .fill(FoyerTheme.gold)
                        .frame(width: underlineWidth, height: 2)
                        .shadow(color: FoyerTheme.gold.opacity(0.6), radius: 6, y: 0)

                    Text("Every open house, quietly remembered.")
                        .font(.system(size: 15))
                        .foregroundStyle(FoyerTheme.creamDim)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                        .opacity(taglineIn ? 1 : 0)
                        .offset(y: taglineIn ? 0 : 8)
                }
                Spacer()
                signInBlock
                    .padding(.horizontal, 28)
                    .padding(.bottom, 60)
                    .opacity(ctaIn ? 1 : 0)
                    .offset(y: ctaIn ? 0 : 18)
            }
        }
        .onAppear { runIntroAnimation() }
    }

    // The staggered intro. Delays are tuned so each motion picks up where
    // the previous one is mid-way through — the screen reads as one
    // continuous gesture rather than five separate animations.
    private func runIntroAnimation() {
        withAnimation(.easeOut(duration: 1.2)) { bloom = true }
        withAnimation(.spring(response: 0.7, dampingFraction: 0.78).delay(0.15)) {
            markIn = true
        }
        withAnimation(.easeOut(duration: 0.7).delay(0.35)) { titleIn = true }
        withAnimation(.easeOut(duration: 0.8).delay(0.55)) { underlineWidth = 160 }
        withAnimation(.easeOut(duration: 0.6).delay(0.75)) { taglineIn = true }
        withAnimation(.easeOut(duration: 0.6).delay(0.95)) { ctaIn = true }
        // Slow ambient glow — never finishes, gives the screen a heartbeat
        // so it doesn't feel frozen while the user looks for the button.
        withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true).delay(1.3)) {
            glowPulse = true
        }
    }

    private var signInBlock: some View {
        VStack(spacing: 12) {
            if let err = auth.lastError {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(FoyerTheme.terracotta)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            Button(action: signIn) {
                HStack(spacing: 10) {
                    if isSigningIn || auth.loading {
                        ProgressView().tint(FoyerTheme.inkOnGold).scaleEffect(0.85)
                    } else {
                        Image(systemName: "g.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    Text(isSigningIn || auth.loading ? "Signing in…" : "Continue with Google")
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundStyle(FoyerTheme.inkOnGold)
                .background(FoyerTheme.gold, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: FoyerTheme.gold.opacity(glowPulse ? 0.55 : 0.30),
                        radius: glowPulse ? 22 : 12,
                        x: 0,
                        y: 6)
            }
            .buttonStyle(.plain)
            .disabled(isSigningIn || auth.loading)
            .opacity(isSigningIn || auth.loading ? 0.65 : 1)

            Text("BY CONTINUING, YOU AGREE TO FOYER'S TERMS · AGENTS ONLY")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(FoyerTheme.textMuted)
                .padding(.top, 6)
        }
    }

    private func signIn() {
        // ASWebAuthenticationSession needs a UIWindow-shaped anchor. Pull
        // the active window from the connected scene set.
        let anchor: ASPresentationAnchor = (
            UIApplication.shared
                .connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow }
        ) ?? UIWindow()
        isSigningIn = true
        Task {
            await auth.signInWithGoogle(presentationAnchor: anchor)
            await MainActor.run { isSigningIn = false }
        }
    }
}
