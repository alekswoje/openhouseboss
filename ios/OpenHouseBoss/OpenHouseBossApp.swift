import SwiftUI

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
// on the device's horizontal size class.
struct RootView: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var router = AppRouter()
    @State private var splashDone = false

    var body: some View {
        ZStack {
            FoyerTheme.bgDeep.ignoresSafeArea()
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

            if !splashDone {
                SplashView()
                    .transition(.opacity)
                    .onAppear {
                        // Kick off backend prefetch in the background so the
                        // splash isn't dead time — by the time it fades, the
                        // Sessions tab usually has data ready to render.
                        Task { await SessionStore.shared.refreshSessions() }
                        Task { await SessionStore.shared.refreshScripts() }
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

            VStack(spacing: 14) {
                Spacer()

                // Eyebrow above the wordmark — small, monospaced, in gold.
                Text("OPEN HOUSE")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(2.4)
                    .foregroundStyle(FoyerTheme.gold)
                    .opacity(titleIn ? 1 : 0)
                    .offset(y: titleIn ? 0 : 6)

                // Wordmark — large editorial serif.
                Text("Boss")
                    .foyerDisplay(64)
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
        }
    }
}
