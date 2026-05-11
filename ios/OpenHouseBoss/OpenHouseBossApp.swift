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
        case .visitors: return "Visitors"
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

    var body: some View {
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
        .background(FoyerTheme.bgDeep.ignoresSafeArea())
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
