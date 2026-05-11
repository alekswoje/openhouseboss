import SwiftUI

// HomeShell — the root tabbed shell for the iPhone flow. Holds the tab bar
// + FAB at the bottom; the body swaps between Sessions / Visitors / Kiosk /
// Profile content. Pushing destinations is routed through the AppRouter
// (NavigationPath-based) so we can collapse the stack after end-session.
struct HomeShell: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        ZStack(alignment: .bottom) {
            FoyerTheme.bgDeep.ignoresSafeArea()
            WarmBg(tone: backgroundTone)

            content

            tabBar
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var backgroundTone: WarmBg.Tone {
        switch router.tab {
        case .sessions: return .gold
        case .visitors: return .gold
        case .kiosk:    return .auth
        case .profile:  return .cool
        }
    }

    @ViewBuilder
    private var content: some View {
        switch router.tab {
        case .sessions: SessionsTabContent()
        case .visitors: VisitorsTabContent()
        case .kiosk:    KioskTabContent()
        case .profile:  ProfileTabContent()
        }
    }

    // Floating tab bar + cyan FAB. FAB action depends on the active tab:
    // Sessions → start a new session; Kiosk → launch the sign-in flow; etc.
    private var tabBar: some View {
        HStack(spacing: 10) {
            GlassSurface(cornerRadius: 14, strong: true) {
                HStack(spacing: 0) {
                    ForEach(HomeTab.allCases, id: \.self) { t in
                        tabItem(t)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .frame(height: 60)
            }

            Button(action: handleFAB) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(FoyerTheme.gold)
                    Image(systemName: fabIcon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(FoyerTheme.inkOnGold)
                }
                .frame(width: 60, height: 60)
                .shadow(color: FoyerTheme.gold.opacity(0.30), radius: 14, x: 0, y: 8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
    }

    private func tabItem(_ t: HomeTab) -> some View {
        let active = router.tab == t
        return Button {
            router.tab = t
        } label: {
            VStack(spacing: 3) {
                Image(systemName: t.icon)
                    .font(.system(size: 17, weight: .medium))
                Text(t.label.uppercased())
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .tracking(1.4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .foregroundStyle(active ? FoyerTheme.gold : FoyerTheme.textMuted)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(active ? FoyerTheme.goldSoft : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var fabIcon: String {
        switch router.tab {
        case .sessions: return "plus"
        case .visitors: return "magnifyingglass"
        case .kiosk:    return "qrcode"
        case .profile:  return "gearshape"
        }
    }

    private func handleFAB() {
        switch router.tab {
        case .sessions:
            SessionStore.shared.reset()
            router.push(.setup)
        case .visitors:
            router.push(.visitorsAll)
        case .kiosk:
            router.push(.kiosk)
        case .profile:
            break
        }
    }
}

// MARK: – Sessions tab content (the previous home body)

struct SessionsTabContent: View {
    @Environment(AppRouter.self) private var router
    @State private var store = SessionStore.shared

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                statsCard
                sessionsList
                Spacer().frame(height: 160)
            }
            .padding(.top, 8)
        }
        .onAppear { Log.ui("SessionsTabContent appeared") }
        .task {
            Log.ui("SessionsTabContent.task fired refreshSessions")
            await store.refreshSessions()
        }
        .refreshable { await store.refreshSessions() }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: todayLabel, color: FoyerTheme.gold)
                Text("Sessions")
                    .foyerDisplay(38)
                    .foregroundStyle(FoyerTheme.cream)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 18)
    }

    private var statsCard: some View {
        GlassSurface(cornerRadius: 18) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: "This month")
                    HStack(spacing: 22) {
                        statBlock(value: "\(store.pastSessions.count)", label: "Open houses")
                        statBlock(value: "\(totalGuests)", label: "Guests met")
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(readyCount)")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(FoyerTheme.gold)
                    Eyebrow(text: "Drafts ready", color: FoyerTheme.gold)
                }
            }
            .padding(18)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private func statBlock(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(FoyerTheme.cream)
            Eyebrow(text: label)
        }
    }

    @ViewBuilder
    private var sessionsList: some View {
        if let err = store.listError {
            errorState(err)
        } else if store.pastSessions.isEmpty && !store.listLoading {
            emptyState
        } else {
            buckets
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "No sessions yet", color: FoyerTheme.gold)
            Text("Tap the cyan + button to start your first open house.")
                .font(.system(size: 13))
                .foregroundStyle(FoyerTheme.textDim)
                .lineSpacing(3)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private func errorState(_ message: String) -> some View {
        GlassSurface(cornerRadius: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Can't reach the backend", color: FoyerTheme.terracotta)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(FoyerTheme.cream)
                Text("Make sure the server is running at \(Config.backendURL.absoluteString).")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(FoyerTheme.textMuted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var buckets: some View {
        let b = bucketSessions()
        return VStack(alignment: .leading, spacing: 18) {
            if !b.today.isEmpty    { section(title: "Today",     rows: b.today) }
            if !b.thisWeek.isEmpty { section(title: "This week", rows: b.thisWeek) }
            if !b.older.isEmpty    { section(title: "Earlier",   rows: b.older) }
        }
        .padding(.top, 4)
    }

    private func section(title: String, rows: [SessionSummary]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(text: title)
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, s in
                Button { router.push(.pastSession(id: s.id)) } label: {
                    row(s)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .overlay(alignment: .bottom) {
                    if idx < rows.count - 1 {
                        Hairline().padding(.horizontal, 20)
                    }
                }
            }
        }
    }

    private func row(_ s: SessionSummary) -> some View {
        let (addr, unit) = splitTitle(s.displayTitle)
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(addr)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(FoyerTheme.cream)
                        .lineLimit(1)
                    if let unit {
                        Text(unit)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(FoyerTheme.gold)
                            .lineLimit(1)
                    }
                }
                HStack(spacing: 8) {
                    Text(formatDate(s.createdDate))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(FoyerTheme.textMuted)
                    if s.visitorCount > 0 {
                        Text("·")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(FoyerTheme.textMuted)
                        Text("\(s.visitorCount) guests".uppercased())
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .tracking(1.4)
                            .foregroundStyle(FoyerTheme.textMuted)
                    }
                }
            }
            Spacer(minLength: 0)
            statusChip(s.status)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func statusChip(_ status: String) -> some View {
        switch status {
        case "ready":      StatusPill(text: "Ready",      tone: .sage)
        case "processing": StatusPill(text: "Processing", tone: .gold, pulsing: true)
        case "error":      StatusPill(text: "Error",      tone: .live)
        default:
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(FoyerTheme.textMuted)
        }
    }

    private func splitTitle(_ title: String) -> (String, String?) {
        let parts = title.components(separatedBy: " · ")
        guard parts.count >= 2 else { return (title, nil) }
        return (parts[0], parts.dropFirst().joined(separator: " · "))
    }

    private func formatDate(_ d: Date?) -> String {
        guard let d else { return "" }
        let f = DateFormatter()
        let cal = Calendar.current
        if cal.isDateInToday(d) {
            f.dateFormat = "'TODAY · 'h:mm a"
        } else if cal.isDateInYesterday(d) {
            f.dateFormat = "'YESTERDAY · 'h:mm a"
        } else {
            f.dateFormat = "EEE MMM d"
        }
        return f.string(from: d).uppercased()
    }

    private struct Buckets {
        var today: [SessionSummary] = []
        var thisWeek: [SessionSummary] = []
        var older: [SessionSummary] = []
    }
    private func bucketSessions() -> Buckets {
        let cal = Calendar.current
        var b = Buckets()
        for s in store.pastSessions {
            guard let d = s.createdDate else { b.older.append(s); continue }
            if cal.isDateInToday(d) { b.today.append(s) }
            else if let weekAgo = cal.date(byAdding: .day, value: -7, to: Date()), d > weekAgo {
                b.thisWeek.append(s)
            } else {
                b.older.append(s)
            }
        }
        return b
    }

    private var totalGuests: Int {
        store.pastSessions.reduce(0) { $0 + $1.visitorCount }
    }
    private var readyCount: Int {
        store.pastSessions.filter { $0.status == "ready" }.count
    }
    private var todayLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f.string(from: Date()).uppercased()
    }
}

// MARK: – Visitors tab content

struct VisitorsTabContent: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                Eyebrow(text: "Pull all guests across every session.")
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                Button { router.push(.visitorsAll) } label: {
                    GlassSurface(cornerRadius: 18, strong: true) {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(FoyerTheme.goldSoft)
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(FoyerTheme.gold)
                            }
                            .frame(width: 40, height: 40)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("All visitors")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(FoyerTheme.cream)
                                Text("ACROSS EVERY OPEN HOUSE")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .tracking(1.4)
                                    .foregroundStyle(FoyerTheme.textMuted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(FoyerTheme.textMuted)
                        }
                        .padding(16)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                Spacer().frame(height: 160)
            }
            .padding(.top, 8)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "Database", color: FoyerTheme.gold)
            Text("Visitors")
                .foyerDisplay(38)
                .foregroundStyle(FoyerTheme.cream)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 18)
    }
}

// MARK: – Kiosk tab content

struct KioskTabContent: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                explainer
                launchCard
                Spacer().frame(height: 160)
            }
            .padding(.top, 8)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "Guest check-in", color: FoyerTheme.gold)
            Text("Sign-in")
                .foyerDisplay(38)
                .foregroundStyle(FoyerTheme.cream)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var explainer: some View {
        Text("Hand the phone to a guest. They'll add their name, email, and phone before the open house starts.")
            .font(.system(size: 13))
            .foregroundStyle(FoyerTheme.textDim)
            .lineSpacing(3)
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
    }

    private var launchCard: some View {
        Button { router.push(.kiosk) } label: {
            GlassSurface(cornerRadius: 18, strong: true) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(FoyerTheme.goldSoft)
                        Image(systemName: "person.crop.rectangle")
                            .font(.system(size: 18))
                            .foregroundStyle(FoyerTheme.gold)
                    }
                    .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Launch sign-in page")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(FoyerTheme.cream)
                        Text("FULL-SCREEN · NAME, EMAIL, PHONE")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .tracking(1.4)
                            .foregroundStyle(FoyerTheme.textMuted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(FoyerTheme.textMuted)
                }
                .padding(16)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }
}

// MARK: – Profile tab content (stub)

struct ProfileTabContent: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow(text: "Account", color: FoyerTheme.gold)
                Text("Profile")
                    .foyerDisplay(38)
                    .foregroundStyle(FoyerTheme.cream)
                Text("Settings, integrations and AI behavior live here. Not yet wired up.")
                    .font(.system(size: 13))
                    .foregroundStyle(FoyerTheme.textDim)
                    .padding(.top, 6)
                Spacer().frame(height: 160)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }
}

// MARK: – All visitors (across sessions)

// Fans out to each past session and collects all visitors into a flat list.
// Concurrency-friendly via TaskGroup; the home tab refreshes the session
// list, so by the time this view appears `store.pastSessions` is populated.
struct AllVisitorsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router

    @State private var rows: [VisitorRow] = []
    @State private var loading = true
    @State private var error: String?
    @State private var query: String = ""
    @State private var tagFilter: String = "all"   // all / buyer / seller / browser

    struct VisitorRow: Identifiable {
        let id: String
        let visitor: VisitorResult
        let sessionId: String
        let sessionAddress: String?
        let sessionDate: String
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            FoyerTheme.bgDeep.ignoresSafeArea()
            WarmBg(tone: .gold)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    BackBar(crumbs: ["Visitors"], onBack: { dismiss() }) {
                        StatusPill(text: "\(filteredRows.count)", tone: .gold)
                    }
                    header
                    searchField
                    filterChips
                    list
                    Spacer().frame(height: 60)
                }
                .padding(.top, 8)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("All visitors")
                .foyerDisplay(32)
                .foregroundStyle(FoyerTheme.cream)
            Text("\(rows.count) total · \(SessionStore.shared.pastSessions.count) open houses".uppercased())
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(FoyerTheme.textMuted)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private var searchField: some View {
        GlassSurface(cornerRadius: 12, strong: true) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(FoyerTheme.textMuted)
                TextField("", text: $query,
                          prompt: Text("Name, signal, address…").foregroundStyle(FoyerTheme.textMuted.opacity(0.7)))
                    .font(.system(size: 14))
                    .foregroundStyle(FoyerTheme.cream)
                    .tint(FoyerTheme.gold)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(FoyerTheme.textMuted)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .padding(.horizontal, 20)
    }

    private var filterChips: some View {
        HStack(spacing: 6) {
            ForEach([("all","All"),("buyer","Buyers"),("seller","Sellers"),("browser","Browsers")], id: \.0) { kv in
                GlassChip(text: kv.1, active: tagFilter == kv.0) { tagFilter = kv.0 }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var filteredRows: [VisitorRow] {
        rows.filter { r in
            let kind = r.visitor.analysis.tagToken
            let tagOK = tagFilter == "all" || kind == tagFilter
            guard tagOK else { return false }
            let q = query.lowercased().trimmingCharacters(in: .whitespaces)
            if q.isEmpty { return true }
            if r.visitor.visitor.name.lowercased().contains(q) { return true }
            if r.sessionAddress?.lowercased().contains(q) == true { return true }
            return r.visitor.analysis.signals.contains { $0.lowercased().contains(q) }
        }
    }

    @ViewBuilder
    private var list: some View {
        if loading && rows.isEmpty {
            VStack {
                ProgressView().tint(FoyerTheme.gold)
                Text("LOADING VISITORS")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(FoyerTheme.textMuted)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else if let e = error {
            Text(e).font(.system(size: 13))
                .foregroundStyle(FoyerTheme.terracotta)
                .padding(.horizontal, 20).padding(.top, 24)
        } else if filteredRows.isEmpty {
            Text("No matches")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(FoyerTheme.textDim)
                .padding(.horizontal, 20).padding(.top, 40)
        } else {
            VStack(spacing: 8) {
                ForEach(filteredRows) { r in
                    Button { router.push(.visitorDetail(r.visitor)) } label: {
                        rowView(r)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
    }

    private func rowView(_ r: VisitorRow) -> some View {
        GlassSurface(cornerRadius: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(FoyerTheme.goldSoft)
                    Text(r.visitor.displayInitials.uppercased())
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(FoyerTheme.gold)
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(r.visitor.visitor.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(FoyerTheme.cream)
                    Text("\(r.sessionDate) · \(r.visitor.analysis.signals.first ?? r.visitor.analysis.tag)".uppercased())
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(FoyerTheme.textMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text("\(r.visitor.analysis.score)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(FoyerTheme.gold)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FoyerTheme.textMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private func load() async {
        loading = true
        error = nil
        let summaries = SessionStore.shared.pastSessions
        var collected: [VisitorRow] = []
        await withTaskGroup(of: (SessionSummary, Session?).self) { group in
            for s in summaries where s.status == "ready" {
                group.addTask {
                    let full = try? await APIClient.shared.getSession(id: s.id)
                    return (s, full)
                }
            }
            for await (summary, full) in group {
                guard let full, let result = full.result else { continue }
                let dateLabel = formatDate(summary.createdDate)
                for v in result.visitors {
                    collected.append(.init(
                        id: "\(summary.id):\(v.id)",
                        visitor: v,
                        sessionId: summary.id,
                        sessionAddress: summary.address,
                        sessionDate: dateLabel
                    ))
                }
            }
        }
        // Most recent first, hottest first within a session.
        collected.sort { a, b in
            if a.sessionDate != b.sessionDate { return a.sessionDate > b.sessionDate }
            return a.visitor.analysis.score > b.visitor.analysis.score
        }
        rows = collected
        loading = false
    }

    private func formatDate(_ d: Date?) -> String {
        guard let d else { return "" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }
}

// MARK: – Kiosk sign-in (phone-mode kiosk)

// A simplified version of the iPad kiosk: full-screen, single-shot guest
// form. Used when the agent doesn't have an iPad — they hand the phone over,
// the guest types their info, then the agent gets the phone back to record.
struct KioskSignInView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var saved: Bool = false
    @State private var pendingGuests: [VisitorInput] = []

    var body: some View {
        ZStack(alignment: .bottom) {
            FoyerTheme.bgDeep.ignoresSafeArea()
            WarmBg(tone: .auth)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    BackBar(crumbs: ["Sign-in"], onBack: { dismiss() }) {
                        StatusPill(text: "\(pendingGuests.count) checked in", tone: .sage)
                    }
                    welcome
                    fields
                    if !pendingGuests.isEmpty { checkedInList }
                    Spacer().frame(height: 140)
                }
                .padding(.top, 8)
            }

            actionBar
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "Welcome in", color: FoyerTheme.gold)
            Text("Sign in to see the listing")
                .foyerDisplay(28)
                .foregroundStyle(FoyerTheme.cream)
            Text("Your contact info — so the agent can follow up.")
                .font(.system(size: 13))
                .foregroundStyle(FoyerTheme.textDim)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 18)
    }

    private var fields: some View {
        VStack(spacing: 10) {
            field(label: "Full name", value: $name, placeholder: "Jane Marchetti", contentType: .name)
            field(label: "Email", value: $email, placeholder: "jane@example.com", contentType: .emailAddress, keyboard: .emailAddress)
            field(label: "Phone", value: $phone, placeholder: "555-0123", contentType: .telephoneNumber, keyboard: .phonePad)
        }
        .padding(.horizontal, 20)
    }

    private func field(label: String, value: Binding<String>, placeholder: String, contentType: UITextContentType, keyboard: UIKeyboardType = .default) -> some View {
        GlassSurface(cornerRadius: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: label, color: FoyerTheme.gold)
                TextField("", text: value,
                          prompt: Text(placeholder).foregroundStyle(FoyerTheme.textMuted.opacity(0.7)))
                    .font(.system(size: 16))
                    .foregroundStyle(FoyerTheme.cream)
                    .tint(FoyerTheme.gold)
                    .textContentType(contentType)
                    .keyboardType(keyboard)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private var checkedInList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Already signed in")
                .padding(.horizontal, 20)
            ForEach(pendingGuests) { g in
                HStack {
                    Text(g.name).font(.system(size: 14)).foregroundStyle(FoyerTheme.cream)
                    Spacer()
                    Text(g.email.isEmpty ? g.phone : g.email)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(FoyerTheme.textMuted)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
                .overlay(alignment: .bottom) { Hairline().padding(.horizontal, 20) }
            }
        }
        .padding(.top, 24)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button { saveOne() } label: { Text("Sign in another") }
                .buttonStyle(FoyerGhostButton())
                .frame(maxWidth: .infinity)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            Button { saveAndDone() } label: { Text("Done") }
                .buttonStyle(FoyerPrimaryButton())
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 36)
    }

    private func saveOne() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        pendingGuests.append(VisitorInput(name: trimmed, email: email, phone: phone))
        name = ""; email = ""; phone = ""
    }

    private func saveAndDone() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            pendingGuests.append(VisitorInput(name: trimmed, email: email, phone: phone))
        }
        // For now: store as pendingGuests on the session store. The recording
        // flow will pick them up when the agent starts a session.
        SessionStore.shared.pendingKioskGuests = pendingGuests
        dismiss()
    }
}
