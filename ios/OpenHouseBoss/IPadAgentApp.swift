import AuthenticationServices
import LocalAuthentication
import MapKit
import SwiftUI
import UIKit

// iPad agent surface — runs on the open-house iPad.
//
// Visual direction: Notion side rail (icon nav + collapsible recent-sessions
// list), Instagram-black canvas with image-forward cards, YouTube-style
// session feed on Home, ChatGPT/Claude single-column reading layout for the
// lead detail, Spotify-style card grid for Listings, and a sticky "now
// playing"-style live-session bar pinned to the bottom whenever there's an
// active session or queued kiosk guests.
//
// Data: SessionStore.shared is the single source of truth. Listings come
// from store.listings (UserDefaults-persisted); past sessions from
// store.pastSessions (GET /sessions); the active session's visitors from
// APIClient.getSession; lead state mutations go through
// APIClient.updateLeadState. No SampleData references here.
struct IPadAgentApp: View {
    enum Tab: String, CaseIterable, Identifiable {
        case home, record, kiosk, leads, offers, listings, profile
        var id: String { rawValue }
        var label: String {
            switch self {
            case .home:     return "Home"
            case .record:   return "Record"
            case .kiosk:    return "Kiosk"
            case .leads:    return "Leads"
            case .offers:   return "Offers"
            case .listings: return "Listings"
            case .profile:  return "Profile"
            }
        }
        var iconOutline: String {
            switch self {
            case .home:     return "house"
            case .record:   return "waveform"
            case .kiosk:    return "person.badge.plus"
            case .leads:    return "tray"
            case .offers:   return "tag"
            case .listings: return "square.grid.2x2"
            case .profile:  return "person.crop.circle"
            }
        }
        var iconFilled: String {
            switch self {
            case .home:     return "house.fill"
            case .record:   return "waveform.circle.fill"
            case .kiosk:    return "person.badge.plus.fill"
            case .leads:    return "tray.fill"
            case .offers:   return "tag.fill"
            case .listings: return "square.grid.2x2.fill"
            case .profile:  return "person.crop.circle.fill"
            }
        }
    }

    @State private var tab: Tab = .home
    @State private var store = SessionStore.shared
    @State private var auth = AuthStore.shared
    @State private var activeListing: Listing?
    @State private var activeSessionId: String?
    // When set, the main pane shows the Session Detail view (playback +
    // metadata) instead of the tab content. Set by tapping a recent session
    // in the side rail or a row on Home; cleared by the detail view's back
    // arrow or by tapping any tab. activeSessionId is reserved for seeding
    // the Leads filter when the user drills from detail → leads.
    @State private var viewingPastSession: String?
    // Sidebar collapse — chevron in the brand row toggles between the full
    // 232pt rail and a compact 68pt rail (icons only). Stored in
    // UserDefaults so the agent's preference survives launches.
    @State private var sidebarCollapsed: Bool = UserDefaults.standard.bool(forKey: "ipad.sidebarCollapsed")
    // True while the agent has handed the iPad to guests. Sidebar + chrome
    // are hidden; getting out requires biometric (or passcode) auth so a
    // curious guest can't navigate away from the form.
    @State private var kioskLocked: Bool = false
    @State private var lockAuthFailed: Bool = false
    // Sheet flag for the Add Listing flow opened from the Kiosk launcher
    // or the Listings tab. Both surfaces present the same editor.
    @State private var showAddListing: Bool = false

    // Plays once per cold launch when the user is signed in. Renders on top
    // of the main UI from the very first frame so the agent sees the
    // welcome BEFORE the home content paints in — then fades out to reveal
    // the loaded home. The static flag survives view-struct re-creations so
    // we don't replay the welcome on tab switches.
    @State private var showWelcome: Bool = !IPadAgentApp.welcomeShownThisLaunch
    // Snapshot taken when the view first appears, so even after we flip
    // markWelcomed() the overlay keeps using the right copy until it fades.
    @State private var welcomeIsFirstTime: Bool = AuthStore.shared.isFirstWelcome
    private static var welcomeShownThisLaunch = false

    var body: some View {
        ZStack(alignment: .bottom) {
            if kioskLocked {
                IPadKiosk(
                    store: store,
                    listing: activeListing ?? store.listings.first,
                    locked: true,
                    onPickListing: {},
                    onLaunch: {},
                    onRequestExit: requestKioskExit
                )
                .transition(.opacity)
            } else {
                HStack(spacing: 0) {
                    IPadSideRail(
                        tab: $tab,
                        viewingPastSession: $viewingPastSession,
                        collapsed: $sidebarCollapsed,
                        store: store,
                        auth: auth,
                        onSelectTab: { selectTab($0) },
                        onSelectRecent: { id in viewingPastSession = id },
                        onToggleCollapse: {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                                sidebarCollapsed.toggle()
                            }
                            UserDefaults.standard.set(sidebarCollapsed, forKey: "ipad.sidebarCollapsed")
                        }
                    )
                    Rectangle()
                        .fill(FoyerTheme.hairline)
                        .frame(width: 1)
                    mainPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if hasLiveContext {
                    LiveSessionBar(
                        store: store,
                        recorder: AudioRecorder.shared,
                        onOpen: {
                            // Tapping the bar should land on whichever
                            // surface is currently "live": recording → Record
                            // tab; otherwise → Kiosk.
                            if AudioRecorder.shared.isRecording {
                                selectTab(.record)
                            } else {
                                selectTab(.kiosk)
                            }
                        },
                        onStopRecording: { stopRecording() }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                }
            }
            if showWelcome {
                WelcomeOverlay(name: firstName, greeting: welcomeIsFirstTime ? "Welcome," : "Welcome back,")
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .task {
            await store.refreshSessions()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openhousebossStopRecording)) { _ in
            // Posted by StopRecordingIntent from the Live Activity Stop
            // button. LiveActivityIntent runs in this app's process, so
            // NotificationCenter delivers the post directly — no IPC.
            guard AudioRecorder.shared.isRecording else { return }
            stopRecording()
        }
        .sheet(isPresented: $showAddListing) {
            IPadListingEditor(
                store: store,
                onDone: { listing in
                    if let listing { activeListing = listing }
                    showAddListing = false
                }
            )
        }
        .onAppear {
            guard !Self.welcomeShownThisLaunch else { return }
            Self.welcomeShownThisLaunch = true
            // Persist "we've welcomed this user" so the next launch shows
            // "Welcome back" instead of "Welcome".
            auth.markWelcomed()
            Task {
                // The overlay is already on screen from the first frame; we
                // just need to hold it long enough for the rings + checkmark
                // + name reveal to land, then fade out to reveal the home
                // content sitting behind it.
                try? await Task.sleep(for: .milliseconds(2400))
                withAnimation(.easeInOut(duration: 0.55)) { showWelcome = false }
            }
        }
    }

    private var firstName: String {
        let full = auth.currentUser?.name ?? "there"
        let trimmed = full.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "there" }
        return String(trimmed.split(separator: " ").first ?? Substring(trimmed))
    }

    private func lockKiosk() {
        withAnimation(.easeInOut(duration: 0.35)) {
            kioskLocked = true
        }
    }

    // Triggered by the lock icon inside the fullscreen kiosk. Runs the
    // system biometric/passcode prompt; on success we drop kioskLocked
    // and the sidebar comes back. On failure we leave the kiosk locked.
    private func requestKioskExit() {
        Task {
            let context = LAContext()
            context.localizedFallbackTitle = "Use Passcode"
            var error: NSError?
            // .deviceOwnerAuthentication = biometrics with passcode fallback.
            // Safer than biometrics-only because devices without Face/Touch
            // ID (or with biometrics locked out) can still exit kiosk mode.
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
                await MainActor.run { lockAuthFailed = true }
                return
            }
            do {
                let ok = try await context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: "Exit kiosk mode"
                )
                if ok {
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            kioskLocked = false
                        }
                    }
                }
            } catch {
                // User cancelled or failed — stay locked.
            }
        }
    }

    private var hasLiveContext: Bool {
        // Show the sticky bar only while something is actively in flight.
        // Specifically: recording, uploading, processing, OR queued kiosk
        // guests waiting to be matched. A completed (.ready) or failed
        // (.failed) session shouldn't keep the bar up — that was the bug
        // where the bar stayed pinned forever after the first session.
        if AudioRecorder.shared.isRecording { return true }
        switch store.phase {
        case .uploading, .processing: return true
        default: break
        }
        return !store.pendingKioskGuests.isEmpty
    }

    // Stops the in-progress recording from anywhere in the app (called by
    // the LiveSessionBar's stop button). Mirrors IPadRecord.endSession —
    // ends the live-snapshot loop (which does the final full-depth pass)
    // and bounces the user to the Record tab so they can watch the job
    // finish.
    private func stopRecording() {
        store.endLiveSnapshotLoop()
        selectTab(.record)
    }

    private func selectTab(_ t: Tab) {
        viewingPastSession = nil
        // Clear any session pre-filter when the user explicitly taps a tab in
        // the side rail. The pre-filter only sticks on EXPLICIT routes —
        // tapping a recent session, or "Open in Leads" from Session Detail —
        // so visiting the Leads tab from the rail always lands on All leads.
        if t == .leads {
            activeSessionId = nil
            // Leads has its own internal 340pt list sidebar — collapse the
            // main rail so the reading column has breathing room. We don't
            // persist this to UserDefaults; the agent's saved preference is
            // restored on launch and they can still expand manually.
            if !sidebarCollapsed {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                    sidebarCollapsed = true
                }
            }
        }
        tab = t
    }

    @ViewBuilder
    private var mainPane: some View {
        if let id = viewingPastSession {
            IPadSessionDetail(
                sessionId: id,
                store: store,
                onBack: { viewingPastSession = nil },
                onOpenLeads: { sid in
                    activeSessionId = sid
                    viewingPastSession = nil
                    tab = .leads
                }
            )
        } else {
            tabPane
        }
    }

    @ViewBuilder
    private var tabPane: some View {
        switch tab {
        case .home:
            IPadHome(
                store: store,
                auth: auth,
                onStartKiosk: { listing in
                    activeListing = listing
                    tab = .kiosk
                },
                onStartRecording: { listing in
                    activeListing = listing
                    tab = .record
                },
                onOpenSession: { id in
                    viewingPastSession = id
                }
            )
        case .record:
            IPadRecord(
                store: store,
                listing: activeListing,
                onSelectListing: { activeListing = $0 },
                onOpenLeads: { sessionId in
                    activeSessionId = sessionId
                    tab = .leads
                },
                onOpenSession: { sessionId in
                    // Land the user directly on the just-finished session
                    // rather than the readyPane prompt. They can still tap
                    // the "Open in Leads" CTA inside Session detail if they
                    // want to draft follow-ups next.
                    viewingPastSession = sessionId
                }
            )
        case .kiosk:
            IPadKiosk(
                store: store,
                listing: activeListing ?? store.listings.first,
                locked: false,
                onPickListing: { tab = .listings },
                onSelectListing: { activeListing = $0 },
                onAddListing: { showAddListing = true },
                onLaunch: { lockKiosk() },
                onRequestExit: {}
            )
        case .leads:
            IPadLeads(store: store, initialFilter: activeSessionId)
        case .offers:
            IPadOffers()
        case .listings:
            IPadListings(
                store: store,
                onPickListing: { listing in
                    activeListing = listing
                    tab = .kiosk
                },
                onAdd: { showAddListing = true }
            )
        case .profile:
            IPadProfile(store: store, auth: auth)
        }
    }
}

// MARK: – Side rail (Notion + ChatGPT)

// Always-expanded rail with two regions:
//   1. Brand mark + nav buttons (Notion-style icon rows with labels)
//   2. "Recent" list of past sessions (ChatGPT-style sidebar history)
// Bottom corner has the agent avatar. Filled icons in the active row, soft
// fill on the row background — no hard borders or stroked outlines.
private struct IPadSideRail: View {
    @Binding var tab: IPadAgentApp.Tab
    @Binding var viewingPastSession: String?
    @Binding var collapsed: Bool
    let store: SessionStore
    let auth: AuthStore
    var onSelectTab: (IPadAgentApp.Tab) -> Void
    var onSelectRecent: (String) -> Void
    var onToggleCollapse: () -> Void

    @State private var pendingDeleteId: String?

    private var railWidth: CGFloat { collapsed ? 68 : 232 }

    private var recordedSessions: [SessionSummary] {
        store.pastSessions.filter { $0.kind == "recorded" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.horizontal, collapsed ? 12 : 16)
                .padding(.top, 22)
                .padding(.bottom, 22)

            VStack(spacing: 2) {
                // Profile lives behind the bottom-left avatar; no need
                // to duplicate it in the main nav rail.
                ForEach(IPadAgentApp.Tab.allCases.filter { $0 != .profile }) { t in
                    navRow(t)
                }
            }
            .padding(.horizontal, collapsed ? 8 : 10)

            if !collapsed && !recordedSessions.isEmpty {
                Text("Recent")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FoyerTheme.textMuted)
                    .padding(.horizontal, 22)
                    .padding(.top, 28)
                    .padding(.bottom, 6)
                    .transition(.opacity)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 1) {
                        ForEach(recordedSessions.prefix(20)) { s in
                            recentRow(s)
                        }
                    }
                    .padding(.horizontal, 10)
                }
                .transition(.opacity)
            } else {
                Spacer()
            }

            Spacer(minLength: 0)

            avatar
                .padding(.horizontal, collapsed ? 12 : 16)
                .padding(.vertical, 14)
        }
        .frame(width: railWidth)
        .background(Color(white: 0.04))
        .clipped()
        // When collapsed, tapping anywhere in the rail expands it. Child
        // Buttons (nav rows, avatar, brand) consume their own taps and
        // still call onToggleCollapse from within their actions, so all
        // taps lead to expansion — including empty space hits here.
        .contentShape(Rectangle())
        .onTapGesture {
            if collapsed { onToggleCollapse() }
        }
        .alert(
            "Delete this session?",
            isPresented: Binding(
                get: { pendingDeleteId != nil },
                set: { if !$0 { pendingDeleteId = nil } }
            ),
            presenting: pendingDeleteId
        ) { id in
            Button("Cancel", role: .cancel) { pendingDeleteId = nil }
            Button("Delete permanently", role: .destructive) {
                Task { await performDelete(id) }
            }
        } message: { _ in
            Text("This permanently removes the recording, transcript, analysis, and all leads from this session. It can't be undone.")
        }
    }

    @MainActor
    private func performDelete(_ id: String) async {
        defer { pendingDeleteId = nil }
        do {
            try await APIClient.shared.deleteSession(id: id)
            await store.refreshSessions()
            if viewingPastSession == id { viewingPastSession = nil }
        } catch {
            // Silent fail — surfacing an alert from the rail mid-deletion
            // gets noisy; the user can retry from the detail view if needed.
        }
    }

    @ViewBuilder
    private var brand: some View {
        if collapsed {
            // Collapsed: just the F mark, tappable to expand. Single
            // centered element fits cleanly in the 68pt rail; no crowded
            // chevron-next-to-mark situation.
            Button(action: onToggleCollapse) {
                FoyerBrandMark(size: 36, cornerRadius: 8)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 10) {
                FoyerBrandMark(size: 36, cornerRadius: 8)
                Text("Foyer")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(FoyerTheme.cream)
                    .tracking(-0.3)
                Spacer()
                Button(action: onToggleCollapse) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FoyerTheme.creamDim)
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.05), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func navRow(_ t: IPadAgentApp.Tab) -> some View {
        let active = (tab == t) && (viewingPastSession == nil)
        if collapsed {
            // Compact icon-only row — the active fill is a square instead
            // of a wide pill so it reads cleanly in the narrow rail.
            // Tapping ALSO expands the rail so the user lands on the new
            // tab with the labels visible (one tap = navigate + expand).
            Button {
                onSelectTab(t)
                onToggleCollapse()
            } label: {
                Image(systemName: active ? t.iconFilled : t.iconOutline)
                    .font(.system(size: 17, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? FoyerTheme.gold : FoyerTheme.creamDim)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(active ? FoyerTheme.goldSoft : Color.clear)
                    )
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(t.label)
        } else {
            Button { onSelectTab(t) } label: {
                HStack(spacing: 12) {
                    Image(systemName: active ? t.iconFilled : t.iconOutline)
                        .font(.system(size: 16, weight: active ? .semibold : .regular))
                        .frame(width: 22)
                        .foregroundStyle(active ? FoyerTheme.gold : FoyerTheme.creamDim)
                    Text(t.label)
                        .font(.system(size: 14, weight: active ? .semibold : .medium))
                        .foregroundStyle(active ? FoyerTheme.cream : FoyerTheme.creamDim)
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(active ? Color.white.opacity(0.06) : Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func recentRow(_ s: SessionSummary) -> some View {
        let active = (viewingPastSession == s.id)
        return Button {
            onSelectRecent(s.id)
        } label: {
            HStack(spacing: 10) {
                Text(s.displayTitle)
                    .font(.system(size: 13))
                    .foregroundStyle(active ? FoyerTheme.cream : FoyerTheme.creamDim)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(s.visitorCount)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FoyerTheme.textMuted)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(active ? Color.white.opacity(0.06) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                pendingDeleteId = s.id
            } label: {
                Label("Delete session", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if collapsed {
            // Centered avatar bubble fills the 68pt rail nicely. Tap
            // expands the rail AND lands on the Profile surface so the
            // user sees their full account / settings layout right away.
            Button {
                onSelectTab(.profile)
                onToggleCollapse()
            } label: {
                avatarBubble
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        } else {
            Button { onSelectTab(.profile) } label: {
                HStack(spacing: 10) {
                    avatarBubble
                    VStack(alignment: .leading, spacing: 1) {
                        Text(displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(FoyerTheme.cream)
                            .lineLimit(1)
                        Text(auth.currentUser?.email ?? "Agent")
                            .font(.system(size: 11))
                            .foregroundStyle(FoyerTheme.textMuted)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(FoyerTheme.textMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var avatarBubble: some View {
        if let str = auth.currentUser?.picture, let url = URL(string: str) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                default:
                    initialsBubble
                }
            }
            .frame(width: 30, height: 30)
            .clipShape(Circle())
        } else {
            initialsBubble
        }
    }

    private var initialsBubble: some View {
        Text(initials)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(FoyerTheme.creamDim)
            .frame(width: 30, height: 30)
            .background(FoyerTheme.bgElev, in: Circle())
    }

    private var displayName: String {
        auth.currentUser?.name ?? "Signed in"
    }

    private var initials: String {
        let name = auth.currentUser?.name ?? auth.currentUser?.email ?? "?"
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

// MARK: – Sticky live-session bar (Spotify now-playing)

// Pinned to the bottom of the iPad when there's either an active recorded
// session or guests queued on the kiosk. One tap jumps to whichever surface
// is relevant. Visually: dark elevated capsule that floats above content.
private struct LiveSessionBar: View {
    let store: SessionStore
    let recorder: AudioRecorder
    var onOpen: () -> Void
    var onStopRecording: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onOpen) {
                HStack(spacing: 14) {
                    leadIcon
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(FoyerTheme.cream)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(FoyerTheme.creamDim)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if recorder.isRecording {
                // Stop button — pulled out as its own tap target so the
                // bar's main tap still routes to the Record tab while
                // the stop pill ends the session in-place. Matches the
                // user's "widget to stop recording" requirement.
                Button(action: onStopRecording) {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.white)
                            .frame(width: 9, height: 9)
                        Text("Stop")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(FoyerTheme.terracotta, in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FoyerTheme.creamDim)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(recorder.isRecording ? FoyerTheme.terracotta.opacity(0.5) : Color.white.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var leadIcon: some View {
        if recorder.isRecording {
            ZStack {
                Circle().fill(FoyerTheme.terracotta.opacity(0.18))
                    .frame(width: 44, height: 44)
                Circle().fill(FoyerTheme.terracotta)
                    .frame(width: 12, height: 12)
                    .modifier(PulseAnimation())
            }
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(FoyerTheme.goldSoft)
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: pulseIcon)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(FoyerTheme.gold)
                )
        }
    }

    private var pulseIcon: String {
        store.session != nil ? "waveform" : "person.badge.plus.fill"
    }

    private var title: String {
        if recorder.isRecording {
            return store.pendingAddress ?? "Recording"
        }
        if let s = store.session {
            return s.address ?? "Live session"
        }
        return store.pendingAddress ?? "Ready to start"
    }

    private var subtitle: String {
        if recorder.isRecording {
            return "Live · \(elapsedString)"
        }
        let count = store.pendingKioskGuests.count
        if store.session != nil {
            return "Processing · \(count) guest\(count == 1 ? "" : "s")"
        }
        return "\(count) signed in"
    }

    private var elapsedString: String {
        let total = Int(recorder.elapsed)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }
}

// MARK: – Home (Spotify/YouTube — content feed)

// Greeting → big featured listing card (Instagram-style image-forward) →
// vertical session feed (YouTube rows). Sessions list is real — pulled
// from store.pastSessions.
private struct IPadHome: View {
    let store: SessionStore
    let auth: AuthStore
    var onStartKiosk: (Listing) -> Void
    var onStartRecording: (Listing?) -> Void
    var onOpenSession: (String) -> Void

    @State private var pendingDeleteId: String?
    @State private var deleting: Bool = false
    @State private var deleteError: String?

    private var recorded: [SessionSummary] {
        store.pastSessions.filter { $0.kind == "recorded" }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 36) {
                greeting
                if let listing = store.listings.first {
                    heroListing(listing)
                } else {
                    emptyHero
                }
                if !recorded.isEmpty {
                    sessionFeed
                } else if store.listLoading {
                    // Cold-start safety net: show a spinner instead of a
                    // bare empty page while the first GET /sessions is still
                    // in flight. Without this, agents with sessions saw a
                    // misleading "no sessions" state for the 5-30s wake-up.
                    loadingFeed
                }
            }
            .padding(.horizontal, 44)
            .padding(.top, 36)
            .padding(.bottom, 120) // breathing room for the sticky bar
        }
        .refreshable { await store.refreshSessions() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private var loadingFeed: some View {
        VStack(spacing: 14) {
            FoyerLoadingView(size: 64, cornerRadius: 10)
            Text("Loading your sessions…")
                .font(.system(size: 13))
                .foregroundStyle(FoyerTheme.textDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(periodOfDay)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(FoyerTheme.textDim)
            Text("Good \(periodOfDayShort), \(firstName)")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(FoyerTheme.cream)
                .tracking(-0.6)
        }
    }

    private var firstName: String {
        let full = auth.currentUser?.name ?? "there"
        let trimmed = full.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "there" }
        return String(trimmed.split(separator: " ").first ?? Substring(trimmed))
    }

    private var periodOfDay: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: Date())
    }

    private var periodOfDayShort: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "morning"
        case 12..<17: return "afternoon"
        case 17..<22: return "evening"
        default:      return "evening"
        }
    }

    private func heroListing(_ listing: Listing) -> some View {
        ZStack(alignment: .bottomLeading) {
            listingImage(listing)
                .frame(height: 360)
                .clipped()
            LinearGradient(
                colors: [.clear, .black.opacity(0.2), .black.opacity(0.85)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 360, alignment: .bottom)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 7) {
                    Circle().fill(FoyerTheme.terracotta).frame(width: 7, height: 7)
                        .modifier(PulseAnimation())
                    Text("Hosting today")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text(listing.address)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)
                    .tracking(-0.7)
                    .lineLimit(2)
                HStack(spacing: 16) {
                    if !listing.displayPrice.isEmpty {
                        Text(listing.displayPrice)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(FoyerTheme.gold)
                    }
                    Text(listing.displaySpecs)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Button { onStartKiosk(listing) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Sign-in")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(FoyerTheme.cream)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(Color.white.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Button { onStartRecording(listing) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "waveform")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Record")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(FoyerTheme.inkOnGold)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(FoyerTheme.gold, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(28)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private func listingImage(_ listing: Listing) -> some View {
        if let data = listing.photoData, let img = UIImage(data: data) {
            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.13, green: 0.16, blue: 0.21),
                        Color(red: 0.05, green: 0.06, blue: 0.08),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                Image(systemName: "house")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.white.opacity(0.12))
            }
        }
    }

    private var emptyHero: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(FoyerTheme.goldSoft).frame(width: 64, height: 64)
                Image(systemName: "waveform")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(FoyerTheme.gold)
            }
            Text("Ready when you are")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(FoyerTheme.cream)
            Text("Record your next open-house walkthrough.\nWe'll separate the voices and draft follow-ups.")
                .font(.system(size: 14))
                .foregroundStyle(FoyerTheme.textDim)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            Button { onStartRecording(nil) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Start recording")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(FoyerTheme.inkOnGold)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(FoyerTheme.gold, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(white: 0.06))
        )
    }

    private var sessionFeed: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent sessions")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(FoyerTheme.cream)
                Spacer()
                if recorded.count > 6 {
                    Text("\(recorded.count) total")
                        .font(.system(size: 12))
                        .foregroundStyle(FoyerTheme.textDim)
                }
            }
            VStack(spacing: 10) {
                ForEach(recorded.prefix(8)) { s in
                    Button { onOpenSession(s.id) } label: {
                        sessionRow(s)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            pendingDeleteId = s.id
                        } label: {
                            Label("Delete session", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .alert(
            "Delete this session?",
            isPresented: Binding(
                get: { pendingDeleteId != nil },
                set: { if !$0 { pendingDeleteId = nil } }
            ),
            presenting: pendingDeleteId
        ) { id in
            Button("Cancel", role: .cancel) { pendingDeleteId = nil }
            Button("Delete permanently", role: .destructive) {
                Task { await performDelete(id) }
            }
        } message: { _ in
            Text("This permanently removes the recording, transcript, analysis, and all leads from this session. It can't be undone.")
        }
    }

    @MainActor
    private func performDelete(_ id: String) async {
        deleting = true
        deleteError = nil
        defer { deleting = false; pendingDeleteId = nil }
        do {
            try await APIClient.shared.deleteSession(id: id)
            await store.refreshSessions()
        } catch {
            deleteError = error.localizedDescription
        }
    }

    private func sessionRow(_ s: SessionSummary) -> some View {
        HStack(spacing: 16) {
            // Thumbnail tile — uses a placeholder gradient since session
            // summaries don't carry a photo. YouTube-row feel.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.12, green: 0.14, blue: 0.19),
                            Color(red: 0.05, green: 0.06, blue: 0.08),
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: 92, height: 64)
                .overlay(
                    Image(systemName: "waveform")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(FoyerTheme.gold.opacity(0.55))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(s.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FoyerTheme.cream)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(relativeTime(s.createdDate))
                        .font(.system(size: 12))
                        .foregroundStyle(FoyerTheme.textDim)
                    Text("·")
                        .font(.system(size: 12))
                        .foregroundStyle(FoyerTheme.textMuted)
                    Text("\(s.visitorCount) \(s.visitorCount == 1 ? "lead" : "leads")")
                        .font(.system(size: 12))
                        .foregroundStyle(FoyerTheme.textDim)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(FoyerTheme.textMuted)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color(white: 0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }

    private func relativeTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: – Kiosk (Instagram — image-forward sign-in)

// Big listing photo on the left, minimal form on the right. Submitting
// appends to SessionStore.pendingKioskGuests — same wire as the iPhone
// KioskSignInView so LiveView can read the guest list from the store.
private struct IPadKiosk: View {
    let store: SessionStore
    let listing: Listing?
    // When true, the kiosk renders fullscreen for guests: no sidebar (the
    // parent already hides it), and a discreet back arrow in the top-left
    // triggers biometric auth to return to the agent view. When false, the
    // view sits inside the agent's Kiosk tab and shows a "Launch kiosk"
    // button instead.
    var locked: Bool = false
    var onPickListing: () -> Void
    var onSelectListing: (Listing) -> Void = { _ in }
    var onAddListing: () -> Void = {}
    var onLaunch: () -> Void
    var onRequestExit: () -> Void

    // Form state — split first/last per the agent's UX preference. The
    // pendingKioskGuests list is no longer read here (it caused a re-render
    // on every keystroke), so the form pane stays cheap.
    @State private var first: String = ""
    @State private var last: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    // Default to "Not yet" so guests with no agent can sail through; agents
    // who are already working with someone toggle to Yes.
    @State private var hasAgent: VisitorInput.HasAgent? = .no
    // One combined acceptance — covers both the ambient-recording consent
    // and the marketing-email opt-in. The visible label is intentionally
    // generic ("agree to Terms & Privacy"); the substance lives in those
    // documents so the guest just taps once instead of reading two lines.
    @State private var termsAccepted: Bool = false

    @State private var emailCheck: ValidationState = .idle
    @State private var phoneCheck: ValidationState = .idle
    @State private var emailDebounce: Task<Void, Never>?
    @State private var phoneDebounce: Task<Void, Never>?

    @State private var showSuccess: Bool = false
    @State private var submitting: Bool = false
    @State private var submitError: String?
    @FocusState private var focused: Field?

    private enum Field { case first, last, email, phone }

    enum ValidationState: Equatable {
        case idle
        case checking
        case valid(String?)         // optional friendly hint, e.g. "Looks good"
        case invalid(String)        // user-facing reason

        var isValid: Bool { if case .valid = self { return true }; return false }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if locked {
                // Guest-facing: full listing photo on the left, sign-in
                // form on the right. This is the only place the form
                // actually renders — the agent's pre-launch view is a
                // distinct config surface, so it doesn't look like the
                // real kiosk and there's no chance of confusing the two.
                HStack(spacing: 0) {
                    listingPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    formPane
                        .frame(maxWidth: 560, maxHeight: .infinity)
                        .background(Color.black)
                }
                exitButton
                    .padding(.top, 18)
                    .padding(.leading, 18)
            } else {
                agentLauncher
            }
            if showSuccess {
                KioskSuccessOverlay(name: first.isEmpty ? "you" : first)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
    }

    // Pre-launch surface inside the Kiosk tab. Pared down: just the agent's
    // listings as cards (each with its own Launch button) and, when there
    // are no listings, a pair of stark options — launch without one, or
    // add one first.
    private var agentLauncher: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                Text("Kiosk")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(FoyerTheme.cream)
                    .tracking(-0.5)

                if store.listings.isEmpty {
                    emptyListingsLauncher
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(store.listings) { listing in
                            launchRow(listing)
                        }
                        Button(action: onLaunch) {
                            HStack(spacing: 8) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Launch without a listing")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundStyle(FoyerTheme.creamDim)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Color.white.opacity(0.06), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 6)
                    }
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 44).padding(.top, 36).padding(.bottom, 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
    }

    private func launchRow(_ listing: Listing) -> some View {
        HStack(spacing: 14) {
            listingThumb(listing)
                .frame(width: 84, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(listing.address)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(FoyerTheme.cream)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if !listing.displayPrice.isEmpty {
                        Text(listing.displayPrice)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(FoyerTheme.gold)
                    }
                    Text(listing.displaySpecs)
                        .font(.system(size: 12))
                        .foregroundStyle(FoyerTheme.textDim)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button {
                onSelectListing(listing)
                onLaunch()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Launch")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(FoyerTheme.inkOnGold)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(FoyerTheme.gold, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    private var emptyListingsLauncher: some View {
        VStack(spacing: 12) {
            Button(action: onLaunch) {
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Launch kiosk without a listing")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(FoyerTheme.inkOnGold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(FoyerTheme.gold, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            Button(action: onAddListing) {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Add a listing")
                        .font(.system(size: 15, weight: .medium))
                }
                .foregroundStyle(FoyerTheme.cream)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func listingThumb(_ listing: Listing) -> some View {
        if let data = listing.photoData, let img = UIImage(data: data) {
            Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.12, blue: 0.16),
                    Color(red: 0.03, green: 0.04, blue: 0.06),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .overlay(
                Image(systemName: "house")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(.white.opacity(0.18))
            )
        }
    }

    private var exitButton: some View {
        Button(action: onRequestExit) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.35), in: Circle())
                .overlay(
                    Circle().stroke(.white.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var listingPane: some View {
        if let listing {
            ZStack(alignment: .bottomLeading) {
                listingImage(listing)
                LinearGradient(
                    colors: [.clear, .black.opacity(0.4), .black.opacity(0.88)],
                    startPoint: .top, endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 7) {
                        Circle().fill(FoyerTheme.gold).frame(width: 6, height: 6)
                        Text("Open house")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(FoyerTheme.gold)
                            .tracking(0.4)
                    }
                    Text(listing.address)
                        .font(.system(size: 60, weight: .semibold))
                        .foregroundStyle(.white)
                        .tracking(-1.2)
                        .lineLimit(2)
                    if !listing.neighborhood.isEmpty {
                        Text(listing.neighborhood)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    HStack(alignment: .firstTextBaseline) {
                        if !listing.displayPrice.isEmpty {
                            Text(listing.displayPrice)
                                .font(.system(size: 34, weight: .semibold))
                                .foregroundStyle(FoyerTheme.gold)
                                .tracking(-0.5)
                        }
                        Spacer()
                        Text(listing.displaySpecs)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(.top, 6)
                }
                .padding(44)
            }
            .clipped()
        } else {
            // No listing — show a calm welcome panel. The Foyer brand mark
            // is intentionally dropped here because the back arrow lives in
            // the same top-left corner and they'd visually collide.
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [
                        Color(red: 0.10, green: 0.12, blue: 0.16),
                        Color(red: 0.03, green: 0.04, blue: 0.06),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 7) {
                        Circle().fill(FoyerTheme.gold).frame(width: 6, height: 6)
                        Text("Welcome")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(FoyerTheme.gold)
                            .tracking(0.4)
                    }
                    Text("Come on in.")
                        .font(.system(size: 60, weight: .semibold))
                        .foregroundStyle(.white)
                        .tracking(-1.2)
                    Text("Sign in over there so we can\nfollow up after the tour.")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineSpacing(4)
                }
                .padding(44)
            }
            .clipped()
        }
    }

    @ViewBuilder
    private func listingImage(_ listing: Listing) -> some View {
        if let data = listing.photoData, let img = UIImage(data: data) {
            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipped()
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.12, blue: 0.16),
                    Color(red: 0.03, green: 0.04, blue: 0.06),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    private var formPane: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Welcome in")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FoyerTheme.gold)
                    .tracking(0.4)
                    .padding(.bottom, 16)

                Text("A few details.")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(FoyerTheme.cream)
                    .tracking(-0.6)
                Text("Shared with the listing agent so they can follow up.")
                    .font(.system(size: 14))
                    .foregroundStyle(FoyerTheme.textDim)
                    .padding(.top, 6)

                VStack(spacing: 14) {
                    HStack(spacing: 10) {
                        KioskField(
                            label: "First name",
                            text: $first,
                            keyboard: .default,
                            content: .givenName,
                            isFocused: focused == .first,
                            indicator: nil
                        )
                        .focused($focused, equals: .first)

                        KioskField(
                            label: "Last name",
                            text: $last,
                            keyboard: .default,
                            content: .familyName,
                            isFocused: focused == .last,
                            indicator: nil
                        )
                        .focused($focused, equals: .last)
                    }

                    KioskField(
                        label: "Email",
                        text: $email,
                        keyboard: .emailAddress,
                        content: .emailAddress,
                        isFocused: focused == .email,
                        indicator: emailCheck
                    )
                    .focused($focused, equals: .email)
                    .onChange(of: email) { _, newValue in
                        scheduleEmailCheck(newValue)
                    }

                    KioskField(
                        label: "Phone",
                        text: $phone,
                        keyboard: .asciiCapableNumberPad,
                        content: .telephoneNumber,
                        isFocused: focused == .phone,
                        indicator: phoneCheck
                    )
                    .focused($focused, equals: .phone)
                    .onChange(of: phone) { old, new in
                        // Format inside onChange (not a custom Binding) — the
                        // custom-Binding approach skipped intermediate
                        // formatting on rapid keystrokes; onChange runs on
                        // every commit so "(555) 1" appears as you type.
                        let formatted = formatPhone(new)
                        if formatted != new {
                            phone = formatted
                        }
                        schedulePhoneCheck(formatted)
                    }
                }
                .padding(.top, 24)

                agentChooser
                    .padding(.top, 20)

                termsRow
                    .padding(.top, 22)

                if let submitError {
                    Text(submitError)
                        .font(.system(size: 12))
                        .foregroundStyle(FoyerTheme.terracotta)
                        .padding(.top, 12)
                }

                Button {
                    Task { await submit() }
                } label: {
                    HStack(spacing: 8) {
                        if submitting {
                            ProgressView().scaleEffect(0.75).tint(FoyerTheme.inkOnGold)
                        } else {
                            Text("Done")
                                .font(.system(size: 15, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                    .foregroundStyle(FoyerTheme.inkOnGold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(FoyerTheme.gold, in: RoundedRectangle(cornerRadius: 14))
                    .opacity(canSubmit ? 1 : 0.5)
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit || submitting)
                .padding(.top, 24)
            }
            .padding(.horizontal, 40).padding(.vertical, 40)
        }
    }

    private var agentChooser: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Working with an agent?")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(FoyerTheme.textDim)
            HStack(spacing: 8) {
                ForEach(VisitorInput.HasAgent.allCases) { opt in
                    Button { hasAgent = opt } label: {
                        Text(opt.label)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(hasAgent == opt ? FoyerTheme.inkOnGold : FoyerTheme.creamDim)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(hasAgent == opt ? FoyerTheme.gold : Color(white: 0.06))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // Single combined acceptance. The visible label is intentionally vague
    // — the substance (recording consent, marketing opt-in, data handling)
    // is in the Terms + Privacy docs that link out from "find out more".
    private var termsRow: some View {
        Button { termsAccepted.toggle() } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(termsAccepted ? FoyerTheme.gold : Color.white.opacity(0.25), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if termsAccepted {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(FoyerTheme.gold)
                            .frame(width: 22, height: 22)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(FoyerTheme.inkOnGold)
                    }
                }
                .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text("I agree to Foyer's Terms & Privacy Policy.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(FoyerTheme.cream)
                        .multilineTextAlignment(.leading)
                    Text("Includes audio recording for training purposes and listing follow-ups from your hosting agent.")
                        .font(.system(size: 11))
                        .foregroundStyle(FoyerTheme.textMuted)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(2)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var canSubmit: Bool {
        let hasName = !first.trimmingCharacters(in: .whitespaces).isEmpty &&
                      !last.trimmingCharacters(in: .whitespaces).isEmpty
        return hasName
            && emailCheck.isValid
            && phoneCheck.isValid
            && hasAgent != nil
            && termsAccepted
    }

    // Phone formatting — strips non-digits, caps at 10, formats as
    // "(555) 555-1234". Called from onChange so the field re-renders on
    // every keystroke and the guest sees the shape build up immediately.
    private func formatPhone(_ input: String) -> String {
        let digits = input.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }
        let s = String(String.UnicodeScalarView(digits.prefix(10)))
        let n = s.count
        switch n {
        case 0:     return ""
        case 1...3: return "(\(s)"
        case 4...6:
            let area = s.prefix(3); let mid = s.dropFirst(3)
            return "(\(area)) \(mid)"
        default:
            let area = s.prefix(3); let mid = s.dropFirst(3).prefix(3); let end = s.dropFirst(6)
            return "(\(area)) \(mid)-\(end)"
        }
    }

    // Email regex used for offline / fail-open client checks. The backend
    // MX lookup is the real source of truth, but if it can't be reached
    // we don't want to block the kiosk — so we fall through to this regex
    // + TLD whitelist and accept the value.
    private static let emailRegex = try! NSRegularExpression(
        pattern: #"^[A-Z0-9._%+-]+@[A-Z0-9-]+(\.[A-Z0-9-]+)*\.([A-Z]{2,})$"#,
        options: [.caseInsensitive]
    )

    // Whitelist of TLDs we'll accept without backend MX verification.
    // Covers the long tail of real-world emails. Anything else (e.g.
    // "dd.dd") gets rejected at the client so the guest can't slip by
    // when the verifier is down.
    private static let knownTLDs: Set<String> = [
        // generic
        "com", "net", "org", "edu", "gov", "mil", "int",
        "info", "biz", "name", "pro", "aero", "coop", "museum",
        "co", "io", "ai", "app", "dev", "me", "tv", "fm",
        "xyz", "online", "store", "site", "tech", "blog", "shop",
        "design", "art", "club", "live", "news", "today", "world", "life",
        "group", "agency", "page", "link", "fun", "top", "vip", "work", "zone",
        "plus", "social", "network", "media", "digital", "cloud", "services",
        "solutions", "consulting", "ventures", "capital", "studio", "house",
        "realty", "estate", "homes", "properties", "realtor",
        // country codes that show up in US open-house context
        "us", "uk", "ca", "au", "de", "fr", "jp", "cn", "in", "br",
        "ru", "mx", "es", "it", "nl", "se", "no", "dk", "fi", "pl",
        "kr", "tw", "hk", "sg", "th", "vn", "ph", "my", "id",
        "ar", "cl", "pe", "co", "ng", "ke", "za", "il", "ae", "tr",
        "gr", "pt", "ie", "be", "ch", "at", "cz", "sk", "hu", "ro",
        "nz", "is", "mt", "cy", "lu", "lt", "lv", "ee",
    ]

    private static func looksLikeEmail(_ s: String) -> Bool {
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        guard emailRegex.firstMatch(in: s, range: range) != nil else { return false }
        // Pull the TLD (after the last dot) and check it's something real.
        // This is what catches "something@dd.dd" — "dd" isn't a TLD.
        guard let lastDot = s.lastIndex(of: ".") else { return false }
        let tld = s[s.index(after: lastDot)...].lowercased()
        return knownTLDs.contains(tld)
    }

    private func scheduleEmailCheck(_ value: String) {
        emailDebounce?.cancel()
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            emailCheck = .idle
            return
        }
        if !Self.looksLikeEmail(trimmed) {
            // Show the live red state immediately on obvious-junk input so
            // the guest gets a hint without waiting for the backend.
            emailCheck = .checking
        } else {
            emailCheck = .checking
        }
        emailDebounce = Task {
            try? await Task.sleep(for: .milliseconds(500))
            if Task.isCancelled { return }
            do {
                let result = try await APIClient.shared.verifyContact(email: trimmed)
                if Task.isCancelled { return }
                await MainActor.run {
                    if let check = result.email {
                        emailCheck = check.valid
                            ? .valid(nil)
                            : .invalid(check.reason ?? "Invalid email")
                    } else {
                        // Backend didn't echo the field — fall back to
                        // client regex so we don't get stuck "checking".
                        emailCheck = Self.looksLikeEmail(trimmed)
                            ? .valid(nil)
                            : .invalid("Doesn't look like an email")
                    }
                }
            } catch {
                if Task.isCancelled { return }
                // Backend unreachable — fail OPEN: client regex decides.
                // No "couldn't reach verifier" hint shown to the guest.
                await MainActor.run {
                    emailCheck = Self.looksLikeEmail(trimmed)
                        ? .valid(nil)
                        : .invalid("Doesn't look like an email")
                }
            }
        }
    }

    private func schedulePhoneCheck(_ value: String) {
        phoneDebounce?.cancel()
        let digits = value.filter(\.isNumber)
        if digits.isEmpty {
            phoneCheck = .idle
            return
        }
        if digits.count < 10 {
            phoneCheck = .checking
            return
        }
        phoneCheck = .checking
        phoneDebounce = Task {
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }
            do {
                let result = try await APIClient.shared.verifyContact(phone: value)
                if Task.isCancelled { return }
                await MainActor.run {
                    if let check = result.phone {
                        phoneCheck = check.valid ? .valid(nil) : .invalid(check.reason ?? "Invalid phone")
                    } else {
                        phoneCheck = digits.count == 10 ? .valid(nil) : .invalid("Need 10 digits")
                    }
                }
            } catch {
                if Task.isCancelled { return }
                // Backend unreachable — accept any 10-digit number.
                await MainActor.run {
                    phoneCheck = digits.count == 10 ? .valid(nil) : .invalid("Need 10 digits")
                }
            }
        }
    }

    @MainActor
    private func submit() async {
        guard canSubmit else { return }
        submitting = true
        defer { submitting = false }
        submitError = nil

        let fullName = (first.trimmingCharacters(in: .whitespaces) + " " +
                        last.trimmingCharacters(in: .whitespaces))
                       .trimmingCharacters(in: .whitespaces)
        var guest = VisitorInput(
            name: fullName,
            email: email.trimmingCharacters(in: .whitespaces),
            phone: phone
        )
        guest.hasAgent = hasAgent
        // Combined consent maps to both flags for the backend, since the
        // server schema still tracks them separately (and we want the
        // honest legal record that both were granted, even if the UI
        // bundled them).
        guest.marketingConsent = termsAccepted
        guest.recordingConsent = termsAccepted
        store.pendingKioskGuests.append(guest)

        // Persist the lead to the backend immediately so the agent has the
        // contact info even if no audio session ever gets recorded (the
        // original bug — pendingKioskGuests only became leads during the
        // post-recording match step, which never fires without a recording).
        // We still keep them in pendingKioskGuests so the matcher can link
        // them to speakers IF a recording does happen.
        let manualAddress = listing?.address
        Task.detached(priority: .background) {
            do {
                _ = try await APIClient.shared.createManualLead(
                    name: fullName,
                    email: guest.email,
                    phone: guest.phone,
                    tag: "buyer",
                    address: manualAddress
                )
            } catch {
                // Silent — the guest already saw "thanks for signing in".
                // If the backend is down, pendingKioskGuests still holds
                // the data; the agent can also re-enter via ManualLeadSheet.
                Log.warn("Manual lead from kiosk failed: \(error.localizedDescription)")
            }
        }

        // Show the success overlay, clear the form WHILE it's still up so
        // the next guest sees an empty form when the overlay dismisses.
        // Previously we cleared after dismiss, so the guest would briefly
        // see the prior guest's data clear out in front of them.
        withAnimation(.easeOut(duration: 0.3)) { showSuccess = true }
        try? await Task.sleep(for: .milliseconds(2000))
        clearForm()
        try? await Task.sleep(for: .milliseconds(300))
        withAnimation(.easeInOut(duration: 0.45)) { showSuccess = false }
    }

    private func clearForm() {
        first = ""; last = ""; email = ""; phone = ""
        hasAgent = .no
        termsAccepted = false
        emailCheck = .idle
        phoneCheck = .idle
        submitError = nil
        focused = .first
    }
}

// Single text field row for the kiosk. Pulled out as its own View struct
// so SwiftUI can diff per-field instead of rebuilding the entire form
// pane when any one field's text changes — that was the source of the
// keystroke lag.
private struct KioskField: View {
    let label: String
    @Binding var text: String
    let keyboard: UIKeyboardType
    let content: UITextContentType
    let isFocused: Bool
    let indicator: IPadKiosk.ValidationState?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isFocused ? FoyerTheme.gold : FoyerTheme.textDim)
                Spacer()
                indicatorView
            }
            TextField("", text: $text)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(FoyerTheme.cream)
                .tint(FoyerTheme.gold)
                .textContentType(content)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                .autocorrectionDisabled()
                .padding(.vertical, 14).padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(white: 0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(strokeColor, lineWidth: 1)
                )
        }
    }

    private var strokeColor: Color {
        if case .invalid = indicator { return FoyerTheme.terracotta.opacity(0.7) }
        if case .valid = indicator { return FoyerTheme.sage.opacity(0.5) }
        if isFocused { return FoyerTheme.gold.opacity(0.6) }
        return .clear
    }

    @ViewBuilder
    private var indicatorView: some View {
        switch indicator {
        case .none, .idle:
            EmptyView()
        case .checking:
            ProgressView().scaleEffect(0.55).tint(FoyerTheme.textDim)
        case .valid(let hint):
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(FoyerTheme.sage)
                if let hint {
                    Text(hint)
                        .font(.system(size: 10))
                        .foregroundStyle(FoyerTheme.textDim)
                }
            }
        case .invalid(let reason):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(FoyerTheme.terracotta)
                Text(reason)
                    .font(.system(size: 10))
                    .foregroundStyle(FoyerTheme.terracotta)
            }
        }
    }
}

// Fullscreen "Thanks, Aleks" celebration shown after Done is tapped. Uses
// the same disc + checkmark vocabulary as the welcome overlay so the app
// feels like one piece.
private struct KioskSuccessOverlay: View {
    let name: String

    @State private var ringScale: CGFloat = 0.5
    @State private var ringOpacity: Double = 0
    @State private var discScale: CGFloat = 0
    @State private var checkProgress: CGFloat = 0
    @State private var textOpacity: Double = 0

    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 26) {
                ZStack {
                    Circle()
                        .stroke(FoyerTheme.sage.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 180, height: 180)
                        .scaleEffect(ringScale)
                        .opacity(ringOpacity)
                    Circle()
                        .fill(FoyerTheme.sage)
                        .frame(width: 96, height: 96)
                        .scaleEffect(discScale)
                        .shadow(color: FoyerTheme.sage.opacity(0.35), radius: 24, y: 8)
                    Check()
                        .trim(from: 0, to: checkProgress)
                        .stroke(FoyerTheme.inkOnGold,
                                style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                        .frame(width: 44, height: 36)
                        .opacity(discScale > 0.6 ? 1 : 0)
                }
                .frame(height: 200)
                VStack(spacing: 4) {
                    Text("Thanks for signing in,")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(FoyerTheme.creamDim)
                    Text("\(name)!")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(FoyerTheme.cream)
                        .tracking(-0.8)
                }
                .opacity(textOpacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeOut(duration: 0.85)) {
                ringScale = 1.25
                ringOpacity = 1
            }
            withAnimation(.easeOut(duration: 1.3).delay(0.15)) {
                ringScale = 1.8
                ringOpacity = 0
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.62).delay(0.18)) {
                discScale = 1
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.5)) {
                checkProgress = 1
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.7)) {
                textOpacity = 1
            }
        }
    }
}

// MARK: – Leads (ChatGPT/Claude — single-column reading)

// Compact left list (visitor name + tag + status), wide reading column on
// the right with the visitor's profile, what the AI heard, signals as
// inline chips, and the drafted follow-up as an editable-feeling block.
// Real data: APIClient.getSession(id) populates visitors;
// updateLeadState(...) flips status optimistically.
private struct IPadLeads: View {
    let store: SessionStore
    // Optional pre-filter: when the agent taps a recent session in the
    // side rail, we land here with that session selected. nil = "All".
    var initialFilter: String? = nil

    // A single row in the unified Leads inbox: one VisitorResult + the
    // session it came from. We hold full Session refs (not just summaries)
    // because the detail view needs the session id and address to send
    // follow-ups and surface the right metadata.
    struct LeadRow: Identifiable {
        let visitor: VisitorResult
        let session: Session
        var id: String { "\(session.id):\(visitor.id)" }
    }

    @State private var allLeads: [LeadRow] = []
    @State private var loading = false
    @State private var activeId: String?
    @State private var filterSessionId: String?
    @State private var showAddLead: Bool = false
    @State private var didApplyInitialFilter: Bool = false

    // Send-via-Gmail state.
    @State private var sendingId: String?
    @State private var sendError: String?
    @State private var showGmailConnect: Bool = false

    // Delete-lead state.
    @State private var pendingDeleteLead: LeadRow?
    @State private var deletingLead: Bool = false
    @State private var deleteLeadError: String?

    // Send-success toast — shown above the detail pane for ~2s after a
    // Gmail send succeeds, so the agent gets a clear "yes that went out"
    // signal that doesn't depend on noticing the small status pill flip.
    @State private var sentToast: String?
    @State private var toastTask: Task<Void, Never>?

    // CRM panel state — per-lead draft text for new notes/tasks so the
    // agent's typing persists when they switch leads and back. Keyed by
    // LeadRow.id (which is session_id + visitor_id).
    @State private var newNoteText: [String: String] = [:]
    @State private var newTaskText: [String: String] = [:]
    @State private var crmError: String?

    // Schedule-send sheet — non-nil means a date picker is up for that lead.
    @State private var scheduleForLead: LeadRow?

    // Draft editor — always editable. The DraftEditorPane child view owns
    // its text + autosave state so per-keystroke re-renders don't cascade
    // through the parent's lead list / sidebar.

    // Edit-contact sheet — when non-nil, a modal lets the agent fix the
    // lead's display name / email / phone (often wrong off diarization or
    // the kiosk form).
    @State private var editingContactFor: LeadRow?

    // Leads AI agent — sheet at the top of the Leads tab. The agent can ask
    // free-text questions ("how many buyers do I have?") or describe a
    // batch action ("send our $2,500 buyer credit blast to all buyers");
    // server returns either an answer or a plan we render with one bulk
    // confirmation.
    @State private var showLeadsAgent: Bool = false

    // Per-lead expansion state for the "What we heard" summary block — keyed
    // by LeadRow.id. Default is collapsed (3-line clamp) so the agent lands
    // on the draft + actions without scrolling past a wall of text.
    @State private var expandedSummaries: Set<String> = []

    // Score-explainer popover anchor inside the detail header. SwiftUI
    // popovers are per-view; the boolean lives on the parent so the
    // header sub-view can read/toggle it without losing identity on
    // re-render.
    @State private var showScoreInfo: Bool = false

    private var filteredLeads: [LeadRow] {
        guard let id = filterSessionId else { return allLeads }
        return allLeads.filter { $0.session.id == id }
    }

    private var current: LeadRow? {
        if let id = activeId, let m = allLeads.first(where: { $0.id == id }) { return m }
        return filteredLeads.first
    }

    private var sessionsForFilter: [Session] {
        var seen = Set<String>()
        var out: [Session] = []
        for row in allLeads where !seen.contains(row.session.id) {
            seen.insert(row.session.id)
            out.append(row.session)
        }
        return out
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 340)
                .background(Color(white: 0.03))
                .overlay(alignment: .trailing) {
                    Rectangle().fill(FoyerTheme.hairline).frame(width: 1)
                }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .overlay(alignment: .top) {
                    if let toast = sentToast {
                        sentToastView(toast)
                            .padding(.top, 24)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: sentToast)
        }
        .task { await load() }
        .onAppear {
            if !didApplyInitialFilter, let id = initialFilter {
                filterSessionId = id
                didApplyInitialFilter = true
            }
        }
        .onChange(of: initialFilter) { _, newValue in
            // Re-apply when the side rail picks a different recent session.
            if let id = newValue { filterSessionId = id; activeId = nil }
        }
        .sheet(isPresented: $showGmailConnect) {
            GmailConnectSheet(
                onConnected: { connected in
                    showGmailConnect = false
                    if connected, let row = current {
                        Task { await markSent(row.visitor, session: row.session) }
                    }
                },
                onCancel: { showGmailConnect = false }
            )
        }
        .sheet(isPresented: $showAddLead) {
            ManualLeadSheet(
                onCancel: { showAddLead = false },
                onCreated: { _ in
                    showAddLead = false
                    Task { await load() }
                }
            )
        }
        .sheet(item: $scheduleForLead) { row in
            ScheduleSendSheet(
                row: row,
                onCancel: { scheduleForLead = nil },
                onScheduled: { state in
                    apply(state, to: row)
                    scheduleForLead = nil
                    showToast("Scheduled for \(row.visitor.displayName.split(separator: " ").first.map(String.init) ?? row.visitor.displayName)")
                }
            )
        }
        .sheet(item: $editingContactFor) { row in
            EditContactSheet(
                row: row,
                onCancel: { editingContactFor = nil },
                onSaved: { updated in
                    apply(visitor: updated, to: row)
                    editingContactFor = nil
                    showToast("Contact updated")
                }
            )
        }
        .sheet(isPresented: $showLeadsAgent) {
            LeadsAgentSheet(
                onDismiss: { showLeadsAgent = false },
                onCompleted: { sentCount in
                    showLeadsAgent = false
                    if sentCount > 0 {
                        showToast("Sent \(sentCount) email\(sentCount == 1 ? "" : "s")")
                        Task { await load() }
                    }
                }
            )
        }
        .alert(
            "Delete this lead?",
            isPresented: Binding(
                get: { pendingDeleteLead != nil },
                set: { if !$0 { pendingDeleteLead = nil } }
            ),
            presenting: pendingDeleteLead
        ) { row in
            Button("Cancel", role: .cancel) { pendingDeleteLead = nil }
            Button("Delete permanently", role: .destructive) {
                Task { await performDeleteLead(row) }
            }
        } message: { row in
            Text("Permanently remove \(row.visitor.displayName) from this session. The rest of the session and its other leads are kept. This can't be undone.")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Leads")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(FoyerTheme.cream)
                        .tracking(-0.4)
                    Spacer()
                    Button { showAddLead = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(FoyerTheme.inkOnGold)
                            .frame(width: 30, height: 30)
                            .background(FoyerTheme.gold, in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                askAILauncher

                if !sessionsForFilter.isEmpty {
                    sessionFilterMenu
                }
            }
            .padding(.horizontal, 22).padding(.top, 36).padding(.bottom, 14)

            if loading && allLeads.isEmpty {
                Spacer()
                FoyerLoadingView(size: 96, cornerRadius: 14)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else if filteredLeads.isEmpty {
                emptyList
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredLeads) { row in
                            Button { activeId = row.id } label: { leadRow(row) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                }
                .refreshable { await load() }
            }
        }
    }

    private var askAILauncher: some View {
        Button { showLeadsAgent = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FoyerTheme.gold)
                Text("Ask your inbox anything…")
                    .font(.system(size: 13))
                    .foregroundStyle(FoyerTheme.creamDim)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(FoyerTheme.textMuted)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(white: 0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(FoyerTheme.gold.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var sessionFilterMenu: some View {
        Menu {
            Button {
                filterSessionId = nil
                activeId = nil
            } label: {
                HStack {
                    Text("All open houses")
                    if filterSessionId == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }
            Divider()
            ForEach(sessionsForFilter, id: \.id) { s in
                Button {
                    filterSessionId = s.id
                    activeId = nil
                } label: {
                    HStack {
                        Text(s.address ?? "Open house")
                        if filterSessionId == s.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 10, weight: .semibold))
                Text(filterLabel)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(FoyerTheme.creamDim)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Color.white.opacity(0.06), in: Capsule())
        }
    }

    private var filterLabel: String {
        guard let id = filterSessionId,
              let s = sessionsForFilter.first(where: { $0.id == id }) else {
            return "All leads (\(allLeads.count))"
        }
        return s.address ?? "Selected open house"
    }

    private var emptyList: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(FoyerTheme.creamDim.opacity(0.35))
            Text("No leads yet")
                .font(.system(size: 14))
                .foregroundStyle(FoyerTheme.textDim)
            Text("Record a session or add one manually.")
                .font(.system(size: 12))
                .foregroundStyle(FoyerTheme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func leadRow(_ row: LeadRow) -> some View {
        let v = row.visitor
        let active = (activeId ?? filteredLeads.first?.id) == row.id
        let lastContactedAt = lastContactedDate(v.leadState)
        return HStack(alignment: .top, spacing: 12) {
            Text(v.displayInitials)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(FoyerTheme.gold)
                .frame(width: 36, height: 36)
                .background(FoyerTheme.bgElev, in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                // Name + score on the same baseline so the column reads as
                // a quick triage list. Score reads as "X / 100" so the
                // number isn't ambiguous on its own.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(v.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FoyerTheme.cream)
                        .lineLimit(1)
                    Spacer()
                    HStack(spacing: 2) {
                        Text("\(v.analysis.score)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(v.analysis.score >= 80 ? FoyerTheme.gold : FoyerTheme.creamDim)
                        Text("/100")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(FoyerTheme.textMuted)
                    }
                }
                // Address line — which open house this lead came from. Once
                // we wire up the MLS API we'll turn this into a chevron-able
                // link to the listing detail.
                if let addr = row.session.address, !addr.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "house")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(FoyerTheme.gold.opacity(0.7))
                        Text(addr)
                            .font(.system(size: 11))
                            .foregroundStyle(FoyerTheme.creamDim)
                            .lineLimit(1)
                    }
                }
                // Contact line — surface email or phone in the list so the
                // agent can see at a glance whether the lead is reachable
                // without having to open the detail pane. Inlined (rather
                // than calling primaryContact) because the surrounding
                // view body is already complex enough that SwiftUI's type
                // checker chokes on the helper call.
                let contactIcon: String? = !v.visitor.email.isEmpty ? "envelope"
                    : (!v.visitor.phone.isEmpty ? "phone" : nil)
                let contactText: String = !v.visitor.email.isEmpty ? v.visitor.email
                    : v.visitor.phone
                if let icon = contactIcon {
                    HStack(spacing: 4) {
                        Image(systemName: icon)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(FoyerTheme.creamDim.opacity(0.7))
                        Text(contactText)
                            .font(.system(size: 11))
                            .foregroundStyle(FoyerTheme.creamDim)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                // Tag + state pill row.
                HStack(spacing: 6) {
                    Circle()
                        .fill(tagColor(v.analysis.tagToken))
                        .frame(width: 5, height: 5)
                    Text(v.analysis.tag)
                        .font(.system(size: 11))
                        .foregroundStyle(FoyerTheme.textDim)
                    if let state = v.leadState, state.status != .drafted {
                        Text("·")
                            .font(.system(size: 11))
                            .foregroundStyle(FoyerTheme.textMuted)
                        Text(state.status.rawValue.capitalized)
                            .font(.system(size: 11))
                            .foregroundStyle(FoyerTheme.textDim)
                    }
                }
                // Created / last-contacted footer. Two facts the agent needs
                // at a glance: how fresh is this lead, and have I followed up?
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                        .foregroundStyle(FoyerTheme.textMuted)
                    Text("Added \(relativeTime(row.session.createdAt))")
                        .font(.system(size: 10))
                        .foregroundStyle(FoyerTheme.textMuted)
                    Text("·")
                        .font(.system(size: 10))
                        .foregroundStyle(FoyerTheme.textMuted)
                    if let when = lastContactedAt {
                        Text("Contacted \(relativeTime(when))")
                            .font(.system(size: 10))
                            .foregroundStyle(FoyerTheme.sage)
                    } else {
                        Text("Never contacted")
                            .font(.system(size: 10))
                            .foregroundStyle(FoyerTheme.terracotta.opacity(0.85))
                    }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(active ? Color.white.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    // Pick the most recent send timestamp for this lead. Lead state stores
    // every successful send in `sent_emails`, and we ALSO bump `sent_at`
    // when a manual mark-as-sent fires from the visitor-state endpoint, so
    // we check both and take whichever is newer.
    private func lastContactedDate(_ state: LeadState?) -> Date? {
        guard let state else { return nil }
        var candidates: [Date] = []
        if let sentAt = state.sentAt, let d = parseISO(sentAt) {
            candidates.append(d)
        }
        for email in state.sentEmails ?? [] {
            if let sentAt = email.sentAt, let d = parseISO(sentAt) {
                candidates.append(d)
            }
        }
        return candidates.max()
    }

    private func parseISO(_ s: String) -> Date? {
        ISO8601DateFormatter.fractionalSeconds.date(from: s)
            ?? ISO8601DateFormatter().date(from: s)
    }

    // Overload for the relativeTime helper that lives further down the file —
    // accepts a pre-parsed Date so the row footer doesn't have to convert
    // back to an ISO string just to feed the existing String-based path.
    private func relativeTime(_ d: Date) -> String {
        let delta = max(0, Date().timeIntervalSince(d))
        if delta < 60 { return "just now" }
        if delta < 3600 { return "\(Int(delta / 60))m ago" }
        if delta < 86_400 { return "\(Int(delta / 3600))h ago" }
        let days = Int(delta / 86_400)
        if days < 14 { return "\(days)d ago" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }

    private func tagColor(_ token: String) -> Color {
        switch token {
        case "buyer":   return FoyerTheme.gold
        case "seller":  return FoyerTheme.terracotta
        case "browser": return FoyerTheme.sage
        default:        return FoyerTheme.creamDim
        }
    }

    // Pick the best contact line for the list row. Email wins because it's
    // the channel we actually send through; phone is the fallback so the
    // agent at least sees they have SOMETHING to reach this person on.
    private func primaryContact(_ v: VisitorResult) -> (icon: String, text: String)? {
        if !v.visitor.email.isEmpty { return ("envelope", v.visitor.email) }
        if !v.visitor.phone.isEmpty { return ("phone", v.visitor.phone) }
        return nil
    }

    @ViewBuilder
    private var content: some View {
        if let row = current {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 36) {
                    visitorHeader(row)
                    summary(row)
                    followup(row.visitor, session: row.session)
                    scheduledSection(row)
                    historySection(row)
                    notesSection(row)
                    tasksSection(row)
                    if let crmError {
                        Text(crmError)
                            .font(.system(size: 12))
                            .foregroundStyle(FoyerTheme.terracotta)
                    }
                    if let deleteLeadError {
                        Text(deleteLeadError)
                            .font(.system(size: 12))
                            .foregroundStyle(FoyerTheme.terracotta)
                    }
                    Spacer().frame(height: 80)
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 56).padding(.top, 56)
            }
            .refreshable { await load() }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if loading {
            FoyerLoadingView(size: 120, cornerRadius: 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            emptyContent
        }
    }

    private var emptyContent: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(FoyerTheme.creamDim.opacity(0.4))
            Text("No leads to show yet.")
                .font(.system(size: 14))
                .foregroundStyle(FoyerTheme.textDim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func visitorHeader(_ row: LeadRow) -> some View {
        let v = row.visitor
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                Text(v.displayInitials)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(FoyerTheme.gold)
                    .frame(width: 64, height: 64)
                    .background(FoyerTheme.bgElev, in: Circle())
                VStack(alignment: .leading, spacing: 6) {
                    Text(v.displayName)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(FoyerTheme.cream)
                        .tracking(-0.5)
                    HStack(spacing: 8) {
                        Text(v.analysis.tag)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(tagColor(v.analysis.tagToken))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(
                                Capsule().fill(tagColor(v.analysis.tagToken).opacity(0.12))
                            )
                        Button { showScoreInfo.toggle() } label: {
                            HStack(spacing: 4) {
                                Text("Score \(v.analysis.score) / 100")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(FoyerTheme.creamDim)
                                Image(systemName: "info.circle")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(FoyerTheme.textMuted)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(Color.white.opacity(0.05)))
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showScoreInfo, arrowEdge: .top) {
                            scoreInfoPopover(v.analysis.score)
                        }
                        if let state = v.leadState, state.status != .drafted {
                            statusPill(state.status)
                        }
                    }
                }
                Spacer()
                Button { pendingDeleteLead = row } label: {
                    HStack(spacing: 6) {
                        if deletingLead {
                            ProgressView().scaleEffect(0.7).tint(FoyerTheme.terracotta)
                        } else {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        Text("Delete")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(FoyerTheme.terracotta)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(FoyerTheme.terracotta.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(deletingLead)
            }
            HStack(spacing: 18) {
                if !v.visitor.email.isEmpty {
                    contactLine(icon: "envelope", text: v.visitor.email)
                }
                if !v.visitor.phone.isEmpty {
                    contactLine(icon: "phone", text: v.visitor.phone)
                }
                Button {
                    editingContactFor = row
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "pencil")
                            .font(.system(size: 10, weight: .semibold))
                        Text(v.visitor.email.isEmpty && v.visitor.phone.isEmpty
                             ? "Add contact info"
                             : "Edit")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(FoyerTheme.creamDim)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func contactLine(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11))
            Text(text).font(.system(size: 13))
        }
        .foregroundStyle(FoyerTheme.creamDim)
    }

    // Explains what the 0–100 lead score means. Reasoning behind the
    // current score band is included so the agent can sanity-check the
    // model's call without leaving the detail pane.
    private func scoreInfoPopover(_ score: Int) -> some View {
        let band: (label: String, color: Color, blurb: String) = {
            switch score {
            case 80...:
                return ("Hot lead",
                        FoyerTheme.gold,
                        "Strong buying or selling signals — likely a near-term opportunity.")
            case 50..<80:
                return ("Warm lead",
                        FoyerTheme.sage,
                        "Some intent signals but key details (timeline, budget, pre-approval) are missing.")
            default:
                return ("Cold lead",
                        FoyerTheme.terracotta,
                        "Minimal engagement or unclear intent — likely a casual browser.")
            }
        }()
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("\(score) / 100")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(band.color)
                Text(band.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(band.color)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(band.color.opacity(0.14)))
            }
            Text(band.blurb)
                .font(.system(size: 12))
                .foregroundStyle(FoyerTheme.creamDim)
                .lineSpacing(3)
            Divider().background(FoyerTheme.hairline)
            Text("How it's scored")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(FoyerTheme.textDim)
            Text("Foyer's AI rates each lead 0–100 by analyzing what they said during the open house: budget mentions, timeline, pre-approval, motivation, and engagement depth. Higher means more buying or selling intent.")
                .font(.system(size: 12))
                .foregroundStyle(FoyerTheme.creamDim)
                .lineSpacing(3)
        }
        .padding(16)
        .frame(width: 320)
        .background(Color(white: 0.07))
    }

    private func summary(_ row: LeadRow) -> some View {
        let v = row.visitor
        let expanded = expandedSummaries.contains(row.id)
        return VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    if expanded { expandedSummaries.remove(row.id) }
                    else { expandedSummaries.insert(row.id) }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("What we heard")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(FoyerTheme.textDim)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(FoyerTheme.textMuted)
                    Spacer()
                    if !expanded {
                        Text("Show more")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(FoyerTheme.creamDim)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text(v.analysis.summary)
                .font(.system(size: 15))
                .foregroundStyle(FoyerTheme.cream)
                .lineSpacing(5)
                .lineLimit(expanded ? nil : 3)
            if expanded && !v.analysis.signals.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(v.analysis.signals, id: \.self) { s in
                        Text(s)
                            .font(.system(size: 12))
                            .foregroundStyle(FoyerTheme.creamDim)
                            .padding(.horizontal, 11).padding(.vertical, 5)
                            .background(
                                Capsule().fill(Color(white: 0.07))
                            )
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private func draftBodyFor(_ row: LeadRow) -> String {
        row.visitor.leadState?.draftOverride?.body
            ?? row.visitor.analysis.followUpDraft
    }

    private func followup(_ v: VisitorResult, session: Session) -> some View {
        let row = LeadRow(visitor: v, session: session)
        let isOverridden = (v.leadState?.draftOverride?.body ?? "").isEmpty == false
        let currentBody = draftBodyFor(row)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Drafted follow-up")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(FoyerTheme.textDim)
                if isOverridden {
                    Text("Edited")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(FoyerTheme.gold)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(FoyerTheme.gold.opacity(0.14)))
                }
                Spacer()
                if isOverridden {
                    Button {
                        Task { await resetDraft(for: row) }
                    } label: {
                        Text("Reset to AI")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(FoyerTheme.creamDim)
                    }
                    .buttonStyle(.plain)
                }
                Text(channel(v))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FoyerTheme.textMuted)
            }

            // Always-editable: the editor owns its own text state so each
            // keystroke only re-renders the editor (not the whole Leads
            // screen). `.id(row.id)` remounts on lead switch so a fresh row
            // starts from its server-side body instead of stale state.
            DraftEditorPane(
                initialText: currentBody,
                sessionId: row.session.id,
                visitorName: row.visitor.visitor.name,
                visitorSpeaker: row.visitor.visitor.speaker,
                onAutosave: { text in
                    await autosaveDraft(for: row, body: text)
                }
            )
            .id(row.id)

            HStack(spacing: 10) {
                let state = v.leadState?.status ?? .drafted
                if state == .sent {
                    stateAction("Mark replied", icon: "checkmark.circle", color: FoyerTheme.sage) {
                        Task { await transition(v, session: session, to: .replied) }
                    }
                } else if state == .drafted {
                    stateAction("Mark replied", icon: "checkmark.circle", color: FoyerTheme.sage) {
                        Task { await transition(v, session: session, to: .replied) }
                    }
                }
                if state != .archived {
                    stateAction("Archive", icon: "archivebox", color: FoyerTheme.creamDim) {
                        Task { await transition(v, session: session, to: .archived) }
                    }
                } else {
                    stateAction("Restore", icon: "tray.and.arrow.up", color: FoyerTheme.gold) {
                        Task { await transition(v, session: session, to: .drafted) }
                    }
                }
                Spacer()
                let sending = (sendingId == v.id)
                Button {
                    if let row = current { scheduleForLead = row }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 11, weight: .medium))
                        Text("Schedule")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(FoyerTheme.creamDim)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Color(white: 0.07), in: Capsule())
                }
                .disabled(sending)
                .buttonStyle(.plain)
                Button { Task { await markSent(v, session: session) } } label: {
                    HStack(spacing: 8) {
                        if sending {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(FoyerTheme.inkOnGold)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        Text(sending ? "Sending…" : "Send")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(FoyerTheme.inkOnGold)
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    .background(FoyerTheme.gold, in: Capsule())
                }
                .disabled(sending)
                .buttonStyle(.plain)
            }
            .padding(.top, 2)

            if let sendError {
                Text(sendError)
                    .font(.system(size: 12))
                    .foregroundStyle(FoyerTheme.terracotta)
                    .padding(.top, 4)
            }
        }
    }

    private func channel(_ v: VisitorResult) -> String {
        if !v.visitor.email.isEmpty { return "Email" }
        if !v.visitor.phone.isEmpty { return "SMS" }
        return "—"
    }

    private func stateAction(_ text: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11, weight: .medium))
                Text(text).font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(color.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func transition(_ v: VisitorResult, session: Session, to status: LeadState.Status) async {
        do {
            let newState = try await APIClient.shared.updateLeadState(
                sessionId: session.id,
                visitorName: v.visitor.name,
                visitorSpeaker: v.visitor.speaker,
                status: status,
                snoozedUntil: nil
            )
            if let idx = allLeads.firstIndex(where: { $0.visitor.id == v.id && $0.session.id == session.id }) {
                var row = allLeads[idx]
                var visitor = row.visitor
                visitor.leadState = newState
                row = LeadRow(visitor: visitor, session: row.session)
                allLeads[idx] = row
            }
        } catch {
            sendError = "Couldn't update: \(error.localizedDescription)"
        }
    }

    private func ghost(_ text: String, icon: String) -> some View {
        Button { } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11, weight: .medium))
                Text(text).font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(FoyerTheme.creamDim)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Color(white: 0.07), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func statusPill(_ status: LeadState.Status) -> some View {
        let (text, color): (String, Color) = {
            switch status {
            case .drafted:  return ("Drafted", FoyerTheme.gold)
            case .sent:     return ("Sent", FoyerTheme.sage)
            case .replied:  return ("Replied", FoyerTheme.sage)
            case .archived: return ("Archived", FoyerTheme.creamDim)
            }
        }()
        return Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    // Fetch every recorded session in parallel and flatten the visitors
    // into a single inbox. The session-summary list (cheap) tells us which
    // ids to fetch; per-session detail fetches happen concurrently. This
    // is N round trips on the cold path — fine for the agent's own list
    // (typically dozens). A flat /leads endpoint can replace this later.
    private func load() async {
        await MainActor.run { loading = true }
        defer { Task { @MainActor in loading = false } }
        await store.refreshSessions()
        // Include BOTH "recorded" sessions and "manual" leads — they're
        // all leads from the agent's perspective. The original filter
        // hid manually-added leads (and kiosk sign-ins, since those are
        // also stored as manual leads), making them appear to vanish.
        let summaries = store.pastSessions
        let collected: [LeadRow] = await withTaskGroup(of: [LeadRow]?.self) { group in
            for summary in summaries {
                group.addTask {
                    guard let session = try? await APIClient.shared.getSession(id: summary.id),
                          let visitors = session.result?.visitors else { return nil }
                    return visitors.map { LeadRow(visitor: $0, session: session) }
                }
            }
            var rows: [LeadRow] = []
            for await maybe in group {
                if let chunk = maybe { rows.append(contentsOf: chunk) }
            }
            return rows
        }
        await MainActor.run {
            self.allLeads = collected.sorted { lhs, rhs in
                (lhs.session.createdAt ?? "") > (rhs.session.createdAt ?? "")
            }
            if activeId == nil { activeId = self.filteredLeads.first?.id }
        }
    }

    @MainActor
    private func performDeleteLead(_ row: LeadRow) async {
        deletingLead = true
        deleteLeadError = nil
        defer { deletingLead = false; pendingDeleteLead = nil }
        // Resolve the visitor's index inside its session — the backend
        // identifies leads by their position in result.visitors. Fall back
        // to load() if we can't find the index (stale local state).
        guard let result = row.session.result,
              let idx = result.visitors.firstIndex(where: { $0.id == row.visitor.id }) else {
            deleteLeadError = "Couldn't locate this lead."
            return
        }
        do {
            try await APIClient.shared.deleteVisitor(
                sessionId: row.session.id,
                visitorIndex: idx
            )
            allLeads.removeAll { $0.id == row.id }
            if activeId == row.id { activeId = filteredLeads.first?.id }
        } catch {
            deleteLeadError = error.localizedDescription
        }
    }

    private func markSent(_ v: VisitorResult, session: Session) async {
        await MainActor.run { sendingId = v.id; sendError = nil }
        defer { Task { @MainActor in sendingId = nil } }
        do {
            let result = try await APIClient.shared.sendVisitorEmail(
                sessionId: session.id,
                visitorName: v.visitor.name,
                visitorSpeaker: v.visitor.speaker
            )
            // Best-effort push to Follow Up Boss if the agent has connected.
            // FUB failures don't roll back the "sent" flip — the email already
            // went out, so we just surface a soft warning toast.
            var fubWarning: String? = nil
            if FUBCredential.isConnected {
                do {
                    var updatedVisitor = v
                    updatedVisitor.leadState = result.leadState
                    _ = try await APIClient.shared.fubPushLead(
                        visitor: updatedVisitor,
                        sessionAddress: session.address,
                        snoozedUntil: result.leadState?.snoozedUntilDate
                    )
                } catch {
                    fubWarning = "Sent — but FUB push failed: \(error.localizedDescription)"
                }
            }
            await MainActor.run {
                let newState = result.leadState
                    ?? LeadState(status: .sent, sentAt: nil, snoozedUntil: nil, updatedAt: nil,
                                 notes: nil, tasks: nil, sentEmails: nil, scheduledEmail: nil,
                                 draftOverride: nil)
                if let idx = allLeads.firstIndex(where: { $0.visitor.id == v.id && $0.session.id == session.id }) {
                    var row = allLeads[idx]
                    var visitor = row.visitor
                    visitor.leadState = newState
                    row = LeadRow(visitor: visitor, session: row.session)
                    allLeads[idx] = row
                }
                let first = v.visitor.name.split(separator: " ").first.map(String.init) ?? v.visitor.name
                showToast("Email sent to \(first)")
                if let warning = fubWarning {
                    sendError = warning
                }
            }
        } catch APIClient.SendEmailError.gmailNotConnected {
            await MainActor.run { showGmailConnect = true }
        } catch APIClient.SendEmailError.noRecipient {
            await MainActor.run { sendError = "This lead has no email on file." }
        } catch {
            await MainActor.run {
                sendError = friendlyErrorMessage("Couldn't send", error: error)
            }
        }
    }

    // MARK: – Toast

    @MainActor
    private func showToast(_ text: String) {
        sentToast = text
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.4))
            if !Task.isCancelled {
                await MainActor.run { sentToast = nil }
            }
        }
    }

    private func sentToastView(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(FoyerTheme.sage)
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(FoyerTheme.cream)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(FoyerTheme.sage.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
        )
    }

    // MARK: – CRM helpers

    @MainActor
    private func apply(_ state: LeadState, to row: LeadRow) {
        guard let idx = allLeads.firstIndex(where: { $0.id == row.id }) else { return }
        var existing = allLeads[idx]
        var visitor = existing.visitor
        visitor.leadState = state
        existing = LeadRow(visitor: visitor, session: existing.session)
        allLeads[idx] = existing
    }

    // Slot a freshly-edited visitor (with possibly-renamed name + updated
    // email/phone) back into the local list so the UI doesn't have to wait
    // for the next full reload. LeadRow.id depends on visitor.id which is
    // (name, speaker) — speaker is stable on rename, so the row's id can
    // change if the agent renamed the lead. Re-key activeId if so.
    @MainActor
    private func apply(visitor updated: VisitorResult, to row: LeadRow) {
        guard let idx = allLeads.firstIndex(where: { $0.id == row.id }) else { return }
        let session = allLeads[idx].session
        let replaced = LeadRow(visitor: updated, session: session)
        allLeads[idx] = replaced
        if activeId == row.id { activeId = replaced.id }
    }

    private func sectionHeader(_ title: String, count: Int? = nil) -> some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(FoyerTheme.textDim)
            if let count, count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(FoyerTheme.creamDim)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color(white: 0.10)))
            }
            Rectangle().fill(FoyerTheme.hairline).frame(height: 1)
        }
    }

    // MARK: – Scheduled email panel

    private func scheduledSection(_ row: LeadRow) -> some View {
        Group {
            if let sched = row.visitor.leadState?.scheduledEmail,
               let date = sched.sendDate {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("Scheduled")
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(FoyerTheme.gold)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sending \(absoluteDate(date))")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(FoyerTheme.cream)
                            if let err = sched.error {
                                Text("Last attempt failed: \(err)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(FoyerTheme.terracotta)
                            } else {
                                Text(sched.subject ?? "")
                                    .font(.system(size: 12))
                                    .foregroundStyle(FoyerTheme.textDim)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Button { Task { await cancelSchedule(row) } } label: {
                            Text("Cancel")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(FoyerTheme.terracotta)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(FoyerTheme.terracotta.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(FoyerTheme.goldSoft)
                    )
                }
            } else {
                EmptyView()
            }
        }
    }

    // MARK: – Sent emails history

    private func historySection(_ row: LeadRow) -> some View {
        let sent = row.visitor.leadState?.sentEmails ?? []
        return Group {
            if !sent.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("Email history", count: sent.count)
                    VStack(spacing: 8) {
                        ForEach(sent.reversed()) { e in
                            sentEmailRow(e)
                        }
                    }
                }
            } else {
                EmptyView()
            }
        }
    }

    private func sentEmailRow(_ e: SentEmail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(FoyerTheme.sage)
                Text(e.subject)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FoyerTheme.cream)
                    .lineLimit(1)
                Spacer()
                if e.scheduled == true {
                    Text("Scheduled")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(FoyerTheme.gold)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(FoyerTheme.goldSoft))
                }
                Text(relativeTime(e.sentAt))
                    .font(.system(size: 11))
                    .foregroundStyle(FoyerTheme.textDim)
            }
            Text("To \(e.to)")
                .font(.system(size: 11))
                .foregroundStyle(FoyerTheme.textDim)
            Text(e.body)
                .font(.system(size: 13))
                .foregroundStyle(FoyerTheme.creamDim)
                .lineSpacing(4)
                .lineLimit(4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(white: 0.05))
        )
    }

    // MARK: – Notes

    private func notesSection(_ row: LeadRow) -> some View {
        let notes = row.visitor.leadState?.notes ?? []
        let draft = Binding(
            get: { newNoteText[row.id] ?? "" },
            set: { newNoteText[row.id] = $0 }
        )
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Notes", count: notes.count)
            HStack(alignment: .top, spacing: 8) {
                TextField("Add a note — anything you want to remember…", text: draft, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.system(size: 14))
                    .foregroundStyle(FoyerTheme.cream)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(white: 0.05))
                    )
                Button { Task { await addNote(row) } } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(FoyerTheme.inkOnGold)
                        .frame(width: 36, height: 36)
                        .background(FoyerTheme.gold, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled((newNoteText[row.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity((newNoteText[row.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            }
            ForEach(notes.reversed()) { n in
                noteRow(row, note: n)
            }
        }
    }

    private func noteRow(_ row: LeadRow, note: LeadNote) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle().fill(FoyerTheme.gold).frame(width: 2)
                .clipShape(Capsule())
            VStack(alignment: .leading, spacing: 4) {
                Text(note.body)
                    .font(.system(size: 14))
                    .foregroundStyle(FoyerTheme.cream)
                    .lineSpacing(4)
                Text(relativeTime(note.createdAt))
                    .font(.system(size: 11))
                    .foregroundStyle(FoyerTheme.textDim)
            }
            Spacer()
            Button { Task { await deleteNote(row, noteId: note.id) } } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FoyerTheme.textDim)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(white: 0.04))
        )
    }

    // MARK: – Tasks

    private func tasksSection(_ row: LeadRow) -> some View {
        let tasks = row.visitor.leadState?.tasks ?? []
        let draft = Binding(
            get: { newTaskText[row.id] ?? "" },
            set: { newTaskText[row.id] = $0 }
        )
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Tasks", count: tasks.filter { !$0.done }.count)
            HStack(spacing: 8) {
                TextField("Add a task — e.g. 'Send comps Thursday'", text: draft)
                    .font(.system(size: 14))
                    .foregroundStyle(FoyerTheme.cream)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(white: 0.05))
                    )
                    .onSubmit { Task { await addTask(row) } }
                Button { Task { await addTask(row) } } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(FoyerTheme.inkOnGold)
                        .frame(width: 36, height: 36)
                        .background(FoyerTheme.gold, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled((newTaskText[row.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity((newTaskText[row.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            }
            ForEach(tasks) { t in
                taskRow(row, task: t)
            }
        }
    }

    private func taskRow(_ row: LeadRow, task: LeadTask) -> some View {
        HStack(spacing: 12) {
            Button { Task { await toggleTask(row, task: task) } } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(task.done ? FoyerTheme.sage : FoyerTheme.textDim)
            }
            .buttonStyle(.plain)
            Text(task.title)
                .font(.system(size: 14))
                .foregroundStyle(task.done ? FoyerTheme.textDim : FoyerTheme.cream)
                .strikethrough(task.done, color: FoyerTheme.textDim)
            Spacer()
            Button { Task { await deleteTask(row, taskId: task.id) } } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FoyerTheme.textDim)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(white: 0.04))
        )
    }

    // MARK: – CRM API calls

    @MainActor
    private func addNote(_ row: LeadRow) async {
        let body = (newNoteText[row.id] ?? "").trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return }
        do {
            let state = try await APIClient.shared.addNote(
                sessionId: row.session.id,
                visitorName: row.visitor.visitor.name,
                visitorSpeaker: row.visitor.visitor.speaker,
                body: body
            )
            apply(state, to: row)
            newNoteText[row.id] = ""
        } catch {
            crmError = "Couldn't add note: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func deleteNote(_ row: LeadRow, noteId: String) async {
        do {
            let state = try await APIClient.shared.deleteNote(
                sessionId: row.session.id,
                noteId: noteId,
                visitorName: row.visitor.visitor.name,
                visitorSpeaker: row.visitor.visitor.speaker
            )
            apply(state, to: row)
        } catch {
            crmError = "Couldn't delete note: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func addTask(_ row: LeadRow) async {
        let title = (newTaskText[row.id] ?? "").trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        do {
            let state = try await APIClient.shared.addTask(
                sessionId: row.session.id,
                visitorName: row.visitor.visitor.name,
                visitorSpeaker: row.visitor.visitor.speaker,
                title: title
            )
            apply(state, to: row)
            newTaskText[row.id] = ""
        } catch {
            crmError = "Couldn't add task: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func toggleTask(_ row: LeadRow, task: LeadTask) async {
        do {
            let state = try await APIClient.shared.updateTask(
                sessionId: row.session.id,
                taskId: task.id,
                visitorName: row.visitor.visitor.name,
                visitorSpeaker: row.visitor.visitor.speaker,
                done: !task.done
            )
            apply(state, to: row)
        } catch {
            crmError = "Couldn't update task: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func deleteTask(_ row: LeadRow, taskId: String) async {
        do {
            let state = try await APIClient.shared.deleteTask(
                sessionId: row.session.id,
                taskId: taskId,
                visitorName: row.visitor.visitor.name,
                visitorSpeaker: row.visitor.visitor.speaker
            )
            apply(state, to: row)
        } catch {
            crmError = "Couldn't delete task: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func autosaveDraft(for row: LeadRow, body: String) async {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let state = try await APIClient.shared.updateDraft(
                sessionId: row.session.id,
                visitorName: row.visitor.visitor.name,
                visitorSpeaker: row.visitor.visitor.speaker,
                body: trimmed,
                subject: nil,
                clear: false
            )
            apply(state, to: row)
        } catch {
            // Surface failures lightly — the agent's typing isn't lost
            // (still in the editor's local @State), so we don't need a
            // blocking toast. The Saved pip just won't appear, and the
            // next keystroke retries.
            crmError = friendlyErrorMessage("Couldn't autosave draft", error: error)
        }
    }

    @MainActor
    private func resetDraft(for row: LeadRow) async {
        do {
            _ = try await APIClient.shared.updateDraft(
                sessionId: row.session.id,
                visitorName: row.visitor.visitor.name,
                visitorSpeaker: row.visitor.visitor.speaker,
                body: nil,
                subject: nil,
                clear: true
            )
            // Pull a fresh copy of the session so the visitor's full
            // analysis + lead_state pair lands in our local cache. The
            // PATCH return only carries lead_state, which used to leave
            // the displayed draft stuck on whatever cached analysis we
            // already had — reset would clear the override but the AI
            // draft displayed wouldn't update. Refetching the session
            // guarantees the UI matches the server.
            let fresh = try await APIClient.shared.getSession(id: row.session.id)
            apply(session: fresh, to: row)
        } catch {
            crmError = "Couldn't reset draft: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func apply(session fresh: Session, to row: LeadRow) {
        guard let result = fresh.result,
              let visitor = result.visitors.first(where: { $0.id == row.visitor.id })
        else { return }
        guard let idx = allLeads.firstIndex(where: { $0.id == row.id }) else { return }
        allLeads[idx] = LeadRow(visitor: visitor, session: fresh)
    }

    @MainActor
    private func cancelSchedule(_ row: LeadRow) async {
        do {
            let state = try await APIClient.shared.cancelScheduledEmail(
                sessionId: row.session.id,
                visitorName: row.visitor.visitor.name,
                visitorSpeaker: row.visitor.visitor.speaker
            )
            apply(state, to: row)
        } catch {
            crmError = "Couldn't cancel: \(error.localizedDescription)"
        }
    }

    private func relativeTime(_ iso: String?) -> String {
        guard let iso else { return "" }
        let fmt = ISO8601DateFormatter.fractionalSeconds
        guard let date = fmt.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else {
            return ""
        }
        let now = Date()
        let delta = now.timeIntervalSince(date)
        if delta < 60 { return "just now" }
        if delta < 3600 { return "\(Int(delta / 60))m ago" }
        if delta < 86_400 { return "\(Int(delta / 3600))h ago" }
        let days = Int(delta / 86_400)
        if days < 14 { return "\(days)d ago" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    private func absoluteDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d 'at' h:mma"
        return f.string(from: date).replacingOccurrences(of: "AM", with: "am").replacingOccurrences(of: "PM", with: "pm")
    }
}

// MARK: – Follow Up Boss connect sheet

private struct FUBConnectSheetIPad: View {
    @Binding var connectedName: String?
    var onClose: () -> Void

    @State private var apiKey: String = ""
    @State private var testing = false
    @State private var errorMessage: String?
    @State private var alreadyConnected: Bool = FUBCredential.isConnected

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    intro
                    if alreadyConnected {
                        connectedCard
                    } else {
                        keyField
                        connectButton
                    }
                    if let err = errorMessage {
                        Text(err)
                            .font(.system(size: 12))
                            .foregroundStyle(FoyerTheme.terracotta)
                    }
                    howToFind
                }
                .padding(28)
            }
            .background(Color.black)
            .navigationTitle("Follow Up Boss")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CRM INTEGRATION")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(FoyerTheme.gold)
            Text("Push captured leads automatically")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(FoyerTheme.cream)
            Text("When you Send a follow-up draft, OpenHouseBoss creates the contact in FUB, attaches your session notes, and schedules a follow-up task. The API key stays in this device's Keychain — it never goes to our servers.")
                .font(.system(size: 13))
                .foregroundStyle(FoyerTheme.creamDim)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
        }
    }

    private var keyField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("API KEY")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(FoyerTheme.textDim)
            SecureField("", text: $apiKey,
                        prompt: Text("Paste from FUB → Settings → API").foregroundStyle(FoyerTheme.textMuted.opacity(0.7)))
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(FoyerTheme.cream)
                .tint(FoyerTheme.gold)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var connectButton: some View {
        Button(action: testAndSave) {
            HStack(spacing: 8) {
                if testing {
                    ProgressView().scaleEffect(0.7).tint(FoyerTheme.inkOnGold)
                }
                Text(testing ? "Connecting…" : "Test & connect")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(FoyerTheme.inkOnGold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(FoyerTheme.gold, in: Capsule())
        }
        .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty || testing)
        .opacity(apiKey.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
        .buttonStyle(.plain)
    }

    private var connectedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(FoyerTheme.sage)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connected")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(FoyerTheme.cream)
                    Text(connectedName ?? "Sending leads to your FUB account.")
                        .font(.system(size: 12))
                        .foregroundStyle(FoyerTheme.creamDim)
                }
                Spacer()
            }
            .padding(16)
            .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: 14))

            Button(role: .destructive, action: disconnect) {
                Text("Disconnect")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FoyerTheme.terracotta)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(FoyerTheme.terracotta.opacity(0.10), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var howToFind: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WHERE DO I FIND THIS?")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(FoyerTheme.textDim)
            Text("In Follow Up Boss: click your profile → Settings → API. Create or copy a key with read + write access.")
                .font(.system(size: 12))
                .foregroundStyle(FoyerTheme.textDim)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
        }
    }

    private func testAndSave() {
        let key = apiKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        testing = true
        errorMessage = nil
        Task {
            do {
                let name = try await APIClient.shared.fubTestKey(key)
                try FUBCredential.save(key)
                await MainActor.run {
                    testing = false
                    alreadyConnected = true
                    connectedName = name
                    apiKey = ""
                }
            } catch {
                await MainActor.run {
                    testing = false
                    errorMessage = "That key didn't work: \(error.localizedDescription)"
                }
            }
        }
    }

    private func disconnect() {
        FUBCredential.clear()
        alreadyConnected = false
        connectedName = nil
    }
}

// MARK: – Script editor sheet

// Identifiable wrapper so `.sheet(item:)` can drive on an Optional<String>.
private struct ScriptIdRef: Identifiable, Hashable {
    let id: String
}

private struct ScriptEditorSheet: View {
    let existingId: String?
    var onCancel: () -> Void
    var onSaved: () -> Void

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var steps: [ScriptStepDraft] = [ScriptStepDraft(label: "Step 1")]
    @State private var loading: Bool = true
    @State private var saving: Bool = false
    @State private var deleting: Bool = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirm: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if loading {
                    ProgressView()
                        .tint(FoyerTheme.gold)
                        .padding(60)
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        introBlurb
                        nameAndDescription
                        stepsSection
                        if let err = errorMessage {
                            Text(err)
                                .font(.system(size: 12))
                                .foregroundStyle(FoyerTheme.terracotta)
                        }
                        if existingId != nil {
                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("Delete script")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .foregroundStyle(FoyerTheme.terracotta)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(FoyerTheme.terracotta.opacity(0.10), in: Capsule())
                            }
                            .disabled(saving || deleting)
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(28)
                }
            }
            .background(Color.black)
            .navigationTitle(existingId == nil ? "New script" : "Edit script")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .disabled(saving || deleting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(!canSave || saving || deleting)
                }
            }
            .alert("Delete this script?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { Task { await delete() } }
            } message: {
                Text("This can't be undone. Past sessions graded against this script keep their coverage results, but new sessions won't have it as an option.")
            }
        }
        .task { await load() }
    }

    private var introBlurb: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("OPEN-HOUSE COACHING")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(FoyerTheme.gold)
            Text(existingId == nil ? "Author a script" : "Edit script")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(FoyerTheme.cream)
            Text("After each open house, the AI grades how well you covered each step and surfaces the lines you said vs. what's missing. Use Quote for the line you typically deliver, and Why it matters to teach the AI when it counts as covered.")
                .font(.system(size: 13))
                .foregroundStyle(FoyerTheme.creamDim)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
        }
    }

    private var nameAndDescription: some View {
        VStack(alignment: .leading, spacing: 14) {
            field("NAME", placeholder: "My buyer flow", text: $name)
            field("DESCRIPTION", placeholder: "Lead qualification + rebate close",
                  text: $description, multiline: true, minHeight: 60)
        }
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("STEPS · \(steps.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(FoyerTheme.textDim)
                Spacer()
                Button { addStep() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Add step")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(FoyerTheme.gold)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(FoyerTheme.goldSoft, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            VStack(spacing: 12) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { idx, _ in
                    stepCard(at: idx)
                }
            }
        }
    }

    private func stepCard(at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("STEP \(index + 1)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(FoyerTheme.gold)
                Spacer()
                if steps.count > 1 {
                    Button { removeStep(at: index) } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(FoyerTheme.terracotta)
                    }
                    .buttonStyle(.plain)
                }
            }
            miniField("Label", placeholder: "Establish the timeline",
                      text: Binding(
                        get: { steps[index].label },
                        set: { steps[index].label = $0 }))
            miniField("What you'll say", placeholder: "So are you getting close to making a move?",
                      text: Binding(
                        get: { steps[index].quote },
                        set: { steps[index].quote = $0 }),
                      multiline: true, minHeight: 60)
            miniField("Why it matters", placeholder: "Sorts active buyers from window-shoppers",
                      text: Binding(
                        get: { steps[index].intent },
                        set: { steps[index].intent = $0 }),
                      multiline: true, minHeight: 50)
        }
        .padding(14)
        .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func field(_ label: String, placeholder: String, text: Binding<String>,
                       multiline: Bool = false, minHeight: CGFloat = 44) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(FoyerTheme.textDim)
            if multiline {
                ZStack(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        Text(placeholder)
                            .font(.system(size: 14))
                            .foregroundStyle(FoyerTheme.textDim.opacity(0.6))
                            .padding(.horizontal, 14).padding(.vertical, 12)
                    }
                    TextEditor(text: text)
                        .font(.system(size: 14))
                        .foregroundStyle(FoyerTheme.cream)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .frame(minHeight: minHeight)
                }
                .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 12))
            } else {
                TextField(placeholder, text: text)
                    .font(.system(size: 14))
                    .foregroundStyle(FoyerTheme.cream)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 12))
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.sentences)
            }
        }
    }

    @ViewBuilder
    private func miniField(_ label: String, placeholder: String, text: Binding<String>,
                           multiline: Bool = false, minHeight: CGFloat = 38) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(FoyerTheme.textMuted)
            if multiline {
                ZStack(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        Text(placeholder)
                            .font(.system(size: 13))
                            .foregroundStyle(FoyerTheme.textDim.opacity(0.6))
                            .padding(.horizontal, 10).padding(.vertical, 8)
                    }
                    TextEditor(text: text)
                        .font(.system(size: 13))
                        .foregroundStyle(FoyerTheme.cream)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .frame(minHeight: minHeight)
                }
                .background(Color(white: 0.04), in: RoundedRectangle(cornerRadius: 10))
            } else {
                TextField(placeholder, text: text)
                    .font(.system(size: 13))
                    .foregroundStyle(FoyerTheme.cream)
                    .padding(.horizontal, 10).padding(.vertical, 9)
                    .background(Color(white: 0.04), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        steps.contains { !$0.label.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func addStep() {
        steps.append(ScriptStepDraft(label: "Step \(steps.count + 1)"))
    }

    private func removeStep(at index: Int) {
        guard index < steps.count else { return }
        steps.remove(at: index)
    }

    @MainActor
    private func load() async {
        if let id = existingId {
            do {
                let detail = try await APIClient.shared.getScript(id: id)
                name = detail.name
                description = detail.description
                steps = detail.steps.map {
                    ScriptStepDraft(id: $0.id, label: $0.label, quote: $0.quote ?? "", intent: $0.intent ?? "")
                }
                if steps.isEmpty {
                    steps = [ScriptStepDraft(label: "Step 1")]
                }
            } catch {
                errorMessage = "Couldn't load script: \(error.localizedDescription)"
            }
        }
        loading = false
    }

    @MainActor
    private func save() async {
        saving = true
        defer { saving = false }
        let cleaned = steps.filter { !$0.label.trimmingCharacters(in: .whitespaces).isEmpty }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if let id = existingId {
                _ = try await APIClient.shared.updateScript(
                    id: id, name: trimmedName, description: trimmedDesc, steps: cleaned
                )
            } else {
                _ = try await APIClient.shared.createScript(
                    name: trimmedName, description: trimmedDesc, steps: cleaned
                )
            }
            onSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func delete() async {
        guard let id = existingId else { return }
        deleting = true
        defer { deleting = false }
        do {
            try await APIClient.shared.deleteScript(id: id)
            onSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: – Template editor sheet

private struct TemplateEditorSheet: View {
    let existing: FollowupTemplate?
    var onCancel: () -> Void
    var onSaved: (FollowupTemplate) -> Void

    @State private var name: String = ""
    @State private var matchHints: String = ""
    @State private var subject: String = ""
    @State private var bodyText: String = ""
    @State private var enabled: Bool = true
    @State private var saving: Bool = false
    @State private var deleting: Bool = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirm: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    field("NAME", placeholder: "Interested buyer, no offer yet", text: $name)
                    field("MATCH HINTS (when this fits)",
                          placeholder: "Buyer expressed interest but no urgency — likes the place, hasn't made an offer.",
                          text: $matchHints,
                          multiline: true,
                          minHeight: 70)
                    field("SUBJECT",
                          placeholder: "Following up — {property_address}",
                          text: $subject)
                    field("BODY",
                          placeholder: "Hi {first_name} — great to chat about the place. Want me to send a few comps so you can compare?\n\n— [Your name]",
                          text: $bodyText,
                          multiline: true,
                          minHeight: 220)

                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(FoyerTheme.textDim)
                        Text("Use `{first_name}` and `{full_name}` for auto-fill, or any other `{slot}` you want filled (e.g. `{call_to_action}`).")
                            .font(.system(size: 11))
                            .foregroundStyle(FoyerTheme.textDim)
                    }
                    .padding(.top, -8)

                    Toggle(isOn: $enabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enabled")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(FoyerTheme.cream)
                            Text("When off, the AI ignores this template.")
                                .font(.system(size: 11))
                                .foregroundStyle(FoyerTheme.textMuted)
                        }
                    }
                    .tint(FoyerTheme.gold)
                    .padding(.vertical, 12).padding(.horizontal, 14)
                    .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 12))

                    if let err = errorMessage {
                        Text(err)
                            .font(.system(size: 12))
                            .foregroundStyle(FoyerTheme.terracotta)
                    }

                    if existing != nil {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "trash")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Delete template")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(FoyerTheme.terracotta)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(FoyerTheme.terracotta.opacity(0.10), in: Capsule())
                        }
                        .disabled(saving || deleting)
                        .buttonStyle(.plain)
                    }
                }
                .padding(28)
            }
            .background(Color.black)
            .navigationTitle(existing == nil ? "New template" : "Edit template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .disabled(saving || deleting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(saving || deleting
                                  || name.trimmingCharacters(in: .whitespaces).isEmpty
                                  || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Delete this template?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { Task { await delete() } }
            } message: {
                Text("This can't be undone. Existing follow-ups that used this template are unaffected.")
            }
        }
        .onAppear {
            if let t = existing {
                name = t.name
                matchHints = t.matchHints
                subject = t.subject
                bodyText = t.body
                enabled = t.enabled
            }
        }
    }

    @ViewBuilder
    private func field(_ label: String, placeholder: String, text: Binding<String>, multiline: Bool = false, minHeight: CGFloat = 44) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(FoyerTheme.textDim)
            if multiline {
                ZStack(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        Text(placeholder)
                            .font(.system(size: 14))
                            .foregroundStyle(FoyerTheme.textDim.opacity(0.6))
                            .padding(.horizontal, 14).padding(.vertical, 12)
                    }
                    TextEditor(text: text)
                        .font(.system(size: 14))
                        .foregroundStyle(FoyerTheme.cream)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .frame(minHeight: minHeight)
                }
                .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 12))
            } else {
                TextField(placeholder, text: text)
                    .font(.system(size: 14))
                    .foregroundStyle(FoyerTheme.cream)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 12))
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.sentences)
            }
        }
    }

    @MainActor
    private func save() async {
        saving = true
        defer { saving = false }
        do {
            let saved: FollowupTemplate
            if let t = existing {
                saved = try await APIClient.shared.updateTemplate(
                    id: t.id,
                    name: name.trimmingCharacters(in: .whitespaces),
                    subject: subject.trimmingCharacters(in: .whitespaces),
                    body: bodyText.trimmingCharacters(in: .whitespacesAndNewlines),
                    matchHints: matchHints.trimmingCharacters(in: .whitespacesAndNewlines),
                    enabled: enabled
                )
            } else {
                saved = try await APIClient.shared.createTemplate(
                    name: name.trimmingCharacters(in: .whitespaces),
                    subject: subject.trimmingCharacters(in: .whitespaces),
                    body: bodyText.trimmingCharacters(in: .whitespacesAndNewlines),
                    matchHints: matchHints.trimmingCharacters(in: .whitespacesAndNewlines),
                    enabled: enabled
                )
            }
            onSaved(saved)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func delete() async {
        guard let t = existing else { return }
        deleting = true
        defer { deleting = false }
        do {
            try await APIClient.shared.deleteTemplate(id: t.id)
            onSaved(t)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: – Schedule send sheet

private struct ScheduleSendSheet: View {
    let row: IPadLeads.LeadRow
    var onCancel: () -> Void
    var onScheduled: (LeadState) -> Void

    @State private var sendAt: Date = Date().addingTimeInterval(60 * 60 * 24)  // default: 24h
    @State private var subject: String = ""
    @State private var bodyText: String = ""
    @State private var submitting: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SEND TO")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(FoyerTheme.textDim)
                        Text(row.visitor.visitor.email.isEmpty
                             ? "No email on file"
                             : row.visitor.visitor.email)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(row.visitor.visitor.email.isEmpty
                                             ? FoyerTheme.terracotta : FoyerTheme.cream)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("WHEN")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(FoyerTheme.textDim)
                        DatePicker(
                            "",
                            selection: $sendAt,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .labelsHidden()
                        .datePickerStyle(.graphical)
                        .tint(FoyerTheme.gold)
                    }

                    HStack(spacing: 10) {
                        quickPicker("In 1 hour", offset: 3600)
                        quickPicker("Tomorrow 9am", absolute: tomorrowAt(hour: 9))
                        quickPicker("Mon 9am", absolute: nextWeekdayAt(weekday: 2, hour: 9))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("SUBJECT")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(FoyerTheme.textDim)
                        TextField("Following up", text: $subject)
                            .font(.system(size: 14))
                            .foregroundStyle(FoyerTheme.cream)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(white: 0.06))
                            )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("EMAIL BODY")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(FoyerTheme.textDim)
                        TextEditor(text: $bodyText)
                            .font(.system(size: 14))
                            .foregroundStyle(FoyerTheme.cream)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 140)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(white: 0.06))
                            )
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(FoyerTheme.terracotta)
                    }
                }
                .padding(24)
            }
            .background(Color.black)
            .navigationTitle("Schedule send")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(submitting ? "Scheduling…" : "Schedule") {
                        Task { await schedule() }
                    }
                    .disabled(submitting || row.visitor.visitor.email.isEmpty)
                    .bold()
                }
            }
        }
        .onAppear {
            if subject.isEmpty {
                subject = "Following up — \(row.session.address ?? "the open house")"
            }
            if bodyText.isEmpty {
                bodyText = row.visitor.analysis.followUpDraft
            }
        }
    }

    private func quickPicker(_ label: String, offset: TimeInterval? = nil, absolute: Date? = nil) -> some View {
        Button {
            if let offset { sendAt = Date().addingTimeInterval(offset) }
            if let absolute { sendAt = absolute }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(FoyerTheme.gold)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(FoyerTheme.goldSoft, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func tomorrowAt(hour: Int) -> Date {
        let cal = Calendar.current
        let base = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return cal.date(bySettingHour: hour, minute: 0, second: 0, of: base) ?? base
    }

    private func nextWeekdayAt(weekday: Int, hour: Int) -> Date {
        // weekday: 1=Sunday … 2=Monday
        let cal = Calendar.current
        var d = Date()
        for _ in 0..<8 {
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
            if cal.component(.weekday, from: d) == weekday { break }
        }
        return cal.date(bySettingHour: hour, minute: 0, second: 0, of: d) ?? d
    }

    @MainActor
    private func schedule() async {
        submitting = true
        defer { submitting = false }
        errorMessage = nil
        do {
            let state = try await APIClient.shared.scheduleEmail(
                sessionId: row.session.id,
                visitorName: row.visitor.visitor.name,
                visitorSpeaker: row.visitor.visitor.speaker,
                sendAt: sendAt,
                subject: subject.isEmpty ? nil : subject,
                bodyText: bodyText.isEmpty ? nil : bodyText
            )
            onScheduled(state)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: – Manual lead entry sheet

// Minimal form for typing in a lead that didn't come from a recorded
// session — e.g. the agent met someone outside the open house and wants
// it to flow through the same follow-up tooling. Backend creates a
// kind="manual" Session under the hood so the lead surfaces in the inbox.
private struct ManualLeadSheet: View {
    var onCancel: () -> Void
    var onCreated: (Session) -> Void

    @State private var first: String = ""
    @State private var last: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var tag: String = "buyer"
    @State private var address: String = ""
    @State private var submitting: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        field("First name", value: $first, keyboard: .default)
                        field("Last name", value: $last, keyboard: .default)
                    }
                    field("Email", value: $email, keyboard: .emailAddress)
                    // asciiCapableNumberPad locks the keyboard to digits
                    // (no symbols, no letters) — what the agent expects
                    // when typing a phone number. We format display-side.
                    field("Phone", value: $phone, keyboard: .asciiCapableNumberPad)
                        .onChange(of: phone) { _, new in
                            let formatted = formatPhone(new)
                            if formatted != new { phone = formatted }
                        }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Lead type").font(.system(size: 11, weight: .medium))
                            .foregroundStyle(FoyerTheme.textDim)
                        Picker("Lead type", selection: $tag) {
                            Text("Buyer").tag("buyer")
                            Text("Seller").tag("seller")
                            Text("Browser").tag("browser")
                        }
                        .pickerStyle(.segmented)
                    }

                    field("Address (optional)", value: $address, keyboard: .default)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(FoyerTheme.terracotta)
                    }
                }
                .padding(24)
            }
            .background(Color.black)
            .navigationTitle("New lead")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                        .foregroundStyle(FoyerTheme.creamDim)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await submit() } } label: {
                        if submitting { ProgressView() } else { Text("Save") }
                    }
                    .foregroundStyle(canSave ? FoyerTheme.gold : FoyerTheme.textMuted)
                    .disabled(!canSave || submitting)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func field(_ label: String, value: Binding<String>, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 11, weight: .medium))
                .foregroundStyle(FoyerTheme.textDim)
            TextField("", text: value)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(FoyerTheme.cream)
                .tint(FoyerTheme.gold)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .padding(.vertical, 14).padding(.horizontal, 14)
                .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var canSave: Bool {
        let hasName = !first.trimmingCharacters(in: .whitespaces).isEmpty &&
                      !last.trimmingCharacters(in: .whitespaces).isEmpty
        return hasName &&
            (!email.trimmingCharacters(in: .whitespaces).isEmpty ||
             !phone.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    @MainActor
    private func submit() async {
        submitting = true
        errorMessage = nil
        defer { submitting = false }
        let fullName = (first.trimmingCharacters(in: .whitespaces) + " " +
                        last.trimmingCharacters(in: .whitespaces))
                       .trimmingCharacters(in: .whitespaces)
        do {
            let session = try await APIClient.shared.createManualLead(
                name: fullName,
                email: email.trimmingCharacters(in: .whitespaces),
                phone: phone.trimmingCharacters(in: .whitespaces),
                tag: tag,
                address: address.trimmingCharacters(in: .whitespaces).isEmpty ? nil : address
            )
            onCreated(session)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func formatPhone(_ input: String) -> String {
        let digits = input.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }
        let s = String(String.UnicodeScalarView(digits.prefix(10)))
        let n = s.count
        switch n {
        case 0:     return ""
        case 1...3: return "(\(s)"
        case 4...6:
            let area = s.prefix(3); let mid = s.dropFirst(3)
            return "(\(area)) \(mid)"
        default:
            let area = s.prefix(3); let mid = s.dropFirst(3).prefix(3); let end = s.dropFirst(6)
            return "(\(area)) \(mid)-\(end)"
        }
    }
}

// MARK: – Draft editor pane
//
// Always-editable draft surface. There's no edit/save toggle — every
// keystroke debounces into a background autosave (~800ms after the agent
// stops typing) and a small inline status pip shows Saving / Saved so the
// agent has confidence the change landed. Refine With AI stays in the
// editor; its rewrite drops into `text`, which triggers the same autosave
// path that manual typing does.

private struct DraftEditorPane: View {
    let initialText: String
    let sessionId: String
    let visitorName: String
    let visitorSpeaker: String?
    let onAutosave: (String) async -> Void

    @State private var text: String
    @State private var instruction: String = ""
    @State private var refining: Bool = false
    @State private var refineError: String?
    @State private var saveStatus: SaveStatus = .idle
    @State private var autosaveTask: Task<Void, Never>?
    @FocusState private var instructionFocused: Bool

    private enum SaveStatus { case idle, saving, saved }

    init(
        initialText: String,
        sessionId: String,
        visitorName: String,
        visitorSpeaker: String?,
        onAutosave: @escaping (String) async -> Void
    ) {
        self.initialText = initialText
        self.sessionId = sessionId
        self.visitorName = visitorName
        self.visitorSpeaker = visitorSpeaker
        self.onAutosave = onAutosave
        _text = State(initialValue: initialText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextEditor(text: $text)
                .font(.system(size: 15))
                .foregroundStyle(FoyerTheme.cream)
                .scrollContentBackground(.hidden)
                .padding(14)
                .frame(minHeight: 160)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(white: 0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(FoyerTheme.gold.opacity(0.25), lineWidth: 1)
                )
                .onChange(of: text) { _, newValue in
                    scheduleAutosave(newValue)
                }

            HStack(spacing: 10) {
                saveStatusPill
                Spacer()
            }

            refineRow
        }
    }

    @ViewBuilder
    private var saveStatusPill: some View {
        switch saveStatus {
        case .idle:
            EmptyView()
        case .saving:
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.55).tint(FoyerTheme.creamDim)
                Text("Saving…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FoyerTheme.creamDim)
            }
        case .saved:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FoyerTheme.sage)
                Text("Saved")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FoyerTheme.creamDim)
            }
            .transition(.opacity)
        }
    }

    private func scheduleAutosave(_ candidate: String) {
        autosaveTask?.cancel()
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        // Blank drafts are a no-op — Send needs SOMETHING in the body, so
        // just hold and wait for more typing instead of persisting empty.
        guard !trimmed.isEmpty else {
            saveStatus = .idle
            return
        }
        autosaveTask = Task { [candidate] in
            try? await Task.sleep(for: .milliseconds(800))
            if Task.isCancelled { return }
            await MainActor.run { saveStatus = .saving }
            await onAutosave(candidate)
            if Task.isCancelled { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) { saveStatus = .saved }
            }
            try? await Task.sleep(for: .seconds(1.4))
            if Task.isCancelled { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.35)) { saveStatus = .idle }
            }
        }
    }

    private var refineRow: some View {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FoyerTheme.gold)
                Text("Refine with AI")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(FoyerTheme.creamDim)
                Spacer()
            }
            HStack(spacing: 8) {
                TextField(
                    "e.g. shorter, add a CTA, mention @offerName",
                    text: $instruction,
                    axis: .horizontal
                )
                .font(.system(size: 13))
                .foregroundStyle(FoyerTheme.cream)
                .tint(FoyerTheme.gold)
                .submitLabel(.send)
                .autocorrectionDisabled(false)
                .focused($instructionFocused)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Color(white: 0.07), in: RoundedRectangle(cornerRadius: 10))
                .disabled(refining)
                .onSubmit { Task { await runRefine() } }

                Button { Task { await runRefine() } } label: {
                    HStack(spacing: 6) {
                        if refining {
                            ProgressView().scaleEffect(0.6).tint(FoyerTheme.inkOnGold)
                        } else {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(refining ? "Refining…" : "Rewrite")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(trimmed.isEmpty ? FoyerTheme.textMuted : FoyerTheme.inkOnGold)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(
                        Capsule().fill(trimmed.isEmpty
                                       ? Color(white: 0.10)
                                       : FoyerTheme.gold)
                    )
                }
                .buttonStyle(.plain)
                .disabled(trimmed.isEmpty || refining)
            }
            MentionSuggestionsView(text: $instruction)
            if let refineError {
                Text(refineError)
                    .font(.system(size: 11))
                    .foregroundStyle(FoyerTheme.terracotta)
            }
        }
        .padding(.top, 4)
    }

    @MainActor
    private func runRefine() async {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        refining = true
        refineError = nil
        let base = text
        defer { refining = false }
        do {
            let newBody = try await APIClient.shared.refineDraft(
                sessionId: sessionId,
                visitorName: visitorName,
                visitorSpeaker: visitorSpeaker,
                instruction: trimmed,
                baseBody: base
            )
            text = newBody
            instruction = ""
        } catch {
            refineError = friendlyErrorMessage("Refine failed", error: error)
        }
    }
}

// Pretty-print the network errors we see most often so we don't dump
// raw HTML or stack traces into the UI. Backend runs on a paid Render
// plan (always warm), so "waking up" framing is wrong — if leads loaded
// the dyno is up. A 502 here usually means the worker errored mid-
// request; a timeout usually means a backend bug holding a lock or a
// hanging upstream call.
private func friendlyErrorMessage(_ prefix: String, error: Error) -> String {
    let raw = error.localizedDescription
    let lower = raw.lowercased()
    if lower.contains("502 bad gateway")
        || lower.contains("503 service")
        || lower.contains("504 gateway")
        || (lower.contains("<title>502") && lower.contains("</title>"))
        || lower.contains("cloudflare")
        || lower.contains("<!doctype html>") {
        return "\(prefix): backend hiccuped (proxy error). Try again."
    }
    if case let APIError.http(code, _) = error, [502, 503, 504].contains(code) {
        return "\(prefix): backend hiccuped (\(code)). Try again."
    }
    if let urlError = error as? URLError, urlError.code == .timedOut {
        return "\(prefix): timed out. The backend may be stuck on this request — try again."
    }
    return "\(prefix): \(raw)"
}

// MARK: – Edit-contact sheet
//
// Lets the agent fix a lead's display name, email, or phone after the fact —
// diarization often gets names wrong (or the kiosk form had a typo). Keeps
// the speaker label stable so notes, tasks, schedules etc. don't lose their
// composite-key anchor on rename.

private struct EditContactSheet: View {
    let row: IPadLeads.LeadRow
    var onCancel: () -> Void
    var onSaved: (VisitorResult) -> Void

    @State private var name: String
    @State private var email: String
    @State private var phone: String
    @State private var submitting: Bool = false
    @State private var errorMessage: String?

    init(row: IPadLeads.LeadRow, onCancel: @escaping () -> Void, onSaved: @escaping (VisitorResult) -> Void) {
        self.row = row
        self.onCancel = onCancel
        self.onSaved = onSaved
        _name = State(initialValue: row.visitor.visitor.name)
        _email = State(initialValue: row.visitor.visitor.email)
        _phone = State(initialValue: row.visitor.visitor.phone)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    field("Name", value: $name, keyboard: .default)
                    field("Email", value: $email, keyboard: .emailAddress)
                    field("Phone", value: $phone, keyboard: .asciiCapableNumberPad)
                        .onChange(of: phone) { _, new in
                            let formatted = formatPhone(new)
                            if formatted != new { phone = formatted }
                        }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(FoyerTheme.terracotta)
                    }
                    Text("Diarization sometimes mangles names off audio. Fix it here and the rest of the app (drafts, sends, follow-ups) picks up the new info.")
                        .font(.system(size: 11))
                        .foregroundStyle(FoyerTheme.textMuted)
                        .padding(.top, 6)
                }
                .padding(24)
            }
            .background(Color.black)
            .navigationTitle("Edit contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                        .foregroundStyle(FoyerTheme.creamDim)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        if submitting { ProgressView() } else { Text("Save") }
                    }
                    .foregroundStyle(canSave ? FoyerTheme.gold : FoyerTheme.textMuted)
                    .disabled(!canSave || submitting)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func field(_ label: String, value: Binding<String>, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 11, weight: .medium))
                .foregroundStyle(FoyerTheme.textDim)
            TextField("", text: value)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(FoyerTheme.cream)
                .tint(FoyerTheme.gold)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .padding(.vertical, 14).padding(.horizontal, 14)
                .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    @MainActor
    private func save() async {
        submitting = true
        errorMessage = nil
        defer { submitting = false }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
        do {
            let updated = try await APIClient.shared.updateVisitorContact(
                sessionId: row.session.id,
                visitorName: row.visitor.visitor.name,
                visitorSpeaker: row.visitor.visitor.speaker,
                newName: trimmedName == row.visitor.visitor.name ? nil : trimmedName,
                newEmail: trimmedEmail == row.visitor.visitor.email ? nil : trimmedEmail,
                newPhone: trimmedPhone == row.visitor.visitor.phone ? nil : trimmedPhone
            )
            onSaved(updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func formatPhone(_ input: String) -> String {
        let digits = input.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }
        let s = String(String.UnicodeScalarView(digits.prefix(10)))
        let n = s.count
        switch n {
        case 0:     return ""
        case 1...3: return "(\(s)"
        case 4...6:
            let area = s.prefix(3); let mid = s.dropFirst(3)
            return "(\(area)) \(mid)"
        default:
            let area = s.prefix(3); let mid = s.dropFirst(3).prefix(3); let end = s.dropFirst(6)
            return "(\(area)) \(mid)-\(end)"
        }
    }
}

// MARK: – Leads AI agent sheet
//
// One-shot AI agent over the agent's leads inbox. The user types a
// question or instruction; the backend either returns an answer (we
// render it as text) or a concrete plan (subject + per-recipient body for
// every lead matching the user's filter). A single "Send all" button
// fires every email in the plan — no per-lead confirmation. The user
// sees ALL recipients in the preview so the bulk send isn't a surprise.

private struct LeadsAgentSheet: View {
    var onDismiss: () -> Void
    var onCompleted: (Int) -> Void

    @State private var input: String = ""
    @State private var loading: Bool = false
    @State private var errorMessage: String?
    @State private var reply: APIClient.LeadsAgentReply?
    @State private var editableSubject: String = ""
    @State private var editableRecipients: [APIClient.LeadsAgentRecipient] = []
    @State private var sending: Bool = false
    @State private var sendResult: APIClient.LeadsAgentExecuteResult?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    promptCard
                    if loading {
                        HStack(spacing: 10) {
                            FoyerLoadingView(size: 36, cornerRadius: 7)
                            Text("Thinking through your leads…")
                                .font(.system(size: 13))
                                .foregroundStyle(FoyerTheme.textDim)
                        }
                        .padding(.vertical, 16)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(FoyerTheme.terracotta)
                    }
                    if let reply, !sending, sendResult == nil {
                        replyCard(reply)
                    }
                    if sending {
                        HStack(spacing: 10) {
                            FoyerLoadingView(size: 36, cornerRadius: 7)
                            Text("Sending — this can take a minute…")
                                .font(.system(size: 13))
                                .foregroundStyle(FoyerTheme.textDim)
                        }
                        .padding(.vertical, 16)
                    }
                    if let sendResult {
                        sendResultCard(sendResult)
                    }
                }
                .padding(24)
            }
            .background(Color.black)
            .navigationTitle("Inbox AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        onCompleted(sendResult?.sent ?? 0)
                        onDismiss()
                    }
                    .foregroundStyle(FoyerTheme.creamDim)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FoyerTheme.gold)
                Text("ASK OR INSTRUCT")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(FoyerTheme.textDim)
            }
            TextEditor(text: $input)
                .font(.system(size: 15))
                .foregroundStyle(FoyerTheme.cream)
                .tint(FoyerTheme.gold)
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 100)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(white: 0.07))
                )
                .overlay(alignment: .topLeading) {
                    if input.isEmpty {
                        Text("e.g. \"Send the $2,500 buyer credit to every buyer lead\" or \"Who are my hottest sellers right now?\" — type @ to reference an offer or template.")
                            .font(.system(size: 13))
                            .foregroundStyle(FoyerTheme.textMuted)
                            .padding(.horizontal, 17).padding(.top, 19)
                            .allowsHitTesting(false)
                    }
                }
            MentionSuggestionsView(text: $input)
            HStack {
                Spacer()
                Button { Task { await ask() } } label: {
                    HStack(spacing: 6) {
                        if loading {
                            ProgressView().scaleEffect(0.6).tint(FoyerTheme.inkOnGold)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(loading ? "Working…" : "Ask")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(canAsk ? FoyerTheme.inkOnGold : FoyerTheme.textMuted)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(
                        Capsule().fill(canAsk ? FoyerTheme.gold : Color(white: 0.10))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canAsk)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(white: 0.04))
        )
    }

    private var canAsk: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !loading
    }

    @ViewBuilder
    private func replyCard(_ r: APIClient.LeadsAgentReply) -> some View {
        if r.kind == "answer" {
            VStack(alignment: .leading, spacing: 12) {
                Text("ANSWER")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(FoyerTheme.gold)
                Text(r.text ?? "")
                    .font(.system(size: 15))
                    .foregroundStyle(FoyerTheme.cream)
                    .lineSpacing(5)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(white: 0.05))
            )
        } else if r.kind == "plan" {
            planCard(r)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func planCard(_ r: APIClient.LeadsAgentReply) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FoyerTheme.gold)
                Text("PROPOSED BATCH SEND")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(FoyerTheme.gold)
                Spacer()
                Text("\(editableRecipients.count) recipient\(editableRecipients.count == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FoyerTheme.creamDim)
            }
            if let s = r.summary, !s.isEmpty {
                Text(s)
                    .font(.system(size: 15))
                    .foregroundStyle(FoyerTheme.cream)
                    .lineSpacing(5)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Subject")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(FoyerTheme.textDim)
                TextField("", text: $editableSubject)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(FoyerTheme.cream)
                    .tint(FoyerTheme.gold)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Color(white: 0.07), in: RoundedRectangle(cornerRadius: 10))
            }

            if !editableRecipients.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recipients")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(FoyerTheme.textDim)
                    VStack(spacing: 8) {
                        ForEach(editableRecipients) { rcp in
                            recipientRow(rcp)
                        }
                    }
                }
            }

            if let skipped = r.skipped, !skipped.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Skipped (\(skipped.count))")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(FoyerTheme.terracotta)
                    ForEach(skipped, id: \.self) { s in
                        Text("• \(s.name) — \(s.reason)")
                            .font(.system(size: 12))
                            .foregroundStyle(FoyerTheme.textDim)
                    }
                }
            }

            HStack {
                Button("Discard") {
                    reply = nil
                    editableRecipients = []
                    editableSubject = ""
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(FoyerTheme.creamDim)
                .buttonStyle(.plain)
                Spacer()
                Button { Task { await sendAll() } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Send all \(editableRecipients.count)")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(FoyerTheme.inkOnGold)
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    .background(FoyerTheme.gold, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(editableRecipients.isEmpty || sending)
            }
            .padding(.top, 4)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(white: 0.05))
        )
    }

    private func recipientRow(_ r: APIClient.LeadsAgentRecipient) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(r.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FoyerTheme.cream)
                Text(r.email)
                    .font(.system(size: 12))
                    .foregroundStyle(FoyerTheme.creamDim)
                Spacer()
                if let addr = r.address, !addr.isEmpty {
                    Text(addr)
                        .font(.system(size: 11))
                        .foregroundStyle(FoyerTheme.textMuted)
                        .lineLimit(1)
                }
            }
            Text(r.body)
                .font(.system(size: 13))
                .foregroundStyle(FoyerTheme.creamDim)
                .lineSpacing(4)
                .lineLimit(4)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func sendResultCard(_ r: APIClient.LeadsAgentExecuteResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: r.failed.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(r.failed.isEmpty ? FoyerTheme.sage : FoyerTheme.terracotta)
                Text(r.failed.isEmpty ? "All sent" : "Partial send")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FoyerTheme.cream)
            }
            Text("Delivered \(r.sent) email\(r.sent == 1 ? "" : "s").")
                .font(.system(size: 13))
                .foregroundStyle(FoyerTheme.creamDim)
            if !r.failed.isEmpty {
                Text("Could not send to:")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FoyerTheme.terracotta)
                ForEach(r.failed, id: \.self) { f in
                    Text("• \(f.name) — \(f.reason)")
                        .font(.system(size: 12))
                        .foregroundStyle(FoyerTheme.textDim)
                }
            }
            HStack {
                Spacer()
                Button("Done") {
                    onCompleted(r.sent)
                    onDismiss()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(FoyerTheme.inkOnGold)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(Capsule().fill(FoyerTheme.gold))
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(white: 0.05))
        )
    }

    @MainActor
    private func ask() async {
        let msg = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty else { return }
        loading = true
        errorMessage = nil
        reply = nil
        editableRecipients = []
        editableSubject = ""
        sendResult = nil
        defer { loading = false }
        do {
            let r = try await APIClient.shared.askLeadsAgent(message: msg)
            reply = r
            if r.kind == "plan" {
                editableSubject = r.subject ?? ""
                editableRecipients = r.recipients ?? []
            }
        } catch {
            errorMessage = "AI agent failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func sendAll() async {
        guard !editableRecipients.isEmpty else { return }
        sending = true
        errorMessage = nil
        defer { sending = false }
        do {
            let result = try await APIClient.shared.executeLeadsAgentPlan(
                subject: editableSubject,
                recipients: editableRecipients
            )
            sendResult = result
        } catch {
            errorMessage = "Bulk send failed: \(error.localizedDescription)"
        }
    }
}

// MARK: – Offers / campaigns

// The Offers tab lets the agent author short marketing angles ("$2,500
// buyer credit", "Saturday 1pm tour", etc.) that the AI can weave into
// outbound emails on demand. Each offer has a short @-reference name
// (used in Refine instructions and the inbox AI: "add @buyerCredit to
// this email" or "send @buyerCredit to all buyer leads") plus a longer
// body that's the actual marketing copy.

private struct IPadOffers: View {
    @State private var offers: [Offer] = []
    @State private var loading: Bool = true
    @State private var loadError: String?
    @State private var editingOffer: Offer?
    @State private var showCreate: Bool = false
    @State private var pendingDelete: Offer?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                header
                if loading && offers.isEmpty {
                    HStack {
                        Spacer()
                        FoyerLoadingView(size: 64, cornerRadius: 10)
                        Spacer()
                    }
                    .padding(.top, 60)
                } else if offers.isEmpty {
                    emptyState
                } else {
                    grid
                }
                if let loadError {
                    Text(loadError)
                        .font(.system(size: 12))
                        .foregroundStyle(FoyerTheme.terracotta)
                }
            }
            .padding(.horizontal, 44)
            .padding(.top, 36)
            .padding(.bottom, 120)
        }
        .refreshable { await load() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .task { await load() }
        .sheet(isPresented: $showCreate) {
            OfferEditorSheet(
                existing: nil,
                onCancel: { showCreate = false },
                onSaved: { offer in
                    offers.append(offer)
                    MentionLibrary.shared.upsert(offer: offer)
                    showCreate = false
                }
            )
        }
        .sheet(item: $editingOffer) { offer in
            OfferEditorSheet(
                existing: offer,
                onCancel: { editingOffer = nil },
                onSaved: { updated in
                    if let idx = offers.firstIndex(where: { $0.id == updated.id }) {
                        offers[idx] = updated
                    }
                    MentionLibrary.shared.upsert(offer: updated)
                    editingOffer = nil
                }
            )
        }
        .alert(
            "Delete this offer?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { offer in
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) {
                Task { await performDelete(offer) }
            }
        } message: { offer in
            Text("Permanently remove @\(offer.name). Any future @reference to it will be ignored. This can't be undone.")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Offers")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(FoyerTheme.cream)
                    .tracking(-0.5)
                Text("Reusable marketing angles. Reference with @name in any AI prompt to weave them into emails.")
                    .font(.system(size: 13))
                    .foregroundStyle(FoyerTheme.textDim)
                    .lineSpacing(3)
            }
            Spacer()
            Button { showCreate = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text("New offer")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(FoyerTheme.inkOnGold)
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(Capsule().fill(FoyerTheme.gold))
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tag")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(FoyerTheme.creamDim.opacity(0.35))
            Text("No offers yet")
                .font(.system(size: 14))
                .foregroundStyle(FoyerTheme.textDim)
            Text("Create a $2,500 buyer credit, a free CMA, an open-house preview — anything you want the AI to mention on demand.")
                .font(.system(size: 12))
                .foregroundStyle(FoyerTheme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .lineSpacing(3)
            Button { showCreate = true } label: {
                Text("Create your first offer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FoyerTheme.inkOnGold)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Capsule().fill(FoyerTheme.gold))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(white: 0.04))
        )
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16)], spacing: 16) {
            ForEach(offers) { offer in
                offerCard(offer)
            }
        }
    }

    private func offerCard(_ offer: Offer) -> some View {
        Button { editingOffer = offer } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(offer.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(FoyerTheme.cream)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Toggle("", isOn: Binding(
                        get: { offer.enabled },
                        set: { newValue in Task { await toggleEnabled(offer, enabled: newValue) } }
                    ))
                    .labelsHidden()
                    .tint(FoyerTheme.gold)
                    .scaleEffect(0.85)
                    Button {
                        pendingDelete = offer
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(FoyerTheme.terracotta.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                Text(offer.body)
                    .font(.system(size: 13))
                    .foregroundStyle(offer.enabled
                                     ? FoyerTheme.creamDim
                                     : FoyerTheme.textMuted)
                    .lineSpacing(4)
                    .lineLimit(5)
                    .multilineTextAlignment(.leading)
                if !offer.enabled {
                    Text("Disabled — AI won't use this offer")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(FoyerTheme.textMuted)
                        .tracking(0.5)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(white: 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(FoyerTheme.hairline, lineWidth: 1)
            )
            .opacity(offer.enabled ? 1 : 0.55)
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func toggleEnabled(_ offer: Offer, enabled: Bool) async {
        do {
            let updated = try await APIClient.shared.setOfferEnabled(
                id: offer.id, enabled: enabled
            )
            if let idx = offers.firstIndex(where: { $0.id == offer.id }) {
                offers[idx] = updated
            }
            MentionLibrary.shared.upsert(offer: updated)
        } catch {
            loadError = "Couldn't update: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func load() async {
        loading = true
        loadError = nil
        defer { loading = false }
        do {
            offers = try await APIClient.shared.listOffers()
            // Keep the @mention picker in sync — the shared library is
            // what powers autocomplete in every input field, so it needs
            // to see the current list, not whatever it cached earlier.
            MentionLibrary.shared.offers = offers
        } catch {
            loadError = "Couldn't load offers: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func performDelete(_ offer: Offer) async {
        do {
            try await APIClient.shared.deleteOffer(id: offer.id)
            offers.removeAll { $0.id == offer.id }
            MentionLibrary.shared.remove(offerId: offer.id)
            pendingDelete = nil
        } catch {
            loadError = "Couldn't delete: \(error.localizedDescription)"
        }
    }
}

private struct OfferEditorSheet: View {
    let existing: Offer?
    var onCancel: () -> Void
    var onSaved: (Offer) -> Void

    @State private var name: String
    @State private var bodyText: String
    @State private var enabled: Bool
    @State private var submitting: Bool = false
    @State private var errorMessage: String?

    init(existing: Offer?, onCancel: @escaping () -> Void, onSaved: @escaping (Offer) -> Void) {
        self.existing = existing
        self.onCancel = onCancel
        self.onSaved = onSaved
        _name = State(initialValue: existing?.name ?? "")
        _bodyText = State(initialValue: existing?.body ?? "")
        _enabled = State(initialValue: existing?.enabled ?? true)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Offer name").font(.system(size: 11, weight: .medium))
                            .foregroundStyle(FoyerTheme.textDim)
                        TextField("e.g. $2,500 buyer credit", text: $name)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(FoyerTheme.cream)
                            .tint(FoyerTheme.gold)
                            .padding(.vertical, 14).padding(.horizontal, 14)
                            .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: 12))
                        Text("Type @ in any AI prompt to reference this offer by name.")
                            .font(.system(size: 11))
                            .foregroundStyle(FoyerTheme.textMuted)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Body").font(.system(size: 11, weight: .medium))
                            .foregroundStyle(FoyerTheme.textDim)
                        TextEditor(text: $bodyText)
                            .font(.system(size: 15))
                            .foregroundStyle(FoyerTheme.cream)
                            .tint(FoyerTheme.gold)
                            .scrollContentBackground(.hidden)
                            .padding(12)
                            .frame(minHeight: 180)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(white: 0.06))
                            )
                        Text("The marketing copy the AI will weave into emails. Describe what the offer is, who qualifies, any deadline, and what action you want the lead to take.")
                            .font(.system(size: 11))
                            .foregroundStyle(FoyerTheme.textMuted)
                            .lineSpacing(2)
                    }

                    Toggle(isOn: $enabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enabled")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(FoyerTheme.cream)
                            Text("When off, the AI ignores this offer even if you @reference it.")
                                .font(.system(size: 11))
                                .foregroundStyle(FoyerTheme.textMuted)
                        }
                    }
                    .tint(FoyerTheme.gold)
                    .padding(.vertical, 14).padding(.horizontal, 14)
                    .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: 12))

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(FoyerTheme.terracotta)
                    }
                }
                .padding(24)
            }
            .background(Color.black)
            .navigationTitle(existing == nil ? "New offer" : "Edit offer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                        .foregroundStyle(FoyerTheme.creamDim)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        if submitting { ProgressView() } else { Text("Save") }
                    }
                    .foregroundStyle(canSave ? FoyerTheme.gold : FoyerTheme.textMuted)
                    .disabled(!canSave || submitting)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var canSave: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty && !trimmedBody.isEmpty
    }

    @MainActor
    private func save() async {
        submitting = true
        errorMessage = nil
        defer { submitting = false }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let offer: Offer
            if let existing {
                offer = try await APIClient.shared.updateOffer(
                    id: existing.id, name: trimmedName,
                    body: trimmedBody, enabled: enabled
                )
            } else {
                offer = try await APIClient.shared.createOffer(
                    name: trimmedName, body: trimmedBody, enabled: enabled
                )
            }
            onSaved(offer)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: – Listings (Spotify — card grid)

// Large image-forward cards arranged in an adaptive grid. Each card jumps
// into the Sign-in tab pre-loaded with that listing. Real listings come
// from store.listings (UserDefaults).
private struct IPadListings: View {
    let store: SessionStore
    var onPickListing: (Listing) -> Void
    var onAdd: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Listings")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(FoyerTheme.cream)
                            .tracking(-0.5)
                        Text("Tap a property to open the sign-in form.")
                            .font(.system(size: 14))
                            .foregroundStyle(FoyerTheme.textDim)
                    }
                    Spacer()
                    Button(action: onAdd) {
                        HStack(spacing: 7) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Add listing")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(FoyerTheme.inkOnGold)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(FoyerTheme.gold, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if store.listings.isEmpty {
                    Button(action: onAdd) { emptyState }
                        .buttonStyle(.plain)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 280), spacing: 18)],
                        spacing: 18
                    ) {
                        ForEach(store.listings) { listing in
                            Button { onPickListing(listing) } label: {
                                card(listing)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 44).padding(.top, 36).padding(.bottom, 120)
        }
        .refreshable { await store.refreshSessions() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private func card(_ listing: Listing) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                if let data = listing.photoData, let img = UIImage(data: data) {
                    Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(
                        colors: [
                            Color(red: 0.12, green: 0.14, blue: 0.19),
                            Color(red: 0.05, green: 0.06, blue: 0.08),
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .overlay(
                        Image(systemName: "house")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(.white.opacity(0.15))
                    )
                }
            }
            .frame(height: 200)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(listing.address)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(FoyerTheme.cream)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if !listing.displayPrice.isEmpty {
                        Text(listing.displayPrice)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(FoyerTheme.gold)
                    }
                    Text(listing.displaySpecs)
                        .font(.system(size: 12))
                        .foregroundStyle(FoyerTheme.textDim)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Color(white: 0.07)).frame(width: 64, height: 64)
                Image(systemName: "house")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(FoyerTheme.creamDim.opacity(0.4))
            }
            Text("No listings yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(FoyerTheme.cream)
            Text("Add open houses from the iPhone app — they'll sync here.")
                .font(.system(size: 13))
                .foregroundStyle(FoyerTheme.textDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
        .background(Color(white: 0.04), in: RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: – Profile (account + integrations + settings)

// Settings-style tab pulled out of the side rail's avatar. Surfaces the
// agent's Google account info, the default script that applies to every
// session unless overridden, the Gmail connection status, and a sign-out.
// All state comes from existing singletons — no new persistence layer.
private struct IPadProfile: View {
    let store: SessionStore
    let auth: AuthStore

    @State private var gmail: APIClient.GmailStatus?
    @State private var gmailLoading: Bool = false
    @State private var gmailError: String?
    @State private var showGmailConnect: Bool = false
    @State private var showSignOutConfirm: Bool = false
    // Local draft of the Send-as alias. Reset to the backend's value
    // on every refresh so a Cancel discards anything in flight.
    @State private var sendAsDraft: String = ""
    @State private var sendAsSaving: Bool = false
    @State private var sendAsMessage: String?

    // Templates state
    @State private var templates: [FollowupTemplate] = []
    @State private var forceTemplates: Bool = false
    @State private var templatesLoading: Bool = false
    @State private var templatesError: String?
    @State private var editingTemplate: FollowupTemplate?
    @State private var showNewTemplate: Bool = false

    // Follow Up Boss state — Keychain-backed, so we just track display state.
    @State private var fubConnected: Bool = FUBCredential.isConnected
    @State private var fubName: String? = nil
    @State private var showFubSheet: Bool = false

    // Scripts state
    @State private var scriptsError: String?
    @State private var editingScriptId: String? = nil
    @State private var showNewScript: Bool = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                header
                accountCard
                gmailCard
                if gmail?.connected == true {
                    sendAsCard
                }
                templatesCard
                scriptsCard
                fubCard
                #if DEBUG
                devModeCard
                #endif
                signOutCard
                Spacer().frame(height: 80)
            }
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 44).padding(.top, 36).padding(.bottom, 120)
        }
        .refreshable {
            await refreshGmail()
            await loadTemplates()
            await store.refreshScripts()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .task { await refreshGmail() }
        .task { await loadTemplates() }
        .task { await store.refreshScripts() }
        .sheet(isPresented: $showGmailConnect) {
            GmailConnectSheet(
                onConnected: { _ in
                    showGmailConnect = false
                    Task { await refreshGmail() }
                },
                onCancel: { showGmailConnect = false }
            )
        }
        .sheet(isPresented: $showNewTemplate) {
            TemplateEditorSheet(
                existing: nil,
                onCancel: { showNewTemplate = false },
                onSaved: { _ in
                    showNewTemplate = false
                    Task { await loadTemplates() }
                }
            )
        }
        .sheet(item: $editingTemplate) { template in
            TemplateEditorSheet(
                existing: template,
                onCancel: { editingTemplate = nil },
                onSaved: { _ in
                    editingTemplate = nil
                    Task { await loadTemplates() }
                }
            )
        }
        .sheet(isPresented: $showFubSheet) {
            FUBConnectSheetIPad(
                connectedName: $fubName,
                onClose: {
                    showFubSheet = false
                    fubConnected = FUBCredential.isConnected
                }
            )
        }
        .sheet(isPresented: $showNewScript) {
            ScriptEditorSheet(
                existingId: nil,
                onCancel: { showNewScript = false },
                onSaved: {
                    showNewScript = false
                    Task { await store.refreshScripts() }
                }
            )
        }
        .sheet(item: Binding(
            get: { editingScriptId.map { ScriptIdRef(id: $0) } },
            set: { editingScriptId = $0?.id }
        )) { ref in
            ScriptEditorSheet(
                existingId: ref.id,
                onCancel: { editingScriptId = nil },
                onSaved: {
                    editingScriptId = nil
                    Task { await store.refreshScripts() }
                }
            )
        }
        .alert("Sign out?", isPresented: $showSignOutConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Sign out", role: .destructive) { auth.signOut() }
        } message: {
            Text("You'll need to sign back in with Google to access your sessions and leads.")
        }
    }

    private var fubCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(
                icon: "arrow.triangle.branch",
                title: "Follow Up Boss",
                subtitle: "Push captured leads into FUB on send."
            )
            HStack(spacing: 12) {
                Circle()
                    .fill(fubConnected ? FoyerTheme.sage : FoyerTheme.creamDim.opacity(0.4))
                    .frame(width: 10, height: 10)
                Text(fubConnected ? "Connected" : "Not connected")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FoyerTheme.cream)
                Spacer()
                Button { showFubSheet = true } label: {
                    Text(fubConnected ? "Manage" : "Connect")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(fubConnected ? FoyerTheme.creamDim : FoyerTheme.inkOnGold)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(fubConnected
                                    ? Color(white: 0.08)
                                    : FoyerTheme.gold,
                                    in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(Color(white: 0.05), in: RoundedRectangle(cornerRadius: 16))
    }

    private var scriptsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(
                icon: "doc.text.fill",
                title: "Open-house scripts",
                subtitle: "Drives coaching + per-session coverage grading."
            )

            // Default script row (Menu) — preserved so the agent can flip
            // defaults in the same card instead of digging through a sheet.
            Menu {
                Button {
                    store.defaultScriptId = nil
                } label: {
                    HStack {
                        Text("No default")
                        if store.defaultScriptId == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                if !store.availableScripts.isEmpty {
                    Divider()
                    ForEach(store.availableScripts) { s in
                        Button {
                            store.defaultScriptId = s.id
                        } label: {
                            HStack {
                                Text(s.name)
                                if store.defaultScriptId == s.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(FoyerTheme.gold)
                    Text("Default for new sessions")
                        .font(.system(size: 13))
                        .foregroundStyle(FoyerTheme.creamDim)
                    Spacer()
                    Text(currentScriptLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(FoyerTheme.cream)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(FoyerTheme.creamDim)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 12))
            }

            if store.availableScripts.isEmpty {
                Text("No scripts loaded yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(FoyerTheme.textDim)
            } else {
                VStack(spacing: 8) {
                    ForEach(store.availableScripts) { s in
                        scriptRow(s)
                    }
                }
            }
            HStack {
                Spacer()
                Button { showNewScript = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("New script")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(FoyerTheme.inkOnGold)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(FoyerTheme.gold, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            if let err = scriptsError {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(FoyerTheme.terracotta)
            }
        }
        .padding(20)
        .background(Color(white: 0.05), in: RoundedRectangle(cornerRadius: 16))
    }

    private func scriptRow(_ s: ScriptSummary) -> some View {
        let isDefault = store.defaultScriptId == s.id
        let editable = !s.isPreset
        return Button {
            if editable { editingScriptId = s.id }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(s.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(FoyerTheme.cream)
                        if s.isPreset {
                            Text("PRESET")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .tracking(1.2)
                                .foregroundStyle(FoyerTheme.textMuted)
                        }
                        if isDefault {
                            Text("DEFAULT")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .tracking(1.2)
                                .foregroundStyle(FoyerTheme.gold)
                        }
                    }
                    Text("\(s.stepCount) steps · \(s.description)")
                        .font(.system(size: 12))
                        .foregroundStyle(FoyerTheme.textDim)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: editable ? "chevron.right" : "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FoyerTheme.creamDim)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!editable)
    }

    private var currentScriptLabel: String {
        if let id = store.defaultScriptId,
           let s = store.availableScripts.first(where: { $0.id == id }) {
            return s.name
        }
        return "None"
    }

    private var templatesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(
                icon: "doc.on.doc.fill",
                title: "Follow-up templates",
                subtitle: "Designs the AI uses when drafting follow-ups."
            )
            Toggle(isOn: Binding(
                get: { forceTemplates },
                set: { newValue in Task { await setForce(newValue) } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Always use a template")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(FoyerTheme.cream)
                    Text(forceTemplates
                         ? "AI uses the best-fit template verbatim (filling {slots})."
                         : "AI picks a template only when one clearly fits; rewrites freely.")
                        .font(.system(size: 12))
                        .foregroundStyle(FoyerTheme.textDim)
                }
            }
            .tint(FoyerTheme.gold)

            if templates.isEmpty {
                Text("No templates yet. Add one to bias follow-ups toward your voice.")
                    .font(.system(size: 12))
                    .foregroundStyle(FoyerTheme.textDim)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 8) {
                    ForEach(templates) { t in
                        templateRow(t)
                    }
                }
            }

            HStack {
                Spacer()
                Button { showNewTemplate = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("New template")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(FoyerTheme.inkOnGold)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(FoyerTheme.gold, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if let err = templatesError {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(FoyerTheme.terracotta)
            }

            Text("Use `{first_name}`, `{full_name}` (auto-filled), or any other `{slot}` you want the AI (soft mode) or yourself (forced mode) to fill in.")
                .font(.system(size: 11))
                .foregroundStyle(FoyerTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(Color(white: 0.05), in: RoundedRectangle(cornerRadius: 16))
    }

    private func templateRow(_ t: FollowupTemplate) -> some View {
        Button { editingTemplate = t } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(t.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FoyerTheme.cream)
                    if !t.matchHints.isEmpty {
                        Text(t.matchHints)
                            .font(.system(size: 12))
                            .foregroundStyle(FoyerTheme.textDim)
                            .lineLimit(1)
                    } else if !t.subject.isEmpty {
                        Text(t.subject)
                            .font(.system(size: 12))
                            .foregroundStyle(FoyerTheme.textDim)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FoyerTheme.creamDim)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func loadTemplates() async {
        templatesLoading = true
        defer { templatesLoading = false }
        do {
            let env = try await APIClient.shared.listTemplates()
            templates = env.templates
            forceTemplates = env.forceTemplates
            templatesError = nil
            // Keep the @mention picker in sync — it pulls from the same
            // library and otherwise wouldn't see template changes until
            // the next app launch.
            MentionLibrary.shared.templates = env.templates
        } catch {
            templatesError = error.localizedDescription
        }
    }

    @MainActor
    private func setForce(_ force: Bool) async {
        forceTemplates = force
        do {
            _ = try await APIClient.shared.setForceTemplates(force)
        } catch {
            forceTemplates = !force
            templatesError = error.localizedDescription
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PROFILE")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(2.0)
                .foregroundStyle(FoyerTheme.gold)
            Text("Settings")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(FoyerTheme.cream)
                .tracking(-0.6)
        }
    }

    private var accountCard: some View {
        HStack(spacing: 16) {
            avatarBubble
            VStack(alignment: .leading, spacing: 3) {
                Text(auth.currentUser?.name ?? "Signed in")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(FoyerTheme.cream)
                Text(auth.currentUser?.email ?? "")
                    .font(.system(size: 13))
                    .foregroundStyle(FoyerTheme.textDim)
            }
            Spacer()
        }
        .padding(18)
        .background(Color(white: 0.05), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var avatarBubble: some View {
        if let str = auth.currentUser?.picture, let url = URL(string: str) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                default:
                    initialsBubble
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(Circle())
        } else {
            initialsBubble
        }
    }

    private var initialsBubble: some View {
        let name = auth.currentUser?.name ?? auth.currentUser?.email ?? "?"
        let initials = name.split(separator: " ").prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined().uppercased()
        return Text(initials.isEmpty ? "?" : initials)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(FoyerTheme.creamDim)
            .frame(width: 60, height: 60)
            .background(FoyerTheme.bgElev, in: Circle())
    }

    private var gmailCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(
                icon: "envelope.fill",
                title: "Gmail",
                subtitle: "Send follow-ups from your own address."
            )
            HStack(spacing: 12) {
                connectionDot
                VStack(alignment: .leading, spacing: 2) {
                    Text(gmailStatusLine)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FoyerTheme.cream)
                    if let err = gmailError {
                        Text(err)
                            .font(.system(size: 11))
                            .foregroundStyle(FoyerTheme.terracotta)
                    } else if let addr = gmail?.email {
                        Text(addr)
                            .font(.system(size: 12))
                            .foregroundStyle(FoyerTheme.textDim)
                    }
                }
                Spacer()
                gmailActionButton
            }
        }
        .padding(20)
        .background(Color(white: 0.05), in: RoundedRectangle(cornerRadius: 16))
    }

    private var connectionDot: some View {
        Circle()
            .fill(gmail?.connected == true ? FoyerTheme.sage : FoyerTheme.creamDim.opacity(0.4))
            .frame(width: 10, height: 10)
    }

    private var gmailStatusLine: String {
        if gmailLoading && gmail == nil { return "Checking…" }
        return gmail?.connected == true ? "Connected" : "Not connected"
    }

    @ViewBuilder
    private var gmailActionButton: some View {
        if gmail?.connected == true {
            Button { Task { await disconnectGmail() } } label: {
                Text(gmailLoading ? "Working…" : "Disconnect")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FoyerTheme.terracotta)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(FoyerTheme.terracotta.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(gmailLoading)
        } else {
            Button { showGmailConnect = true } label: {
                Text("Connect")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FoyerTheme.inkOnGold)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(FoyerTheme.gold, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var signOutCard: some View {
        Button { showSignOutConfirm = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                Text("Sign out")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(FoyerTheme.terracotta)
            .padding(20)
            .background(FoyerTheme.terracotta.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    #if DEBUG
    // Dev-only knobs for friends-and-family testing. Visible only in Debug
    // builds — the whole card disappears when the app ships. Delete this
    // computed property + DevMode.swift to fully strip the feature.
    private var devModeCard: some View {
        @Bindable var settings = DevSettings.shared
        return VStack(alignment: .leading, spacing: 14) {
            cardHeader(
                icon: "wrench.and.screwdriver",
                title: "Developer",
                subtitle: "Pre-launch testing knobs — not visible in shipped builds."
            )
            Toggle(isOn: $settings.fasterSnapshots) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("1-minute snapshot cadence")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(FoyerTheme.cream)
                    Text("Fires a light pipeline pass every 60 seconds during recording instead of waiting 5+ minutes between updates. Burns API credits faster — use only for testing.")
                        .font(.system(size: 12))
                        .foregroundStyle(FoyerTheme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(FoyerTheme.gold)
        }
        .padding(20)
        .background(Color(white: 0.05), in: RoundedRectangle(cornerRadius: 16))
    }
    #endif

    private var sendAsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(
                icon: "at",
                title: "Send mail as",
                subtitle: "Stamp follow-ups with a different From address."
            )
            Text("Verify the alias in Gmail first (Settings → Accounts → Send mail as). Gmail silently falls back to your connected address if it isn't verified.")
                .font(.system(size: 12))
                .foregroundStyle(FoyerTheme.creamDim)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)

            HStack(spacing: 10) {
                TextField(gmail?.email ?? "name@company.com", text: $sendAsDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.emailAddress)
                    .font(.system(size: 14))
                    .foregroundStyle(FoyerTheme.cream)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 12))

                Button { Task { await saveSendAs(clear: false) } } label: {
                    Text(sendAsSaving ? "Saving…" : "Save")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FoyerTheme.inkOnGold)
                        .padding(.horizontal, 16).padding(.vertical, 11)
                        .background(FoyerTheme.gold, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(sendAsSaving)

                if let current = gmail?.sendFrom, !current.isEmpty {
                    Button { Task { await saveSendAs(clear: true) } } label: {
                        Text("Clear")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(FoyerTheme.creamDim)
                            .padding(.horizontal, 14).padding(.vertical, 11)
                            .background(Color(white: 0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(sendAsSaving)
                }
            }

            if let current = gmail?.sendFrom, !current.isEmpty {
                HStack(spacing: 8) {
                    Circle().fill(FoyerTheme.sage).frame(width: 6, height: 6)
                    Text("Sending as ")
                        .foregroundStyle(FoyerTheme.textDim) +
                    Text(current)
                        .foregroundStyle(FoyerTheme.cream) +
                    Text(" via \(gmail?.email ?? "")")
                        .foregroundStyle(FoyerTheme.textDim)
                }
                .font(.system(size: 12))
            }

            if let msg = sendAsMessage {
                Text(msg)
                    .font(.system(size: 12))
                    .foregroundStyle(FoyerTheme.terracotta)
            }
        }
        .padding(20)
        .background(Color(white: 0.05), in: RoundedRectangle(cornerRadius: 16))
    }

    @MainActor
    private func saveSendAs(clear: Bool) async {
        sendAsSaving = true
        sendAsMessage = nil
        defer { sendAsSaving = false }
        do {
            let address: String? = clear ? nil : sendAsDraft.trimmingCharacters(in: .whitespaces)
            let updated = try await APIClient.shared.setGmailSendFrom(
                address: (address?.isEmpty == true) ? nil : address
            )
            gmail = updated
            sendAsDraft = updated.sendFrom ?? ""
        } catch {
            sendAsMessage = error.localizedDescription
        }
    }

    private func cardHeader(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(FoyerTheme.gold)
                .frame(width: 32, height: 32)
                .background(FoyerTheme.goldSoft, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FoyerTheme.cream)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(FoyerTheme.textDim)
            }
            Spacer()
        }
    }

    @MainActor
    private func refreshGmail() async {
        gmailLoading = true
        gmailError = nil
        defer { gmailLoading = false }
        do {
            let status = try await APIClient.shared.gmailStatus()
            gmail = status
            // Seed the draft with whatever the server thinks is current.
            sendAsDraft = status.sendFrom ?? ""
        } catch {
            gmailError = error.localizedDescription
        }
    }

    @MainActor
    private func disconnectGmail() async {
        gmailLoading = true
        gmailError = nil
        defer { gmailLoading = false }
        do {
            try await APIClient.shared.disconnectGmail()
            gmail = nil
            await refreshGmail()
        } catch {
            gmailError = error.localizedDescription
        }
    }
}

// MARK: – Post-sign-in welcome animation

// Plays once per cold launch, layered over the iPad app. A pair of cyan
// rings ripple outward from center, a checkmark draws into a filled cyan
// disc, then "Welcome, [name]" fades up underneath. After ~2 seconds the
// parent fades the whole overlay out and the home content takes over.
private struct WelcomeOverlay: View {
    let name: String
    let greeting: String

    @State private var ringScale: CGFloat = 0.4
    @State private var ringOpacity: Double = 0
    @State private var discScale: CGFloat = 0.0
    @State private var checkProgress: CGFloat = 0
    @State private var textOpacity: Double = 0
    @State private var textOffset: CGFloat = 14

    var body: some View {
        ZStack {
            Color.black

            VStack(spacing: 28) {
                ZStack {
                    // Two ripples on a stagger so it reads as a pulse.
                    Circle()
                        .stroke(FoyerTheme.gold.opacity(0.5), lineWidth: 1.5)
                        .frame(width: 140, height: 140)
                        .scaleEffect(ringScale)
                        .opacity(ringOpacity)
                    Circle()
                        .stroke(FoyerTheme.gold.opacity(0.3), lineWidth: 1)
                        .frame(width: 200, height: 200)
                        .scaleEffect(ringScale * 1.05)
                        .opacity(ringOpacity * 0.7)

                    // Filled cyan disc with a check drawn into it.
                    Circle()
                        .fill(FoyerTheme.gold)
                        .frame(width: 88, height: 88)
                        .scaleEffect(discScale)
                        .shadow(color: FoyerTheme.gold.opacity(0.4), radius: 24, y: 8)

                    Check()
                        .trim(from: 0, to: checkProgress)
                        .stroke(FoyerTheme.inkOnGold,
                                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                        .frame(width: 40, height: 32)
                        .opacity(discScale > 0.6 ? 1 : 0)
                }
                .frame(height: 220)

                VStack(spacing: 6) {
                    Text(greeting)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(FoyerTheme.creamDim)
                    Text(name)
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(FoyerTheme.cream)
                        .tracking(-0.8)
                }
                .opacity(textOpacity)
                .offset(y: textOffset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onAppear { runAnimation() }
    }

    private func runAnimation() {
        // Rings expand + fade in
        withAnimation(.easeOut(duration: 0.9)) {
            ringScale = 1.2
            ringOpacity = 1
        }
        withAnimation(.easeOut(duration: 1.4).delay(0.15)) {
            ringScale = 1.8
            ringOpacity = 0
        }
        // Disc pops in with a slight overshoot
        withAnimation(.spring(response: 0.55, dampingFraction: 0.62).delay(0.20)) {
            discScale = 1.0
        }
        // Check draws after the disc settles
        withAnimation(.easeOut(duration: 0.45).delay(0.55)) {
            checkProgress = 1.0
        }
        // Name slides up and fades in
        withAnimation(.easeOut(duration: 0.55).delay(0.75)) {
            textOpacity = 1
            textOffset = 0
        }
    }
}

// MARK: – Gmail connect sheet

// Shown when the agent taps Send and the backend reports Gmail isn't yet
// connected. One CTA: open the ASWebAuthenticationSession that runs the
// Gmail-send OAuth grant. On success we fire `onConnected(true)` and the
// caller re-tries the send; on cancel we fire `onConnected(false)`.
private struct GmailConnectSheet: View {
    var onConnected: (Bool) -> Void
    var onCancel: () -> Void

    @State private var connecting = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(FoyerTheme.gold)
                    .frame(width: 44, height: 44)
                    .background(FoyerTheme.goldSoft, in: RoundedRectangle(cornerRadius: 12))
                Spacer()
                Button { onCancel() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FoyerTheme.creamDim)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Connect Gmail")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(FoyerTheme.cream)
                    .tracking(-0.4)
                Text("Send follow-ups directly from your Gmail. The agent's address is used for replies — guests reply to you, not to us.")
                    .font(.system(size: 14))
                    .foregroundStyle(FoyerTheme.creamDim)
                    .lineSpacing(4)
            }

            VStack(alignment: .leading, spacing: 12) {
                bullet("Sends from your own email address")
                bullet("Stored only as a refresh token — no inbox access")
                bullet("Disconnect anytime in your Google account settings")
            }

            if let error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(FoyerTheme.terracotta)
            }

            Spacer()

            Button { Task { await connect() } } label: {
                HStack(spacing: 10) {
                    if connecting {
                        ProgressView().scaleEffect(0.7).tint(FoyerTheme.inkOnGold)
                    } else {
                        Image(systemName: "envelope.badge")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text(connecting ? "Opening Google…" : "Continue with Google")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(FoyerTheme.inkOnGold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(FoyerTheme.gold, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(connecting)
        }
        .padding(28)
        .frame(maxWidth: 460, maxHeight: 540)
        .background(Color(white: 0.06))
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(FoyerTheme.gold).frame(width: 5, height: 5).padding(.top, 7)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(FoyerTheme.creamDim)
        }
    }

    @MainActor
    private func connect() async {
        connecting = true
        error = nil
        defer { connecting = false }
        // Resolve a presentation anchor from the active scene's key window
        // so ASWebAuthenticationSession knows what to attach to.
        let anchor: ASPresentationAnchor = {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow) ?? UIWindow()
        }()
        do {
            try await GmailConnectDriver.run(presentationAnchor: anchor)
            onConnected(true)
        } catch GmailConnectDriver.ConnectError.cancelled {
            // User dismissed the web sheet without consenting — just stay
            // on this sheet so they can retry.
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// Check mark shape — three points: down-left, center-low, up-right.
// Drawn inside a 40×32 bounding box so it scales cleanly inside the disc.
private struct Check: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + rect.width * 0.10,
                           y: rect.minY + rect.height * 0.55))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.40,
                              y: rect.minY + rect.height * 0.88))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.92,
                              y: rect.minY + rect.height * 0.18))
        return p
    }
}

// MARK: – Listing editor (with MapKit address validation)

// Sheet presented from Listings tab + the Kiosk launcher. Wraps the
// existing Listing model — same data shape the iPhone editor produces, so
// the listings UserDefaults blob stays compatible. Address input uses
// MKLocalSearchCompleter for live suggestions; picking one runs an
// MKLocalSearch to confirm the address resolves to a real place and
// pulls a canonical postal-formatted string back into the field.
private struct IPadListingEditor: View {
    let store: SessionStore
    var onDone: (Listing?) -> Void

    @State private var address: String = ""
    @State private var neighborhood: String = ""
    @State private var priceText: String = ""
    @State private var beds: Int = 0
    @State private var baths: Double = 0
    @State private var sqftText: String = ""
    @State private var addressValidated: Bool = false

    @StateObject private var completer = AddressCompleter()
    @State private var showSuggestions: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    addressField

                    HStack(spacing: 10) {
                        textField(label: "Neighborhood", value: $neighborhood, keyboard: .default)
                    }

                    HStack(spacing: 10) {
                        textField(label: "Price", value: $priceText, keyboard: .numberPad)
                        textField(label: "Sq ft", value: $sqftText, keyboard: .numberPad)
                    }

                    HStack(spacing: 10) {
                        stepperField(label: "Beds", value: $beds, range: 0...10, step: 1, format: { "\($0)" })
                        stepperField(label: "Baths", value: $beds, range: 0...10, step: 1, format: { "\($0)" })
                            .hidden()  // baths uses different stepper
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Baths").font(.system(size: 11, weight: .medium))
                                .foregroundStyle(FoyerTheme.textDim)
                            HStack {
                                Text(bathsString)
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(FoyerTheme.cream)
                                Spacer()
                                Stepper("", value: $baths, in: 0...10, step: 0.5)
                                    .labelsHidden()
                            }
                            .padding(.vertical, 10).padding(.horizontal, 14)
                            .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding(24)
            }
            .background(Color.black)
            .navigationTitle("New listing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDone(nil) }
                        .foregroundStyle(FoyerTheme.creamDim)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .foregroundStyle(canSave ? FoyerTheme.gold : FoyerTheme.textMuted)
                        .disabled(!canSave)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: address) { _, newValue in
            completer.update(query: newValue)
            addressValidated = false
            showSuggestions = !newValue.isEmpty
        }
    }

    private var bathsString: String {
        baths.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(baths))"
            : String(format: "%.1f", baths)
    }

    @ViewBuilder
    private var addressField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Address")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FoyerTheme.textDim)
                Spacer()
                if addressValidated {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(FoyerTheme.sage)
                        Text("Verified on Maps")
                            .font(.system(size: 10))
                            .foregroundStyle(FoyerTheme.textDim)
                    }
                }
            }

            TextField("", text: $address,
                      prompt: Text("Start typing an address…").foregroundStyle(FoyerTheme.textMuted))
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(FoyerTheme.cream)
                .tint(FoyerTheme.gold)
                .textContentType(.fullStreetAddress)
                .autocorrectionDisabled()
                .padding(.vertical, 14).padding(.horizontal, 16)
                .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(addressValidated ? FoyerTheme.sage.opacity(0.5) : Color.clear, lineWidth: 1)
                )

            if showSuggestions && !completer.results.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(completer.results.prefix(5).enumerated()), id: \.offset) { _, item in
                        Button { selectSuggestion(item) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.system(size: 12))
                                    .foregroundStyle(FoyerTheme.gold)
                                    .padding(.top, 2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(FoyerTheme.cream)
                                    Text(item.subtitle)
                                        .font(.system(size: 12))
                                        .foregroundStyle(FoyerTheme.textDim)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if item !== completer.results.prefix(5).last {
                            Hairline()
                        }
                    }
                }
                .background(Color(white: 0.05), in: RoundedRectangle(cornerRadius: 12))
                .padding(.top, 2)
            }
        }
    }

    private func textField(label: String, value: Binding<String>, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 11, weight: .medium))
                .foregroundStyle(FoyerTheme.textDim)
            TextField("", text: value)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(FoyerTheme.cream)
                .tint(FoyerTheme.gold)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .padding(.vertical, 14).padding(.horizontal, 14)
                .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func stepperField(label: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int, format: @escaping (Int) -> String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 11, weight: .medium))
                .foregroundStyle(FoyerTheme.textDim)
            HStack {
                Text(format(value.wrappedValue))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(FoyerTheme.cream)
                Spacer()
                Stepper("", value: value, in: range, step: step)
                    .labelsHidden()
            }
            .padding(.vertical, 10).padding(.horizontal, 14)
            .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var canSave: Bool {
        !address.trimmingCharacters(in: .whitespaces).isEmpty && addressValidated
    }

    private func selectSuggestion(_ item: MKLocalSearchCompletion) {
        showSuggestions = false
        // Run a real search against MapKit so we get back a precise
        // postal-formatted line; this is what marks the address as
        // "verified". The full title + subtitle becomes the canonical
        // address stored on the Listing.
        let request = MKLocalSearch.Request(completion: item)
        MKLocalSearch(request: request).start { response, _ in
            DispatchQueue.main.async {
                if let mapItem = response?.mapItems.first {
                    let line = postalLine(for: mapItem)
                    address = line.isEmpty ? "\(item.title) \(item.subtitle)" : line
                    addressValidated = true
                } else {
                    address = "\(item.title) \(item.subtitle)"
                    addressValidated = true
                }
            }
        }
    }

    private func postalLine(for item: MKMapItem) -> String {
        // Build the canonical address from CLPlacemark fields. Avoids
        // pulling in the Contacts framework just for CNPostalAddress.
        let pm = item.placemark
        let street: String = {
            let num = pm.subThoroughfare ?? ""
            let road = pm.thoroughfare ?? ""
            return [num, road].filter { !$0.isEmpty }.joined(separator: " ")
        }()
        let parts = [street, pm.locality ?? "", pm.administrativeArea ?? "", pm.postalCode ?? ""]
            .filter { !$0.isEmpty }
        return parts.joined(separator: ", ")
    }

    private func save() {
        let listing = Listing(
            id: UUID().uuidString,
            address: address.trimmingCharacters(in: .whitespaces),
            neighborhood: neighborhood.trimmingCharacters(in: .whitespaces),
            price: Int(priceText.filter(\.isNumber)) ?? 0,
            beds: beds,
            baths: baths,
            sqft: Int(sqftText.filter(\.isNumber)) ?? 0,
            photoData: nil
        )
        store.addListing(listing)
        onDone(listing)
    }
}

// MARK: – MapKit autocomplete adapter

// Thin ObservableObject wrapping MKLocalSearchCompleter so the listing
// editor can observe live address suggestions as the agent types.
@MainActor
private final class AddressCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []

    private let completer: MKLocalSearchCompleter = {
        let c = MKLocalSearchCompleter()
        c.resultTypes = .address
        return c
    }()

    override init() {
        super.init()
        completer.delegate = self
    }

    func update(query: String) {
        completer.queryFragment = query
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let snapshot = completer.results
        Task { @MainActor in
            self.results = snapshot
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.results = []
        }
    }
}

// MARK: – Record (iPad recording surface)

// Three-state surface that mirrors the iPhone LiveView + SummaryView flow:
//   1. setup    — pick a listing (or none), set the guest count, tap Begin
//   2. recording — cinematic mic + live waveform + elapsed timer + End
//   3. done     — processing card → ready summary with a CTA to Leads
// State comes from SessionStore.phase, which moves through .uploading →
// .processing → .ready as the upload + diarization job completes. Pressing
// End hands the audio off to SessionStore.uploadAndProcess and resets the
// recorder; we stay on this view so the agent can watch the job finish.
private struct IPadRecord: View {
    let store: SessionStore
    let listing: Listing?
    var onSelectListing: (Listing) -> Void
    var onOpenLeads: (String) -> Void
    // Called when the final-pass snapshot finishes and the session is ready.
    // The parent uses this to navigate the user directly to Session detail
    // instead of stopping at a "Session ready / Open leads" prompt — which
    // was extra clicks for what's obviously the next step.
    var onOpenSession: (String) -> Void

    // Shared recorder so the recording survives tab switches — the agent
    // can start recording, then jump to the Kiosk tab to take guest sign-ins
    // while the mic keeps capturing in the background.
    @State private var recorder = AudioRecorder.shared
    @State private var permissionDenied = false
    @State private var paused = false
    // Guard so onOpenSession only fires once per session — onChange will
    // otherwise re-fire if the user navigates back to Record while a ready
    // session is still on the store.
    @State private var openedSessionId: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
        }
        .onAppear {
            resetIfFinishedSession()
            paused = recorder.isPaused
        }
        // When the End-Session pass finishes, auto-navigate to the Session
        // detail. Without this the agent landed on a prompt pane asking
        // which screen to go to — the answer is almost always "open the
        // session I just finished," so just do it.
        .onChange(of: store.phase) { _, newPhase in
            if case .ready = newPhase,
               let id = store.session?.id,
               openedSessionId != id {
                openedSessionId = id
                onOpenSession(id)
                store.reset()
            }
        }
        .alert("Microphone access needed", isPresented: $permissionDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Enable microphone access in Settings to record audio.")
        }
    }

    @ViewBuilder
    private var content: some View {
        // Drive the visible state off the recorder + store. The recorder
        // owns the "currently capturing" bit; the store owns the post-end
        // upload/processing/ready lifecycle.
        if recorder.isRecording {
            recordingPane
        } else {
            switch store.phase {
            case .uploading, .processing:
                processingPane
            case .ready:
                readyPane
            case .failed(let msg):
                failedPane(msg)
            case .idle:
                setupPane
            }
        }
    }

    // MARK: Setup

    // Mirrors the kiosk launcher pattern the user already validated: a list
    // of listing rows each with its own Record button, plus a "Record
    // without a listing" fallback for the no-listing path. No address field
    // and no guests selector — if the agent wants the address attached to
    // the session, they pick the listing. Speaker count is left on auto
    // (AssemblyAI's default) which handles 1-to-many open houses cleanly.
    private var setupPane: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                header
                if store.listings.isEmpty {
                    emptyListingsLauncher
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(store.listings) { listing in
                            launchRow(listing)
                        }
                        Button { Task { await beginRecording(with: nil) } } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Record without a listing")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundStyle(FoyerTheme.creamDim)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Color.white.opacity(0.06), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 6)
                    }
                }
                if !store.pendingKioskGuests.isEmpty {
                    kioskGuestsNote
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 44).padding(.top, 36).padding(.bottom, 120)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RECORD")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(2.0)
                .foregroundStyle(FoyerTheme.gold)
            Text("Start a session")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(FoyerTheme.cream)
                .tracking(-0.6)
            Text("Pick the listing you're walking through — we'll attach it to the session.")
                .font(.system(size: 14))
                .foregroundStyle(FoyerTheme.textDim)
                .lineSpacing(3)
                .padding(.top, 2)
        }
    }

    private func launchRow(_ listing: Listing) -> some View {
        HStack(spacing: 14) {
            listingThumb(listing)
                .frame(width: 84, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(listing.address)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(FoyerTheme.cream)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if !listing.displayPrice.isEmpty {
                        Text(listing.displayPrice)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(FoyerTheme.gold)
                    }
                    Text(listing.displaySpecs)
                        .font(.system(size: 12))
                        .foregroundStyle(FoyerTheme.textDim)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button { Task { await beginRecording(with: listing) } } label: {
                HStack(spacing: 6) {
                    Circle().fill(.white).frame(width: 8, height: 8)
                    Text("Record")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(FoyerTheme.terracotta, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    private var emptyListingsLauncher: some View {
        Button { Task { await beginRecording(with: nil) } } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(.white.opacity(0.18)).frame(width: 32, height: 32)
                    Circle().fill(.white).frame(width: 12, height: 12)
                }
                Text("Begin recording")
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(FoyerTheme.terracotta, in: RoundedRectangle(cornerRadius: 18))
            .shadow(color: FoyerTheme.terracotta.opacity(0.4), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func listingThumb(_ listing: Listing) -> some View {
        if let data = listing.photoData, let img = UIImage(data: data) {
            Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.12, blue: 0.16),
                    Color(red: 0.03, green: 0.04, blue: 0.06),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .overlay(
                Image(systemName: "house")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(.white.opacity(0.18))
            )
        }
    }

    private var kioskGuestsNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(FoyerTheme.gold)
            Text("\(store.pendingKioskGuests.count) signed in at the kiosk — we'll match voices to them after the session.")
                .font(.system(size: 12))
                .foregroundStyle(FoyerTheme.creamDim)
                .lineLimit(2)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(FoyerTheme.goldSoft.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }

    private func resetIfFinishedSession() {
        // If the user navigates into Record after a prior session finished,
        // clear the old phase so they see Setup again instead of a stale
        // ready/failed pane.
        if case .ready = store.phase { store.reset() }
        if case .failed = store.phase { store.reset() }
    }

    // MARK: Recording

    private var recordingPane: some View {
        VStack(spacing: 0) {
            recordingHeader
            Spacer(minLength: 0)
            voiceVisualizer
                .padding(.horizontal, 56)
            Spacer(minLength: 0)
            recordingControls
                .padding(.horizontal, 56).padding(.bottom, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recordingHeader: some View {
        HStack(spacing: 14) {
            HStack(spacing: 7) {
                Circle()
                    .fill(paused ? FoyerTheme.creamDim : FoyerTheme.terracotta)
                    .frame(width: 8, height: 8)
                    .modifier(PulseAnimation())
                Text(paused ? "PAUSED" : "LIVE")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(2.0)
                    .foregroundStyle(paused ? FoyerTheme.creamDim : FoyerTheme.terracotta)
            }
            #if DEBUG
            if DevSettings.shared.anyEnabled {
                Text("DEV")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(FoyerTheme.gold)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(FoyerTheme.gold.opacity(0.15)))
                    .overlay(Capsule().stroke(FoyerTheme.gold.opacity(0.4), lineWidth: 0.5))
            }
            #endif
            snapshotPill
            Spacer()
            Text(timeString)
                .font(.system(size: 22, weight: .medium, design: .monospaced))
                .foregroundStyle(FoyerTheme.cream)
                .tracking(2)
        }
        .padding(.horizontal, 56).padding(.top, 36).padding(.bottom, 8)
    }

    // Status pill showing the last successful snapshot's age + current
    // coverage score. Hidden until the first snapshot lands at ~5 min in;
    // also dims while a tick is in flight so the agent gets a feedback
    // beat instead of a silently-stale label.
    @ViewBuilder
    private var snapshotPill: some View {
        if let when = store.liveLastSnapshotAt {
            HStack(spacing: 6) {
                if store.liveSnapshotInFlight {
                    ProgressView().scaleEffect(0.55).tint(FoyerTheme.gold)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(FoyerTheme.gold)
                }
                Text("Updated \(snapshotAgeLabel(when))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FoyerTheme.creamDim)
                if let cov = store.session?.result?.scriptCoverage,
                   let score = cov.score {
                    Text("·")
                        .foregroundStyle(FoyerTheme.textMuted)
                    Text("Coverage \(score)/100")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(FoyerTheme.gold)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.white.opacity(0.06), in: Capsule())
        } else if store.liveSnapshotInFlight {
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.55).tint(FoyerTheme.gold)
                Text("Analyzing first 5 min…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FoyerTheme.creamDim)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.white.opacity(0.06), in: Capsule())
        }
    }

    private func snapshotAgeLabel(_ when: Date) -> String {
        let delta = max(0, Date().timeIntervalSince(when))
        if delta < 60 { return "just now" }
        let m = Int(delta / 60)
        if m < 60 { return "\(m)m ago" }
        return "\(m / 60)h ago"
    }

    private var voiceVisualizer: some View {
        VStack(spacing: 36) {
            VStack(spacing: 10) {
                Text(store.pendingAddress ?? "Open house")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(FoyerTheme.cream)
                    .tracking(-0.4)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(paused ? "Recording paused" : "Listening")
                    .font(.system(size: 13))
                    .foregroundStyle(FoyerTheme.textDim)
            }
            IPadMicOrb(level: rmsLevel, recording: recorder.isRecording && !paused)
                .frame(height: 240)
            IPadWaveform(levels: recorder.levels)
                .frame(height: 80)
        }
    }

    private var recordingControls: some View {
        HStack(spacing: 14) {
            Button {
                if paused { recorder.resume() } else { recorder.pause() }
                paused.toggle()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text(paused ? "Resume" : "Pause")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(FoyerTheme.cream)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            Button(action: endSession) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white)
                        .frame(width: 12, height: 12)
                    Text("End session")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(FoyerTheme.terracotta, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var rmsLevel: CGFloat {
        let recent = recorder.levels.suffix(8)
        let avg = recent.reduce(0, +) / Float(max(recent.count, 1))
        return CGFloat(min(1, max(0, avg)))
    }

    private var timeString: String {
        let total = Int(recorder.elapsed)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    // MARK: Processing / Ready / Failed

    private var processingPane: some View {
        VStack(spacing: 22) {
            FoyerLoadingView(size: 140, cornerRadius: 18)
            VStack(spacing: 6) {
                Text("Processing the session")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(FoyerTheme.cream)
                Text(processingSubtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(FoyerTheme.textDim)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var processingSubtitle: String {
        switch store.phase {
        case .uploading: return "Uploading audio…"
        case .processing: return "Separating voices and drafting follow-ups…"
        default: return "Working on it…"
        }
    }

    private var readyPane: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(FoyerTheme.sage)
                    .frame(width: 96, height: 96)
                    .shadow(color: FoyerTheme.sage.opacity(0.35), radius: 22, y: 8)
                Image(systemName: "checkmark")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(FoyerTheme.inkOnGold)
            }
            VStack(spacing: 8) {
                Text("Session ready")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(FoyerTheme.cream)
                    .tracking(-0.4)
                Text(readySubtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(FoyerTheme.textDim)
            }
            HStack(spacing: 12) {
                Button { store.reset() } label: {
                    Text("Record another")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FoyerTheme.cream)
                        .padding(.horizontal, 20).padding(.vertical, 13)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    if let id = store.session?.id {
                        onOpenLeads(id)
                        store.reset()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text("Open leads")
                            .font(.system(size: 14, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(FoyerTheme.inkOnGold)
                    .padding(.horizontal, 20).padding(.vertical, 13)
                    .background(FoyerTheme.gold, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var readySubtitle: String {
        let count = store.session?.result?.visitors.count ?? 0
        if count == 0 { return "Drafts are ready." }
        return "\(count) lead\(count == 1 ? "" : "s") drafted."
    }

    private func failedPane(_ msg: String) -> some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(FoyerTheme.terracotta.opacity(0.18)).frame(width: 80, height: 80)
                Image(systemName: "exclamationmark")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(FoyerTheme.terracotta)
            }
            VStack(spacing: 8) {
                Text("Something went wrong")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(FoyerTheme.cream)
                Text(msg)
                    .font(.system(size: 13))
                    .foregroundStyle(FoyerTheme.textDim)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Button { store.reset() } label: {
                Text("Try again")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FoyerTheme.inkOnGold)
                    .padding(.horizontal, 20).padding(.vertical, 13)
                    .background(FoyerTheme.gold, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    @MainActor
    private func beginRecording(with chosen: Listing?) async {
        let granted = await recorder.requestPermission()
        guard granted else { permissionDenied = true; return }
        if let chosen {
            onSelectListing(chosen)
            store.pendingAddress = chosen.address
        } else {
            store.pendingAddress = nil
        }
        // Speakers-expected left on auto — diarization handles open-house
        // crowd sizes well on its own, and asking the agent to count guests
        // up front was friction (the user nuked the picker for that reason).
        store.pendingSpeakersExpected = nil
        do {
            try recorder.startRecording(address: store.pendingAddress ?? "")
            // Kick off the periodic snapshot loop — first tick fires at
            // 5 min, then 10 / 20 / 30 / 50 / 70 / 90 / 120, then every 30
            // min after that. Each tick uploads the audio so far so the
            // agent can peek at lead progress + script coverage without
            // ending the session.
            store.startLiveSnapshotLoop()
        }
        catch { permissionDenied = true }
        paused = false
    }

    private func endSession() {
        // Fires one final full-depth snapshot, stops recording, and lets
        // the snapshotTick flip phase → .ready when the pipeline returns.
        store.endLiveSnapshotLoop()
        paused = false
    }
}

// MARK: – Session detail (playback + metadata)

// Shown when the agent taps a recent session in the side rail or a row on
// Home. Loads the full Session via APIClient.getSession (lazy — summaries
// in the side rail only carry id/address/visitor_count), shows an
// AVPlayer-backed audio scrubber, and lists every lead in the session with
// the same tag-pill + score vocabulary the Leads tab uses. Drilling into
// a lead jumps to Leads filtered by this session so the agent lands on the
// detail view they already know.
private struct IPadSessionDetail: View {
    let sessionId: String
    let store: SessionStore
    var onBack: () -> Void
    var onOpenLeads: (String) -> Void

    @State private var session: Session?
    @State private var loading = true
    @State private var loadError: String?
    @State private var player = AudioPlayer()
    @State private var seeking = false
    @State private var seekTarget: Double = 0
    @State private var showDeleteConfirm = false
    @State private var deleting = false
    @State private var deleteError: String?

    private var audioURL: URL {
        Config.backendURL
            .appendingPathComponent("sessions")
            .appendingPathComponent(sessionId)
            .appendingPathComponent("audio")
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                topBar
                if loading && session == nil {
                    loadingState
                } else if let session {
                    header(session)
                    if let deleteError {
                        errorCard(deleteError)
                    }
                    playbackBar
                    if let result = session.result {
                        if let coverage = result.scriptCoverage {
                            coverageSection(coverage)
                        }
                        leadsList(result.visitors, session: session)
                        if let utts = result.utterances, !utts.isEmpty {
                            speakerTranscript(utts, result: result)
                        } else if !result.fullTranscript.isEmpty {
                            transcriptSection(result.fullTranscript)
                        }
                    } else if session.status == "processing" {
                        processingNote
                    } else if let err = session.error {
                        errorCard(err)
                    }
                } else if let loadError {
                    errorCard(loadError)
                }
                Spacer().frame(height: 60)
            }
            .frame(maxWidth: 880, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 44).padding(.top, 28).padding(.bottom, 120)
        }
        .refreshable { await load() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .task(id: sessionId) { await load() }
        .onDisappear { player.stop() }
        .alert("Delete this session?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete permanently", role: .destructive) {
                Task { await performDelete() }
            }
        } message: {
            Text("This permanently removes the recording, transcript, analysis, and all leads from this session. It can't be undone.")
        }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Button(action: onBack) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(FoyerTheme.creamDim)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.white.opacity(0.06), in: Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
            if let session, session.status == "ready" {
                Button { onOpenLeads(session.id) } label: {
                    HStack(spacing: 6) {
                        Text("Open in Leads")
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(FoyerTheme.inkOnGold)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(FoyerTheme.gold, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            if session != nil {
                Button { showDeleteConfirm = true } label: {
                    HStack(spacing: 6) {
                        if deleting {
                            ProgressView().scaleEffect(0.7).tint(FoyerTheme.terracotta)
                        } else {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        Text("Delete")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(FoyerTheme.terracotta)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(FoyerTheme.terracotta.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(deleting)
            }
        }
    }

    @MainActor
    private func performDelete() async {
        guard let id = session?.id else { return }
        deleting = true
        deleteError = nil
        defer { deleting = false }
        do {
            try await APIClient.shared.deleteSession(id: id)
            await store.refreshSessions()
            onBack()
        } catch {
            deleteError = error.localizedDescription
        }
    }

    private var loadingState: some View {
        HStack {
            Spacer()
            FoyerLoadingView(size: 120, cornerRadius: 16)
            Spacer()
        }
        .padding(.top, 60)
    }

    private func header(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SESSION")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(2.0)
                .foregroundStyle(FoyerTheme.gold)
            Text(session.address ?? "Open house")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(FoyerTheme.cream)
                .tracking(-0.5)
                .lineLimit(2)
            HStack(spacing: 10) {
                Text(relativeTime(session.createdAt))
                    .font(.system(size: 13))
                    .foregroundStyle(FoyerTheme.textDim)
                Text("·")
                    .font(.system(size: 13))
                    .foregroundStyle(FoyerTheme.textMuted)
                statusBadge(session.status)
                if let n = session.result?.visitors.count, n > 0 {
                    Text("·")
                        .font(.system(size: 13))
                        .foregroundStyle(FoyerTheme.textMuted)
                    Text("\(n) lead\(n == 1 ? "" : "s")")
                        .font(.system(size: 13))
                        .foregroundStyle(FoyerTheme.textDim)
                }
            }
        }
    }

    private func statusBadge(_ status: String) -> some View {
        let color: Color = {
            switch status {
            case "ready":      return FoyerTheme.sage
            case "processing": return FoyerTheme.gold
            case "error":      return FoyerTheme.terracotta
            default:           return FoyerTheme.creamDim
            }
        }()
        return Text(status.capitalized)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    private var playbackBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Button { player.playPause() } label: {
                    ZStack {
                        Circle()
                            .fill(FoyerTheme.gold)
                            .frame(width: 52, height: 52)
                            .shadow(color: FoyerTheme.gold.opacity(0.35), radius: 14, y: 6)
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(FoyerTheme.inkOnGold)
                            .offset(x: player.isPlaying ? 0 : 1)
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 4)
                            Capsule()
                                .fill(FoyerTheme.gold)
                                .frame(width: progressWidth(geo.size.width), height: 4)
                            Circle()
                                .fill(FoyerTheme.cream)
                                .frame(width: 12, height: 12)
                                .offset(x: max(0, progressWidth(geo.size.width) - 6))
                        }
                        .contentShape(Rectangle())
                        .gesture(scrubGesture(width: geo.size.width))
                    }
                    .frame(height: 14)

                    HStack {
                        Text(formatTime(player.currentTime))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(FoyerTheme.textDim)
                        Spacer()
                        Text(formatTime(displayDuration))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(FoyerTheme.textDim)
                    }
                }
            }
        }
        .padding(20)
        .background(Color(white: 0.05), in: RoundedRectangle(cornerRadius: 16))
        .onAppear {
            if player.loadedURL != audioURL { player.load(url: audioURL) }
        }
    }

    private var displayDuration: TimeInterval {
        seeking ? max(seekTarget, 0) : player.duration
    }

    private func progressWidth(_ total: CGFloat) -> CGFloat {
        let duration = player.duration
        guard duration > 0 else { return 0 }
        let value = seeking ? seekTarget : player.currentTime
        let frac = max(0, min(1, value / duration))
        return total * frac
    }

    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                seeking = true
                let frac = max(0, min(1, v.location.x / width))
                seekTarget = frac * player.duration
            }
            .onEnded { _ in
                player.seek(to: seekTarget)
                seeking = false
            }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let total = Int(t)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    private func leadsList(_ visitors: [VisitorResult], session: Session) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Leads in this session")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(FoyerTheme.textDim)

            VStack(spacing: 10) {
                ForEach(visitors) { v in
                    Button { onOpenLeads(session.id) } label: {
                        leadRow(v)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func leadRow(_ v: VisitorResult) -> some View {
        HStack(spacing: 14) {
            Text(v.displayInitials)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(FoyerTheme.gold)
                .frame(width: 42, height: 42)
                .background(FoyerTheme.bgElev, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(v.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FoyerTheme.cream)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Circle().fill(tagColor(v.analysis.tagToken)).frame(width: 5, height: 5)
                    Text(v.analysis.tag)
                        .font(.system(size: 12))
                        .foregroundStyle(FoyerTheme.textDim)
                    if !v.visitor.email.isEmpty {
                        Text("·")
                            .font(.system(size: 12))
                            .foregroundStyle(FoyerTheme.textMuted)
                        Text(v.visitor.email)
                            .font(.system(size: 12))
                            .foregroundStyle(FoyerTheme.textMuted)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
            Text("\(v.analysis.score)")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(v.analysis.score >= 80 ? FoyerTheme.gold : FoyerTheme.creamDim)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FoyerTheme.textMuted)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color(white: 0.05), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
    }

    private func tagColor(_ token: String) -> Color {
        switch token {
        case "buyer":   return FoyerTheme.gold
        case "seller":  return FoyerTheme.terracotta
        case "browser": return FoyerTheme.sage
        default:        return FoyerTheme.creamDim
        }
    }

    private func transcriptSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Transcript")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(FoyerTheme.textDim)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(FoyerTheme.creamDim)
                .lineSpacing(5)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(white: 0.04), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // Speaker-labeled transcript. The backend already produces per-turn
    // utterances with a speaker label (e.g. "A", "B"); each visitor has a
    // Script coverage panel — score, scriptName, and per-step rows with
    // tap-to-expand "you said" + "suggestion". Mirrors the iPhone summary.
    @ViewBuilder
    private func coverageSection(_ coverage: ScriptCoverage) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Script coverage")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(FoyerTheme.textDim)
                Spacer()
                if let score = coverage.score {
                    Text("\(score)")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(coverageScoreColor(score))
                    Text("/100")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(FoyerTheme.textMuted)
                }
            }
            if let err = coverage.error {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(FoyerTheme.terracotta)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(FoyerTheme.terracotta.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            } else {
                Text(coverage.scriptName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FoyerTheme.cream)
                if let s = coverage.overallSummary, !s.isEmpty {
                    Text(s)
                        .font(.system(size: 13))
                        .foregroundStyle(FoyerTheme.creamDim)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let steps = coverage.steps {
                    VStack(spacing: 8) {
                        ForEach(steps) { step in
                            IPadCoverageRow(step: step)
                        }
                    }
                }
            }
        }
    }

    private func coverageScoreColor(_ score: Int) -> Color {
        switch score {
        case 75...:    return FoyerTheme.sage
        case 40..<75:  return FoyerTheme.gold
        default:       return FoyerTheme.terracotta
        }
    }

    // matched `speaker` field, and the agent's label is in
    // result.agentSpeaker. We resolve each utterance's speaker to a name
    // and color so the agent can scan who said what.
    private func speakerTranscript(_ utterances: [Utterance], result: SessionResult) -> some View {
        let nameByLabel = speakerNameMap(result: result)
        let agentLabel = result.agentSpeaker
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Transcript")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(FoyerTheme.textDim)
                Spacer()
                Text("\(utterances.count) turns · speaker-labeled")
                    .font(.system(size: 11))
                    .foregroundStyle(FoyerTheme.textMuted)
            }
            VStack(spacing: 1) {
                ForEach(utterances) { utt in
                    transcriptTurn(
                        utt,
                        displayName: nameByLabel[utt.speaker] ?? "Speaker \(utt.speaker)",
                        isAgent: utt.speaker == agentLabel,
                        color: speakerColor(utt.speaker, agentLabel: agentLabel, result: result)
                    )
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(white: 0.04), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func transcriptTurn(_ utt: Utterance, displayName: String, isAgent: Bool, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                    .lineLimit(1)
                if isAgent {
                    Text("agent")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(FoyerTheme.textMuted)
                        .padding(.top, 1)
                }
                Text(formatTimestamp(utt.startMs))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(FoyerTheme.textMuted)
                    .padding(.top, 2)
            }
            .frame(width: 90, alignment: .leading)

            Text(utt.text)
                .font(.system(size: 14))
                .foregroundStyle(FoyerTheme.cream)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background(alignment: .bottom) {
            Rectangle().fill(FoyerTheme.hairline).frame(height: 0.5)
        }
    }

    // Map backend speaker labels ("A", "B", "C", …) to display names. The
    // agent gets "You"; visitors get their captured first name; speakers
    // we never matched stay as "Speaker X".
    private func speakerNameMap(result: SessionResult) -> [String: String] {
        var map: [String: String] = [:]
        if !result.agentSpeaker.isEmpty {
            map[result.agentSpeaker] = "You"
        }
        for v in result.visitors {
            if let label = v.visitor.speaker, !label.isEmpty {
                let first = v.visitor.name
                    .split(separator: " ")
                    .first
                    .map(String.init) ?? v.visitor.name
                map[label] = first
            }
        }
        return map
    }

    private func speakerColor(_ label: String, agentLabel: String, result: SessionResult) -> Color {
        if label == agentLabel { return FoyerTheme.gold }
        // Cycle through a small palette so different guests are visually
        // distinguishable even when speaker-name matching failed.
        let palette: [Color] = [
            FoyerTheme.terracotta,
            FoyerTheme.sage,
            Color(red: 0.55, green: 0.65, blue: 0.95),
            Color(red: 0.85, green: 0.55, blue: 0.75),
            Color(red: 0.70, green: 0.80, blue: 0.55),
        ]
        // Stable index by alphabetical position of the label among non-agent
        // labels that appear in this session.
        let nonAgent = Set(result.visitors.compactMap(\.visitor.speaker))
            .filter { $0 != agentLabel }
            .sorted()
        let idx = nonAgent.firstIndex(of: label) ?? label.hashValue
        return palette[(idx % palette.count + palette.count) % palette.count]
    }

    private func formatTimestamp(_ ms: Int) -> String {
        let total = ms / 1000
        let m = total / 60, s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private var processingNote: some View {
        HStack(spacing: 12) {
            ProgressView().tint(FoyerTheme.gold).scaleEffect(0.85)
            VStack(alignment: .leading, spacing: 2) {
                Text("Still processing")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FoyerTheme.cream)
                Text("Voices are being separated. Check back in a minute.")
                    .font(.system(size: 12))
                    .foregroundStyle(FoyerTheme.textDim)
            }
            Spacer()
        }
        .padding(16)
        .background(Color(white: 0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    private func errorCard(_ msg: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(FoyerTheme.terracotta)
                Text("Something went wrong")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FoyerTheme.cream)
            }
            Text(msg)
                .font(.system(size: 12))
                .foregroundStyle(FoyerTheme.textDim)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FoyerTheme.terracotta.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
    }

    private func relativeTime(_ iso: String?) -> String {
        guard let iso, let date = ISO8601DateFormatter.fractionalSeconds.date(from: iso)
            ?? ISO8601DateFormatter().date(from: iso)
        else { return "—" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    private func load() async {
        loading = true
        loadError = nil
        defer { loading = false }
        do {
            let s = try await APIClient.shared.getSession(id: sessionId)
            await MainActor.run { self.session = s }
        } catch {
            await MainActor.run { self.loadError = error.localizedDescription }
        }
    }
}

// MARK: – Coverage row (iPad)

private struct IPadCoverageRow: View {
    let step: StepCoverage
    @State private var expanded = false

    var body: some View {
        Button { withAnimation { expanded.toggle() } } label: {
            VStack(alignment: .leading, spacing: expanded ? 10 : 0) {
                HStack(spacing: 10) {
                    statusPill
                    Text(stepLabel)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(FoyerTheme.cream)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(FoyerTheme.textMuted)
                }
                if expanded {
                    if !step.evidence.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("YOU SAID")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .tracking(1.4)
                                .foregroundStyle(FoyerTheme.textMuted)
                            Text("\"\(step.evidence)\"")
                                .font(.system(size: 13))
                                .foregroundStyle(FoyerTheme.cream)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !step.suggestion.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("SUGGESTION")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .tracking(1.4)
                                .foregroundStyle(FoyerTheme.gold)
                            Text(step.suggestion)
                                .font(.system(size: 13))
                                .foregroundStyle(FoyerTheme.creamDim)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(white: 0.05), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var statusPill: some View {
        let (text, color): (String, Color) = {
            switch step.status {
            case "hit":     return ("HIT",     FoyerTheme.sage)
            case "partial": return ("PARTIAL", FoyerTheme.gold)
            case "missed":  return ("MISSED",  FoyerTheme.terracotta)
            default:        return (step.status.uppercased(), FoyerTheme.creamDim)
            }
        }()
        return Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    private var stepLabel: String {
        ScriptStepLookup.label(for: step.stepId)
    }
}

// MARK: – iPad mic orb + waveform

// Larger version of the iPhone LiveView's MicOrb. Same vocabulary —
// ambient halo, three concentric PulseRings, a level-driven outer ring,
// and the brass mic disc — scaled up for the iPad canvas.
private struct IPadMicOrb: View {
    var level: CGFloat
    var recording: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [FoyerTheme.terracotta.opacity(0.32), .clear],
                        center: .center, startRadius: 12, endRadius: 160
                    )
                )
                .scaleEffect(1 + level * 0.20)
                .animation(.easeOut(duration: 0.15), value: level)

            PulseRing(color: FoyerTheme.terracotta, delay: 0.0)
                .frame(width: 180, height: 180)
                .opacity(recording ? 0.85 : 0.25)
            PulseRing(color: FoyerTheme.terracotta, delay: 0.7)
                .frame(width: 180, height: 180)
                .opacity(recording ? 0.55 : 0.18)
            PulseRing(color: FoyerTheme.gold, delay: 1.4)
                .frame(width: 180, height: 180)
                .opacity(recording ? 0.45 : 0.12)

            Circle()
                .stroke(FoyerTheme.terracotta.opacity(0.8), lineWidth: 1.5)
                .frame(width: 150 + level * 90, height: 150 + level * 90)
                .opacity(level * 0.9 + 0.15)
                .animation(.easeOut(duration: 0.18), value: level)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [FoyerTheme.goldBright, FoyerTheme.goldDeep],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 116, height: 116)
                .shadow(color: FoyerTheme.gold.opacity(0.6), radius: 30, x: 0, y: 10)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                        .blendMode(.overlay)
                )

            Image(systemName: "mic.fill")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(FoyerTheme.inkOnGold)
        }
    }
}

// Symmetric live waveform — newest samples on the right glow terracotta,
// older samples fade through brass. Tween between frames so the motion
// reads as continuous, not stepped.
private struct IPadWaveform: View {
    var levels: [Float]

    @State private var animated: [CGFloat] = []

    var body: some View {
        GeometryReader { geo in
            let count = max(levels.count, 1)
            let barCount = min(count, 72)
            let spacing: CGFloat = 3
            let totalSpacing = spacing * CGFloat(barCount - 1)
            let width = max(2.5, (geo.size.width - totalSpacing) / CGFloat(barCount))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    let value = level(at: i, barCount: barCount)
                    let isNow = i >= barCount - 8
                    Capsule()
                        .fill(isNow ? FoyerTheme.terracotta : FoyerTheme.gold)
                        .opacity(isNow ? min(1, 0.55 + Double(value) * 0.6)
                                       : 0.35 + Double(value) * 0.5)
                        .frame(
                            width: width,
                            height: max(3, value * (geo.size.height - 6))
                        )
                        .shadow(color: isNow ? FoyerTheme.terracotta.opacity(0.55) : .clear,
                                radius: isNow ? 6 : 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { syncAnimated() }
        .onChange(of: levels) { _, _ in
            withAnimation(.easeOut(duration: 0.18)) {
                syncAnimated()
            }
        }
    }

    private func level(at index: Int, barCount: Int) -> CGFloat {
        let count = animated.count
        guard count > 0 else { return 0 }
        let offset = max(0, count - barCount)
        let idx = min(count - 1, offset + index)
        return animated[idx]
    }

    private func syncAnimated() {
        let mapped = levels.map { CGFloat($0) }
        if animated.count != mapped.count {
            animated = mapped
        } else {
            animated = zip(animated, mapped).map { current, target in
                current + (target - current) * 0.85
            }
        }
    }
}

// MARK: – @-mention autocomplete picker
//
// Reusable picker that surfaces below an input field when the user types
// `@`. It pulls offers + templates from the backend, filters them by
// the partial text after `@`, and on tap replaces the partial token
// with the full name. Behaves like Cursor's @file picker.
//
// Why not just match against a fixed regex? Offer / template names are
// free-form (spaces, punctuation), so the regex would have to know all
// names ahead of time. Easier to keep the list in-memory on iOS and let
// the picker handle disambiguation visually — the agent never has to
// type a full name, just tap the suggestion.

struct MentionItem: Identifiable, Hashable {
    let id: String
    let kind: Kind
    let name: String
    let preview: String   // short snippet shown in the picker row

    enum Kind: Hashable { case offer, template }

    static func from(_ offer: Offer) -> MentionItem {
        MentionItem(
            id: "offer:\(offer.id)",
            kind: .offer,
            name: offer.name,
            preview: offer.body
        )
    }

    static func from(_ template: FollowupTemplate) -> MentionItem {
        MentionItem(
            id: "template:\(template.id)",
            kind: .template,
            name: template.name,
            preview: template.body
        )
    }
}

// Shared, app-lifetime cache of the agent's mention library. Refreshed
// lazily AND on demand (when the agent edits offers/templates and we
// want the picker to immediately see the change).
@MainActor
@Observable
final class MentionLibrary {
    static let shared = MentionLibrary()
    private init() {}

    var offers: [Offer] = []
    var templates: [FollowupTemplate] = []
    var loaded: Bool = false      // true once the first load completed
    var loadError: String?        // surfaced in the empty picker state

    var items: [MentionItem] {
        offers.filter(\.enabled).map(MentionItem.from)
            + templates.filter(\.enabled).map(MentionItem.from)
    }

    /// Trigger a fresh fetch and return when it's done. Idempotent —
    /// callers can hit this on every appearance of an input field
    /// without burning round trips because we coalesce in-flight loads.
    private var inFlight: Task<Void, Never>?

    func refresh() async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { @MainActor in
            do {
                async let oReq = APIClient.shared.listOffers()
                async let tReq = APIClient.shared.listTemplates()
                let newOffers = try await oReq
                let envelope = try await tReq
                self.offers = newOffers
                self.templates = envelope.templates
                self.loadError = nil
            } catch {
                self.loadError = error.localizedDescription
            }
            self.loaded = true
        }
        inFlight = task
        await task.value
        inFlight = nil
    }

    /// Optimistic local-update hooks the edit screens can call so the
    /// picker doesn't lag a round trip behind the latest change.
    func upsert(offer: Offer) {
        if let idx = offers.firstIndex(where: { $0.id == offer.id }) {
            offers[idx] = offer
        } else {
            offers.append(offer)
        }
    }
    func remove(offerId: String) { offers.removeAll { $0.id == offerId } }

    func upsert(template: FollowupTemplate) {
        if let idx = templates.firstIndex(where: { $0.id == template.id }) {
            templates[idx] = template
        } else {
            templates.append(template)
        }
    }
    func remove(templateId: String) { templates.removeAll { $0.id == templateId } }
}

// Parses the "active @-token" from a buffer of text. Returns (start,
// query) where `start` is the index of the `@` and `query` is the text
// between `@` and the end of the buffer. Returns nil if no unclosed
// token is currently in progress (i.e. text doesn't end in an `@`-
// initiated word).
//
// Rules:
//   - The `@` must be at the start of the buffer OR preceded by
//     whitespace, so an email address (`a@b.com`) doesn't trigger.
//   - Everything from `@` to the END of the buffer counts as the query.
//     This is what makes free-form names work — typing "@buyer credit"
//     keeps the picker open through the space.
struct ActiveMention {
    let start: String.Index
    let query: String
}

func activeMention(in text: String) -> ActiveMention? {
    guard let atIdx = text.lastIndex(of: "@") else { return nil }
    // Boundary: `@` must follow whitespace or be at start (so a@b.com doesn't
    // open the picker mid-email-address).
    if atIdx != text.startIndex {
        let before = text[text.index(before: atIdx)]
        if !before.isWhitespace && before != "\n" {
            return nil
        }
    }
    let query = String(text[text.index(after: atIdx)...])
    // Token closes as soon as ANY whitespace appears after `@`. This is
    // what makes the picker behave like Cursor: tap a suggestion (the
    // inserter appends a trailing space) and the picker disappears, so
    // further typing isn't re-interpreted as a new query. If the agent
    // wants a multi-word name they pick it from the list — typing it
    // freehand isn't supported on purpose.
    if query.contains(where: { $0.isWhitespace || $0 == "\n" }) {
        return nil
    }
    return ActiveMention(start: atIdx, query: query)
}

// View shown directly below an input field; given the current text and
// a write-back binding, it filters MentionLibrary against the active
// @-token and renders tap-to-insert rows. Visible whenever the user is
// in the middle of typing an @-token — even if no items match yet, we
// show an explanation row so the agent isn't left wondering why nothing
// appeared.
struct MentionSuggestionsView: View {
    @Binding var text: String
    var onInsert: (() -> Void)? = nil
    @State private var library = MentionLibrary.shared

    var body: some View {
        Group {
            if let mention = activeMention(in: text) {
                let matches = filtered(mention.query)
                VStack(alignment: .leading, spacing: 0) {
                    if matches.isEmpty {
                        emptyRow
                    } else {
                        ForEach(matches.prefix(6)) { item in
                            Button {
                                insert(item, replacing: mention)
                            } label: {
                                row(item)
                            }
                            .buttonStyle(.plain)
                            if item.id != matches.prefix(6).last?.id {
                                Rectangle().fill(FoyerTheme.hairline).frame(height: 1)
                            }
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(white: 0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(FoyerTheme.hairline, lineWidth: 1)
                )
                .padding(.top, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        // Refresh on every appearance — cheap (~2 quick GETs) and means
        // an offer added in the Offers tab is visible in the picker
        // immediately when the user comes back to Refine.
        .task { await library.refresh() }
    }

    @ViewBuilder
    private var emptyRow: some View {
        let q = activeMention(in: text)?.query
                  .trimmingCharacters(in: .whitespaces) ?? ""
        let message: String = {
            if !library.loaded { return "Loading…" }
            if library.loadError != nil { return "Couldn't load offers" }
            if library.items.isEmpty { return "No offers or templates yet" }
            return "No matches for @\(q)"
        }()
        HStack(spacing: 12) {
            Image(systemName: !library.loaded ? "hourglass" : "tag")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(FoyerTheme.creamDim)
                .frame(width: 18)
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(FoyerTheme.creamDim)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func filtered(_ q: String) -> [MentionItem] {
        let qLower = q.trimmingCharacters(in: .whitespaces).lowercased()
        let all = library.items
        if qLower.isEmpty { return all }
        return all.filter { $0.name.lowercased().contains(qLower) }
    }

    private func row(_ item: MentionItem) -> some View {
        // Cursor-style row: icon + name, nothing else. Offer icon is
        // gold to mirror the brand accent; templates get a subtler glyph
        // so the two are distinguishable without a textual label.
        HStack(spacing: 12) {
            Image(systemName: item.kind == .offer ? "tag.fill" : "doc.text")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(item.kind == .offer
                                 ? FoyerTheme.gold
                                 : FoyerTheme.creamDim)
                .frame(width: 18)
            Text(item.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(FoyerTheme.cream)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func insert(_ item: MentionItem, replacing mention: ActiveMention) {
        // Replace from the `@` to the end of the buffer with the full
        // canonical name plus a trailing space so the agent can keep
        // typing right after.
        var rewritten = String(text[..<mention.start])
        rewritten += "@\(item.name) "
        text = rewritten
        onInsert?()
    }
}

#Preview { IPadAgentApp() }
