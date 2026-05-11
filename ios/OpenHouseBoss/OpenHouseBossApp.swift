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

// Routes to the iPhone agent flow or the iPad-landscape agent surface based on
// the device's horizontal size class. On iPad in portrait, fall back to the
// iPhone flow inside an extra-wide layout (still legible).
struct RootView: View {
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad && hSize == .regular {
                IPadAgentApp()
            } else {
                NavigationStack { SessionsView() }
            }
        }
        .background(FoyerTheme.bgDeep.ignoresSafeArea())
    }
}
