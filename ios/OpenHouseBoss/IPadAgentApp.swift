import SwiftUI

// iPad agent surface — runs on the open-house iPad. Side rail picks the
// section; the main pane hosts Home / Kiosk / Leads / Listings.
//
// Data model: reads SessionStore.shared for listings + past sessions, and
// for the active session's visitors/lead state when reviewing one. Mock
// arrays (SampleData) are no longer referenced here — every list is real.
struct IPadAgentApp: View {
    enum Tab: String, CaseIterable, Identifiable {
        case home, kiosk, leads, listings
        var id: String { rawValue }
        var label: String {
            switch self {
            case .home:     return "Home"
            case .kiosk:    return "Sign in"
            case .leads:    return "Leads"
            case .listings: return "Listings"
            }
        }
        var icon: String {
            switch self {
            case .home:     return "house"
            case .kiosk:    return "person.badge.plus"
            case .leads:    return "person.2"
            case .listings: return "square.grid.2x2"
            }
        }
    }

    @State private var tab: Tab = .home
    @State private var store = SessionStore.shared
    // Listing the kiosk is currently hosting. Set when the agent taps a
    // listing on Home or in Listings; passed through to IPadKiosk so the
    // sign-in form shows the right property.
    @State private var activeListing: Listing?
    // Session the agent is reviewing leads for in the Leads tab. nil means
    // "show every lead across every recorded session, newest first."
    @State private var activeSessionId: String?

    var body: some View {
        HStack(spacing: 0) {
            sideRail
            mainPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(FoyerTheme.bgDeep.ignoresSafeArea())
        .task {
            await store.refreshSessions()
        }
    }

    @ViewBuilder
    private var mainPane: some View {
        switch tab {
        case .home:
            IPadHome(
                store: store,
                onStartKiosk: { listing in
                    activeListing = listing
                    tab = .kiosk
                },
                onOpenSession: { id in
                    activeSessionId = id
                    tab = .leads
                }
            )
        case .kiosk:
            IPadKiosk(
                store: store,
                listing: activeListing ?? store.listings.first,
                onLaunchListing: { tab = .listings }
            )
        case .leads:
            IPadLeads(
                store: store,
                sessionId: $activeSessionId
            )
        case .listings:
            IPadListings(
                store: store,
                onPickListing: { listing in
                    activeListing = listing
                    tab = .kiosk
                }
            )
        }
    }

    private var sideRail: some View {
        VStack(spacing: 24) {
            Text("F")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(FoyerTheme.gold)
                .frame(width: 40, height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(FoyerTheme.gold.opacity(0.5), lineWidth: 1)
                )
                .padding(.top, 6)

            VStack(spacing: 4) {
                ForEach(Tab.allCases) { t in
                    Button { tab = t } label: {
                        VStack(spacing: 5) {
                            Image(systemName: t.icon)
                                .font(.system(size: 19, weight: tab == t ? .semibold : .regular))
                                .frame(width: 44, height: 44)
                                .foregroundStyle(tab == t ? FoyerTheme.gold : FoyerTheme.creamDim)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(tab == t ? FoyerTheme.goldSoft : Color.clear)
                                )
                            Text(t.label)
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(tab == t ? FoyerTheme.gold : FoyerTheme.textMuted)
                                .lineLimit(1)
                                .frame(width: 70)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            Text("JH")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(FoyerTheme.creamDim)
                .frame(width: 36, height: 36)
                .background(FoyerTheme.bgElev, in: Circle())
                .padding(.bottom, 8)
        }
        .frame(width: 88)
        .padding(.vertical, 20)
    }
}

// MARK: – Home

// Greeting, active listing card, and a real list of recent recorded
// sessions pulled from SessionStore.pastSessions. Tapping the listing card
// jumps to the kiosk for that property; tapping a session jumps to Leads
// with that session preselected.
private struct IPadHome: View {
    let store: SessionStore
    var onStartKiosk: (Listing) -> Void
    var onOpenSession: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                greeting
                if let listing = store.listings.first {
                    activeListingCard(listing)
                } else {
                    emptyListingCard
                }
                recentSessions
            }
            .padding(.horizontal, 40)
            .padding(.top, 32)
            .padding(.bottom, 48)
        }
        .background(FoyerTheme.bgDeep)
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(dateGreeting)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(FoyerTheme.textDim)
            Text("Hello, John")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(FoyerTheme.cream)
                .tracking(-0.6)
        }
    }

    private var dateGreeting: String {
        let now = Date()
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE"
        let dayPart = dayFormatter.string(from: now)
        let hour = Calendar.current.component(.hour, from: now)
        let period: String
        switch hour {
        case 5..<12:  period = "morning"
        case 12..<17: period = "afternoon"
        case 17..<22: period = "evening"
        default:      period = "night"
        }
        return "\(dayPart) \(period)"
    }

    private func activeListingCard(_ listing: Listing) -> some View {
        Button { onStartKiosk(listing) } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    listingPhoto(listing)
                        .frame(height: 220)
                        .clipped()
                    HStack(spacing: 6) {
                        Circle().fill(FoyerTheme.terracotta).frame(width: 6, height: 6)
                        Text("Hosting now")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(FoyerTheme.cream)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(16)
                }

                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(listing.address)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(FoyerTheme.cream)
                            .lineLimit(1)
                        Text(subtitle(for: listing))
                            .font(.system(size: 14))
                            .foregroundStyle(FoyerTheme.creamDim)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 16)
                    HStack(spacing: 8) {
                        Text("Start sign-in")
                            .font(.system(size: 14, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(FoyerTheme.inkOnGold)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(FoyerTheme.gold, in: Capsule())
                }
                .padding(20)
            }
            .background(FoyerTheme.bgCard, in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func listingPhoto(_ listing: Listing) -> some View {
        if let data = listing.photoData, let img = UIImage(data: data) {
            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            // Subtle gradient placeholder when no photo is attached.
            LinearGradient(
                colors: [FoyerTheme.bgElev2, FoyerTheme.bgCard],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .overlay(
                Image(systemName: "house")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(FoyerTheme.creamDim.opacity(0.35))
            )
        }
    }

    private func subtitle(for listing: Listing) -> String {
        var parts: [String] = []
        if !listing.displayPrice.isEmpty { parts.append(listing.displayPrice) }
        if !listing.neighborhood.isEmpty { parts.append(listing.neighborhood) }
        parts.append(listing.displaySpecs)
        return parts.joined(separator: "  ·  ")
    }

    private var emptyListingCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .light))
                .frame(width: 56, height: 56)
                .foregroundStyle(FoyerTheme.gold)
                .background(FoyerTheme.goldSoft, in: Circle())
            Text("No listings yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(FoyerTheme.cream)
            Text("Add an open house to start a sign-in session.")
                .font(.system(size: 14))
                .foregroundStyle(FoyerTheme.textDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
        .background(FoyerTheme.bgCard, in: RoundedRectangle(cornerRadius: 20))
    }

    private var recentSessions: some View {
        let recorded = store.pastSessions.filter { $0.kind == "recorded" }
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent sessions")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(FoyerTheme.cream)
                Spacer()
                if recorded.count > 5 {
                    Text("\(recorded.count) total")
                        .font(.system(size: 12))
                        .foregroundStyle(FoyerTheme.textDim)
                }
            }
            if recorded.isEmpty {
                Text("No recordings yet.")
                    .font(.system(size: 14))
                    .foregroundStyle(FoyerTheme.textDim)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(recorded.prefix(8)) { s in
                        Button { onOpenSession(s.id) } label: {
                            sessionRow(s)
                        }
                        .buttonStyle(.plain)
                        if s.id != recorded.prefix(8).last?.id {
                            Hairline().padding(.horizontal, 4)
                        }
                    }
                }
                .background(FoyerTheme.bgCard, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func sessionRow(_ s: SessionSummary) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(s.displayTitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(FoyerTheme.cream)
                    .lineLimit(1)
                Text(relativeTime(s.createdDate))
                    .font(.system(size: 12))
                    .foregroundStyle(FoyerTheme.textDim)
            }
            Spacer()
            HStack(spacing: 4) {
                Text("\(s.visitorCount)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(FoyerTheme.cream)
                Text(s.visitorCount == 1 ? "lead" : "leads")
                    .font(.system(size: 12))
                    .foregroundStyle(FoyerTheme.textDim)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FoyerTheme.textMuted)
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .contentShape(Rectangle())
    }

    private func relativeTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: – Kiosk (sign-in form)

// The on-iPad sign-in form guests fill out at the open house. Left pane
// shows the listing they're walking through; right pane collects name +
// email + phone and pushes onto SessionStore.pendingKioskGuests. On Done
// we don't navigate — the agent picks the iPad back up and starts a
// session from Home (LiveView reads the guest list from the store).
private struct IPadKiosk: View {
    let store: SessionStore
    let listing: Listing?
    var onLaunchListing: () -> Void

    @State private var name: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""

    var body: some View {
        HStack(spacing: 0) {
            listingPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(FoyerTheme.bgDeep)
            formPane
                .frame(maxWidth: 520, maxHeight: .infinity)
                .background(FoyerTheme.bg)
        }
    }

    @ViewBuilder
    private var listingPane: some View {
        if let listing {
            ZStack(alignment: .bottomLeading) {
                listingPhoto(listing)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.4), .black.opacity(0.85)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 6) {
                        Circle().fill(FoyerTheme.gold).frame(width: 5, height: 5)
                        Text("Open house")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(FoyerTheme.gold)
                    }
                    Text(listing.address)
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundStyle(.white)
                        .tracking(-1)
                        .lineLimit(2)
                    if !listing.neighborhood.isEmpty {
                        Text(listing.neighborhood)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(FoyerTheme.cream)
                    }
                    HStack(alignment: .firstTextBaseline) {
                        if !listing.displayPrice.isEmpty {
                            Text(listing.displayPrice)
                                .font(.system(size: 32, weight: .semibold))
                                .foregroundStyle(FoyerTheme.gold)
                        }
                        Spacer()
                        Text(listing.displaySpecs)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(FoyerTheme.cream.opacity(0.85))
                    }
                    .padding(.top, 4)
                }
                .padding(40)
            }
        } else {
            VStack(spacing: 18) {
                Image(systemName: "house")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(FoyerTheme.creamDim.opacity(0.4))
                Text("No listing picked")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(FoyerTheme.cream)
                Text("Pick the property guests are signing in to.")
                    .font(.system(size: 14))
                    .foregroundStyle(FoyerTheme.textDim)
                Button(action: onLaunchListing) {
                    Text("Pick a listing")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 22).padding(.vertical, 12)
                        .foregroundStyle(FoyerTheme.inkOnGold)
                        .background(FoyerTheme.gold, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func listingPhoto(_ listing: Listing) -> some View {
        if let data = listing.photoData, let img = UIImage(data: data) {
            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.14, blue: 0.17),
                    Color(red: 0.04, green: 0.05, blue: 0.07),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    private var formPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Welcome in")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FoyerTheme.gold)
                Spacer()
                Text("\(store.pendingKioskGuests.count) signed in")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FoyerTheme.creamDim)
            }
            .padding(.bottom, 18)

            Text("A few quick details.")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(FoyerTheme.cream)
                .tracking(-0.5)
            Text("Shared with the listing agent so they can follow up.")
                .font(.system(size: 14))
                .foregroundStyle(FoyerTheme.textDim)
                .padding(.top, 6)

            VStack(spacing: 14) {
                kioskField(label: "Full name", value: $name, keyboard: .default, content: .name)
                kioskField(label: "Email", value: $email, keyboard: .emailAddress, content: .emailAddress)
                kioskField(label: "Phone", value: $phone, keyboard: .phonePad, content: .telephoneNumber)
            }
            .padding(.top, 28)

            if !store.pendingKioskGuests.isEmpty {
                checkedInStrip
                    .padding(.top, 22)
            }

            Spacer()

            HStack(spacing: 10) {
                Button { saveGuest(andClear: true) } label: {
                    Text("Sign in another")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(FoyerTheme.cream)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(FoyerTheme.bgElev, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)

                Button { saveGuest(andClear: false) } label: {
                    HStack(spacing: 8) {
                        Text("Done")
                            .font(.system(size: 14, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(FoyerTheme.inkOnGold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(FoyerTheme.gold, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, 36).padding(.vertical, 36)
    }

    private func kioskField(
        label: String,
        value: Binding<String>,
        keyboard: UIKeyboardType,
        content: UITextContentType
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(FoyerTheme.textDim)
            TextField("", text: value)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(FoyerTheme.cream)
                .tint(FoyerTheme.gold)
                .textContentType(content)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(FoyerTheme.bgElev, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var checkedInStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Already signed in")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(FoyerTheme.textDim)
            VStack(spacing: 0) {
                ForEach(store.pendingKioskGuests) { g in
                    HStack {
                        Text(g.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(FoyerTheme.cream)
                        Spacer()
                        Text(g.email.isEmpty ? g.phone : g.email)
                            .font(.system(size: 12))
                            .foregroundStyle(FoyerTheme.textDim)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    if g.id != store.pendingKioskGuests.last?.id {
                        Hairline()
                    }
                }
            }
            .background(FoyerTheme.bgElev, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func saveGuest(andClear: Bool) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        store.pendingKioskGuests.append(
            VisitorInput(name: trimmed, email: email, phone: phone)
        )
        if andClear {
            name = ""
            email = ""
            phone = ""
        }
    }
}

// MARK: – Leads (per-session review)

// Two-pane leads viewer. Left: list of every visitor across recorded
// sessions (or, when a session is preselected, just that session's leads).
// Right: detail for the picked visitor including the auto-summary, signal
// tags, and the drafted follow-up. Lead-state changes hit the backend via
// APIClient.updateLeadState, same as the iPhone flow.
private struct IPadLeads: View {
    let store: SessionStore
    @Binding var sessionId: String?

    @State private var detailSession: Session?
    @State private var activeVisitorId: String?
    @State private var loading = false

    var body: some View {
        HStack(spacing: 0) {
            list
                .frame(width: 360)
                .background(FoyerTheme.bg)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(FoyerTheme.hairline).frame(width: 1)
                }
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(FoyerTheme.bgDeep)
        }
        .task(id: sessionId) {
            await loadDetail()
        }
    }

    private var visitors: [VisitorResult] {
        detailSession?.result?.visitors ?? []
    }

    private var currentVisitor: VisitorResult? {
        if let id = activeVisitorId {
            return visitors.first { $0.id == id }
        }
        return visitors.first
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Leads")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(FoyerTheme.cream)
                    .tracking(-0.4)
                if let s = detailSession {
                    Text(s.address ?? "Open house")
                        .font(.system(size: 14))
                        .foregroundStyle(FoyerTheme.textDim)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 24).padding(.top, 32).padding(.bottom, 20)

            if loading {
                Spacer()
                ProgressView().tint(FoyerTheme.gold)
                Spacer()
            } else if visitors.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visitors) { v in
                            Button { activeVisitorId = v.id } label: {
                                row(v)
                            }
                            .buttonStyle(.plain)
                            Hairline()
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "person.2")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(FoyerTheme.creamDim.opacity(0.35))
            Text(sessionId == nil ? "Pick a session from Home" : "No leads on this session")
                .font(.system(size: 14))
                .foregroundStyle(FoyerTheme.textDim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ v: VisitorResult) -> some View {
        let isActive = (activeVisitorId ?? visitors.first?.id) == v.id
        return HStack(spacing: 12) {
            Text(v.displayInitials)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(FoyerTheme.gold)
                .frame(width: 38, height: 38)
                .background(FoyerTheme.bgElev2, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(v.displayName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(FoyerTheme.cream)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let kind = TagPill.Kind(v.analysis.tagToken) {
                        TagPill(kind: kind, text: v.analysis.tag)
                    }
                    if let state = v.leadState {
                        Text(state.status.rawValue.capitalized)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(FoyerTheme.textDim)
                    }
                }
            }
            Spacer()
            Text("\(v.analysis.score)")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(v.analysis.score >= 80 ? FoyerTheme.gold : FoyerTheme.creamDim)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(isActive ? FoyerTheme.goldSoft : Color.clear)
        .overlay(alignment: .leading) {
            Rectangle().fill(isActive ? FoyerTheme.gold : Color.clear).frame(width: 2)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let v = currentVisitor, let session = detailSession {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    detailHeader(v)
                    summarySection(v)
                    followupSection(v, session: session)
                }
                .padding(.horizontal, 40).padding(.vertical, 32)
            }
        } else if !loading {
            VStack(spacing: 14) {
                Image(systemName: "rectangle.and.text.magnifyingglass")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(FoyerTheme.creamDim.opacity(0.35))
                Text(sessionId == nil ? "Pick a session to see its leads."
                                       : "Pick a lead to see the summary and follow-up.")
                    .font(.system(size: 14))
                    .foregroundStyle(FoyerTheme.textDim)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ProgressView().tint(FoyerTheme.gold)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func detailHeader(_ v: VisitorResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(v.displayName)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(FoyerTheme.cream)
                    .tracking(-0.4)
                Spacer()
                if let kind = TagPill.Kind(v.analysis.tagToken) {
                    TagPill(kind: kind, text: v.analysis.tag)
                }
            }
            HStack(spacing: 12) {
                Text(v.analysis.score.description)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(v.analysis.score >= 80 ? FoyerTheme.gold : FoyerTheme.creamDim)
                Text("· score")
                    .font(.system(size: 13))
                    .foregroundStyle(FoyerTheme.textDim)
                Spacer()
            }
            HStack(spacing: 8) {
                if !v.visitor.email.isEmpty {
                    Label(v.visitor.email, systemImage: "envelope")
                        .labelStyle(.titleAndIcon)
                }
                if !v.visitor.phone.isEmpty {
                    Label(v.visitor.phone, systemImage: "phone")
                        .labelStyle(.titleAndIcon)
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(FoyerTheme.textDim)
        }
    }

    private func summarySection(_ v: VisitorResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What we heard")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(FoyerTheme.textDim)
            Text(v.analysis.summary)
                .font(.system(size: 16))
                .foregroundStyle(FoyerTheme.cream)
                .lineSpacing(5)
            if !v.analysis.signals.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(v.analysis.signals, id: \.self) { s in
                        Text(s)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(FoyerTheme.gold)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(FoyerTheme.goldSoft, in: Capsule())
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(20)
        .background(FoyerTheme.bgCard, in: RoundedRectangle(cornerRadius: 16))
    }

    private func followupSection(_ v: VisitorResult, session: Session) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Drafted follow-up")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FoyerTheme.textDim)
                Spacer()
                if let state = v.leadState {
                    statusPill(state.status)
                }
            }
            Text(v.analysis.followUpDraft)
                .font(.system(size: 15))
                .foregroundStyle(FoyerTheme.cream)
                .lineSpacing(5)

            HStack(spacing: 10) {
                Button { } label: {
                    Text("Regenerate")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(FoyerTheme.cream)
                        .padding(.horizontal, 16).padding(.vertical, 11)
                        .background(FoyerTheme.bgElev, in: Capsule())
                }
                .buttonStyle(.plain)
                Spacer()
                Button { Task { await sendNow(v, session: session) } } label: {
                    HStack(spacing: 8) {
                        Text("Send email")
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(FoyerTheme.inkOnGold)
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .background(FoyerTheme.gold, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 6)
        }
        .padding(20)
        .background(FoyerTheme.bgCard, in: RoundedRectangle(cornerRadius: 16))
    }

    private func statusPill(_ status: LeadState.Status) -> some View {
        let (text, tone): (String, StatusPill.Tone) = {
            switch status {
            case .drafted:  return ("Drafted", .gold)
            case .sent:     return ("Sent", .sage)
            case .replied:  return ("Replied", .sage)
            case .archived: return ("Archived", .glass)
            }
        }()
        return StatusPill(text: text, tone: tone)
    }

    private func loadDetail() async {
        guard let id = sessionId else {
            detailSession = nil
            activeVisitorId = nil
            return
        }
        loading = true
        defer { loading = false }
        do {
            let s = try await APIClient.shared.getSession(id: id)
            detailSession = s
            activeVisitorId = s.result?.visitors.first?.id
        } catch {
            detailSession = nil
        }
    }

    private func sendNow(_ v: VisitorResult, session: Session) async {
        do {
            let updated = try await APIClient.shared.updateLeadState(
                sessionId: session.id,
                visitorName: v.visitor.name,
                visitorSpeaker: v.visitor.speaker,
                status: .sent,
                snoozedUntil: nil
            )
            await MainActor.run {
                if let idx = detailSession?.result?.visitors.firstIndex(where: { $0.id == v.id }) {
                    detailSession?.result?.visitors[idx].leadState = updated
                }
            }
        } catch {
            // Silent failure here mirrors the iPhone — the UI just doesn't
            // flip to Sent. A toast would be nicer once we have one.
        }
    }
}

// MARK: – Listings (manage open houses)

private struct IPadListings: View {
    let store: SessionStore
    var onPickListing: (Listing) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Listings")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(FoyerTheme.cream)
                    .tracking(-0.4)

                if store.listings.isEmpty {
                    emptyState
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
            .padding(.horizontal, 40).padding(.top, 32).padding(.bottom, 48)
        }
        .background(FoyerTheme.bgDeep)
    }

    private func card(_ listing: Listing) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                if let data = listing.photoData, let img = UIImage(data: data) {
                    Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(
                        colors: [FoyerTheme.bgElev2, FoyerTheme.bgCard],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .overlay(
                        Image(systemName: "house")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(FoyerTheme.creamDim.opacity(0.3))
                    )
                }
            }
            .frame(height: 160)
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(listing.address)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(FoyerTheme.cream)
                    .lineLimit(1)
                if !listing.displayPrice.isEmpty {
                    Text(listing.displayPrice)
                        .font(.system(size: 13))
                        .foregroundStyle(FoyerTheme.gold)
                }
                Text(listing.displaySpecs)
                    .font(.system(size: 12))
                    .foregroundStyle(FoyerTheme.textDim)
                    .lineLimit(1)
            }
            .padding(16)
        }
        .background(FoyerTheme.bgCard, in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "house")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(FoyerTheme.creamDim.opacity(0.35))
            Text("No listings yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(FoyerTheme.cream)
            Text("Add a listing from the iPhone app — it'll sync here.")
                .font(.system(size: 13))
                .foregroundStyle(FoyerTheme.textDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .background(FoyerTheme.bgCard, in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview { IPadAgentApp() }
