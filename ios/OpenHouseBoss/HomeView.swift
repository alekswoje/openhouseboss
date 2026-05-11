import SwiftUI
import UIKit

// MARK: – HomeShell — paged ScrollView with live-tracking tab underline

// Replaces TabView so we can read the horizontal scroll offset as the user
// swipes and animate the bottom-bar underline continuously (Instagram-style),
// instead of jumping at the end of the swipe.
struct HomeShell: View {
    @Environment(AppRouter.self) private var router
    // Drives the bottom-bar underline. Updated from two sources:
    //   • scroll preference → continuous during swipes (Instagram-style)
    //   • onChange(router.tab) → animated jump for tab taps, since
    //     programmatic scrollPosition changes don't reliably fire the
    //     scroll-preference reads on iOS 17.
    @State private var pageFraction: CGFloat = 0   // 0..(N-1)

    private let tabs = HomeTab.allCases

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                FoyerTheme.bgDeep.ignoresSafeArea()
                paged(width: geo.size.width)
                tabBar(totalWidth: geo.size.width)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: router.tab) { _, new in
            if let idx = tabs.firstIndex(of: new) {
                withAnimation(.easeInOut(duration: 0.28)) {
                    pageFraction = CGFloat(idx)
                }
            }
        }
    }

    private func paged(width: CGFloat) -> some View {
        @Bindable var router = router
        let pos = Binding<HomeTab?>(
            get: { router.tab },
            set: { if let t = $0 { router.tab = t } }
        )

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(tabs, id: \.self) { t in
                    page(t)
                        .frame(width: width)
                        .id(t)
                }
            }
            .scrollTargetLayout()
            .background(
                GeometryReader { proxy in
                    let minX = proxy.frame(in: .named("hscroll")).minX
                    Color.clear.preference(
                        key: ScrollOffsetKey.self,
                        value: -minX / max(width, 1)
                    )
                }
            )
        }
        .coordinateSpace(name: "hscroll")
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: pos)
        .onPreferenceChange(ScrollOffsetKey.self) { newValue in
            // No animation here — the value already streams continuously
            // from the scroll, so wrapping it in withAnimation would just
            // make the underline lag the finger.
            pageFraction = newValue
        }
        .ignoresSafeArea(edges: .bottom)
    }

    @ViewBuilder
    private func page(_ t: HomeTab) -> some View {
        switch t {
        case .sessions: SessionsTabContent()
        case .visitors: VisitorsTabContent()
        case .scripts:  ScriptsTabContent()
        case .profile:  ProfileTabContent()
        }
    }

    private func tabBar(totalWidth: CGFloat) -> some View {
        let n = CGFloat(tabs.count)
        let inset: CGFloat = 4
        let tabWidth = (totalWidth - inset * 2) / n
        let underlineW: CGFloat = 28
        let underlineX = inset + tabWidth * pageFraction + tabWidth / 2 - underlineW / 2

        return VStack(spacing: 0) {
            Rectangle()
                .fill(FoyerTheme.border)
                .frame(height: 0.5)

            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(tabs, id: \.self) { t in
                        tabButton(t)
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 24)
                .padding(.horizontal, inset)

                Capsule()
                    .fill(FoyerTheme.gold)
                    .frame(width: underlineW, height: 2.5)
                    .offset(x: underlineX, y: 0)
            }
            .background(FoyerTheme.bg)
        }
    }

    private func tabButton(_ t: HomeTab) -> some View {
        @Bindable var router = router
        let active = router.tab == t
        return Button {
            withAnimation(.easeInOut(duration: 0.28)) {
                router.tab = t
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: t.icon)
                    .font(.system(size: 18, weight: active ? .semibold : .regular))
                    .scaleEffect(active ? 1.05 : 1)
                Text(t.label)
                    .font(.system(size: 10, weight: .medium))
                    .tracking(0.3)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(active ? FoyerTheme.gold : FoyerTheme.textMuted)
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.2), value: active)
        }
        .buttonStyle(.plain)
    }
}

// Bubbles the live horizontal scroll offset (in pages) up through the view
// tree so the tab bar's underline can animate continuously as the user
// swipes, not just at the end.
struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: – Edge swipe-back, restored

// SwiftUI's NavigationStack disables the interactive pop gesture when the
// navigation bar is hidden (which we do on every detail screen). This
// extension hooks the underlying UINavigationController and re-enables it
// whenever there's more than one view on the stack, so swipe-from-left-edge
// to dismiss works again on Summary, Visitor, Followup, etc.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return viewControllers.count > 1
    }
}

// MARK: – Sessions tab content

struct SessionsTabContent: View {
    @Environment(AppRouter.self) private var router
    @State private var store = SessionStore.shared

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    statsCard
                    sessionsList
                    Spacer().frame(height: 120)
                }
                .padding(.top, 8)
            }
            .background(FoyerTheme.bgDeep)
            .refreshable { await store.refreshSessions() }

            addButton
        }
        .onAppear { Log.ui("SessionsTabContent appeared") }
        .task {
            await store.refreshSessions()
            await store.refreshScripts()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: todayLabel, color: FoyerTheme.gold)
            Text("Sessions")
                .foyerDisplay(38)
                .foregroundStyle(FoyerTheme.cream)
        }
        .padding(.horizontal, 20)
        .padding(.top, 56)
        .padding(.bottom, 18)
    }

    // Top-right "NEW" action — replaces the floating FAB. Opens the
    // listings picker (the new entry into the recording flow).
    private var addButton: some View {
        Button {
            store.reset()
            router.push(.picker)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                Text("NEW")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(FoyerTheme.inkOnGold)
            .background(FoyerTheme.gold, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20)
        .padding(.top, 60)
    }

    private var statsCard: some View {
        GlassSurface(cornerRadius: 12) {
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
            .padding(16)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
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
            Text("Tap NEW at the top to start your first open house.")
                .font(.system(size: 13))
                .foregroundStyle(FoyerTheme.textDim)
                .lineSpacing(3)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private func errorState(_ message: String) -> some View {
        GlassSurface(cornerRadius: 12) {
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
                Button { router.push(.visitorsAll) } label: {
                    GlassSurface(cornerRadius: 12, strong: true) {
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
                Spacer().frame(height: 120)
            }
            .padding(.top, 8)
        }
        .background(FoyerTheme.bgDeep)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "Database", color: FoyerTheme.gold)
            Text("Visitors")
                .foyerDisplay(38)
                .foregroundStyle(FoyerTheme.cream)
        }
        .padding(.horizontal, 20)
        .padding(.top, 56)
        .padding(.bottom, 18)
    }
}

// MARK: – Scripts tab content

struct ScriptsTabContent: View {
    @Environment(AppRouter.self) private var router
    @State private var store = SessionStore.shared

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if store.availableScripts.isEmpty {
                        emptyHint
                    } else {
                        Eyebrow(text: "Available")
                            .padding(.horizontal, 20)
                            .padding(.bottom, 6)
                        VStack(spacing: 10) {
                            ForEach(store.availableScripts) { s in
                                scriptCard(s)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    Spacer().frame(height: 120)
                }
                .padding(.top, 8)
            }
            .background(FoyerTheme.bgDeep)
            .refreshable { await store.refreshScripts() }

            addButton
        }
        .task { await store.refreshScripts() }
    }

    private var addButton: some View {
        Button { router.push(.scriptEdit) } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                Text("NEW")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(FoyerTheme.inkOnGold)
            .background(FoyerTheme.gold, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20)
        .padding(.top, 60)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "Open-house coaching", color: FoyerTheme.gold)
            Text("Scripts")
                .foyerDisplay(38)
                .foregroundStyle(FoyerTheme.cream)
            Text("Pick one as your default — we'll grade every session against it.")
                .font(.system(size: 13))
                .foregroundStyle(FoyerTheme.textDim)
                .padding(.top, 4)
                .lineSpacing(2)
        }
        .padding(.horizontal, 20)
        .padding(.top, 56)
        .padding(.bottom, 18)
    }

    private var emptyHint: some View {
        Text("Loading scripts…")
            .font(.system(size: 13))
            .foregroundStyle(FoyerTheme.textDim)
            .padding(.horizontal, 20)
    }

    private func scriptCard(_ s: ScriptSummary) -> some View {
        let isDefault = store.defaultScriptId == s.id
        return Button { router.push(.scriptDetail(scriptId: s.id)) } label: {
            GlassSurface(cornerRadius: 12, strong: isDefault) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(s.name)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(FoyerTheme.cream)
                            Text("\(s.stepCount) STEPS")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .tracking(1.4)
                                .foregroundStyle(FoyerTheme.textMuted)
                        }
                        Spacer()
                        if isDefault {
                            StatusPill(text: "Default", tone: .sage)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(FoyerTheme.textMuted)
                    }
                    Text(s.description)
                        .font(.system(size: 13))
                        .foregroundStyle(FoyerTheme.creamDim)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isDefault ? FoyerTheme.gold.opacity(0.4) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: – Profile tab content

struct ProfileTabContent: View {
    @Environment(AppRouter.self) private var router
    @State private var store = SessionStore.shared
    @State private var defaultScriptSheet = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                statsCard
                defaultScriptRow
                kioskRow
                versionLabel
                Spacer().frame(height: 120)
            }
            .padding(.top, 8)
        }
        .background(FoyerTheme.bgDeep)
        .sheet(isPresented: $defaultScriptSheet) { defaultScriptPicker }
        .task { await store.refreshScripts() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "Account", color: FoyerTheme.gold)
            Text("Profile")
                .foyerDisplay(38)
                .foregroundStyle(FoyerTheme.cream)
        }
        .padding(.horizontal, 20)
        .padding(.top, 56)
        .padding(.bottom, 18)
    }

    private var statsCard: some View {
        GlassSurface(cornerRadius: 12, strong: true) {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "This month", color: FoyerTheme.gold)
                HStack {
                    statBlock(value: "\(store.pastSessions.count)", label: "Houses")
                    Spacer()
                    statBlock(value: "\(store.pastSessions.reduce(0) { $0 + $1.visitorCount })", label: "Guests")
                    Spacer()
                    statBlock(value: "\(store.pastSessions.filter { $0.status == "ready" }.count)", label: "Drafts")
                }
            }
            .padding(16)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    private func statBlock(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(FoyerTheme.cream)
            Eyebrow(text: label)
        }
    }

    private var defaultScriptRow: some View {
        Button { defaultScriptSheet = true } label: {
            settingsRow(
                icon: "doc.text",
                label: "Default script",
                value: defaultScriptName ?? "None"
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }

    private var kioskRow: some View {
        Button { router.push(.kiosk) } label: {
            settingsRow(
                icon: "person.crop.rectangle",
                label: "Guest sign-in kiosk",
                value: "Hand to a guest"
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private func settingsRow(icon: String, label: String, value: String) -> some View {
        GlassSurface(cornerRadius: 12) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(FoyerTheme.goldSoft)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(FoyerTheme.gold)
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(FoyerTheme.cream)
                    Text(value)
                        .font(.system(size: 11))
                        .foregroundStyle(FoyerTheme.textMuted)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FoyerTheme.textMuted)
            }
            .padding(14)
        }
    }

    private var versionLabel: some View {
        Text("OPENHOUSEBOSS · v2.0")
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .tracking(1.6)
            .foregroundStyle(FoyerTheme.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.top, 28)
    }

    private var defaultScriptName: String? {
        guard let id = store.defaultScriptId else { return nil }
        return store.availableScripts.first(where: { $0.id == id })?.name ?? id
    }

    private var defaultScriptPicker: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        store.defaultScriptId = nil
                        defaultScriptSheet = false
                    } label: {
                        HStack {
                            Text("No default script")
                            Spacer()
                            if store.defaultScriptId == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(FoyerTheme.gold)
                            }
                        }
                    }
                    .foregroundStyle(FoyerTheme.cream)
                    ForEach(store.availableScripts) { s in
                        Button {
                            store.defaultScriptId = s.id
                            defaultScriptSheet = false
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.name)
                                    Text(s.description)
                                        .font(.system(size: 12))
                                        .foregroundStyle(FoyerTheme.textMuted)
                                }
                                Spacer()
                                if store.defaultScriptId == s.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(FoyerTheme.gold)
                                }
                            }
                        }
                        .foregroundStyle(FoyerTheme.cream)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(FoyerTheme.bgDeep)
            .navigationTitle("Default script")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { defaultScriptSheet = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: – Listings picker (Compass-style cards, entry to recording)

struct ListingsPickerView: View {
    @Environment(AppRouter.self) private var router
    @State private var store = SessionStore.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            FoyerTheme.bgDeep.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    BackBar(crumbs: ["Sessions", "Start session"], onBack: { router.pop() }) {
                        Button { router.push(.editListing(id: nil)) } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("ADD")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .tracking(1.4)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .foregroundStyle(FoyerTheme.gold)
                            .background(FoyerTheme.goldSoft, in: Capsule())
                            .overlay(Capsule().stroke(FoyerTheme.gold.opacity(0.4), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                    header
                    listingsList
                    Spacer().frame(height: 120)
                }
                .padding(.top, 8)
            }

            blankRecordButton
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Open Houses")
                .foyerDisplay(34)
                .foregroundStyle(FoyerTheme.cream)
            Text("\(store.listings.count) listing\(store.listings.count == 1 ? "" : "s")")
                .font(.system(size: 12))
                .foregroundStyle(FoyerTheme.textDim)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var listingsList: some View {
        if store.listings.isEmpty {
            emptyListings
        } else {
            VStack(spacing: 10) {
                ForEach(store.listings) { l in
                    listingCard(l)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var emptyListings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No listings yet.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(FoyerTheme.cream)
            Text("Tap ADD up top to save your first one, or record without a listing below.")
                .font(.system(size: 13))
                .foregroundStyle(FoyerTheme.textDim)
                .lineSpacing(3)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private func listingCard(_ l: Listing) -> some View {
        Button { startRecording(with: l) } label: {
            HStack(spacing: 14) {
                listingPhoto(l)
                VStack(alignment: .leading, spacing: 4) {
                    Text(l.address)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(FoyerTheme.cream)
                        .lineLimit(1)
                    Text(l.neighborhood)
                        .font(.system(size: 12))
                        .foregroundStyle(FoyerTheme.textDim)
                    Spacer().frame(height: 2)
                    if !l.displayPrice.isEmpty {
                        Text(l.displayPrice)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(FoyerTheme.gold)
                    }
                    Text(l.displaySpecs)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(FoyerTheme.textMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(FoyerTheme.bgCard, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(FoyerTheme.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { router.push(.editListing(id: l.id)) } label: {
                Label("Edit listing", systemImage: "pencil")
            }
            Button(role: .destructive) { store.deleteListing(id: l.id) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func listingPhoto(_ l: Listing) -> some View {
        if let data = l.photoData, let img = UIImage(data: data) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 110, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(FoyerTheme.bgElev)
                Image(systemName: "house.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(FoyerTheme.textMuted)
            }
            .frame(width: 110, height: 96)
        }
    }

    private var blankRecordButton: some View {
        Button { startRecording(with: nil) } label: {
            HStack(spacing: 10) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("Record without a listing")
            }
        }
        .buttonStyle(FoyerGhostButton())
        .padding(.horizontal, 20)
        .padding(.bottom, 32)
    }

    private func startRecording(with listing: Listing?) {
        @Bindable var router = router
        SessionStore.shared.reset()
        SessionStore.shared.pendingAddress = listing.map { "\($0.address) · \($0.neighborhood)" }
        // pendingScriptId stays nil → defaultScriptId picks it up automatically.
        router.path = [.live]
    }
}

// MARK: – Listing edit (create / edit a saved listing)

struct ListingEditView: View {
    let listingId: String?
    @Environment(AppRouter.self) private var router
    @State private var store = SessionStore.shared
    @State private var address: String = ""
    @State private var neighborhood: String = ""
    @State private var price: String = ""
    @State private var beds: Int = 3
    @State private var baths: Double = 2
    @State private var sqft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            FoyerTheme.bgDeep.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    BackBar(crumbs: ["Listings", listingId == nil ? "New" : "Edit"], onBack: { router.pop() })
                    title
                    form
                    Spacer().frame(height: 140)
                }
                .padding(.top, 8)
            }
            saveButton
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            focused = true
            if let id = listingId, let l = store.listings.first(where: { $0.id == id }) {
                address = l.address
                neighborhood = l.neighborhood
                price = l.price > 0 ? String(l.price) : ""
                beds = l.beds
                baths = l.baths
                sqft = l.sqft > 0 ? String(l.sqft) : ""
            }
        }
    }

    private var title: some View {
        Text(listingId == nil ? "New listing" : "Edit listing")
            .foyerDisplay(28)
            .foregroundStyle(FoyerTheme.cream)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 18)
    }

    private var form: some View {
        VStack(spacing: 10) {
            textField("Address", text: $address, placeholder: "1936 17th Ave NE")
                .focused($focused)
            textField("Neighborhood", text: $neighborhood, placeholder: "Issaquah Highlands")
            numericField("Price ($)", text: $price, placeholder: "850000")
            HStack(spacing: 10) {
                stepperField("Beds", value: $beds, range: 0...10)
                stepperField("Baths", value: $baths, range: 0...10, step: 0.5)
            }
            numericField("Square feet", text: $sqft, placeholder: "1510")
        }
        .padding(.horizontal, 20)
    }

    private func textField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        GlassSurface(cornerRadius: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: label, color: FoyerTheme.gold)
                TextField("", text: text,
                          prompt: Text(placeholder).foregroundStyle(FoyerTheme.textMuted.opacity(0.7)))
                    .font(.system(size: 15))
                    .foregroundStyle(FoyerTheme.cream)
                    .tint(FoyerTheme.gold)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private func numericField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        GlassSurface(cornerRadius: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: label, color: FoyerTheme.gold)
                TextField("", text: text,
                          prompt: Text(placeholder).foregroundStyle(FoyerTheme.textMuted.opacity(0.7)))
                    .font(.system(size: 15))
                    .foregroundStyle(FoyerTheme.cream)
                    .tint(FoyerTheme.gold)
                    .keyboardType(.numberPad)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private func stepperField(_ label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        GlassSurface(cornerRadius: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: label, color: FoyerTheme.gold)
                Stepper(value: value, in: range) {
                    Text("\(value.wrappedValue)")
                        .font(.system(size: 15))
                        .foregroundStyle(FoyerTheme.cream)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func stepperField(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        GlassSurface(cornerRadius: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: label, color: FoyerTheme.gold)
                Stepper(value: value, in: range, step: step) {
                    Text(value.wrappedValue.truncatingRemainder(dividingBy: 1) == 0
                         ? "\(Int(value.wrappedValue))"
                         : String(format: "%.1f", value.wrappedValue))
                        .font(.system(size: 15))
                        .foregroundStyle(FoyerTheme.cream)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private var saveButton: some View {
        Button(action: save) {
            Text(listingId == nil ? "Save listing" : "Save changes")
        }
        .buttonStyle(FoyerPrimaryButton())
        .padding(.horizontal, 20)
        .padding(.bottom, 36)
        .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
        .opacity(address.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
    }

    private func save() {
        let listing = Listing(
            id: listingId ?? UUID().uuidString,
            address: address.trimmingCharacters(in: .whitespaces),
            neighborhood: neighborhood.trimmingCharacters(in: .whitespaces),
            price: Int(price) ?? 0,
            beds: beds,
            baths: baths,
            sqft: Int(sqft) ?? 0,
            photoData: nil
        )
        if listingId == nil {
            store.addListing(listing)
        } else {
            store.updateListing(listing)
        }
        router.pop()
    }
}

// MARK: – Script detail (view + set as default)

struct ScriptDetailView: View {
    let scriptId: String
    @Environment(AppRouter.self) private var router
    @State private var store = SessionStore.shared

    var body: some View {
        let script = store.availableScripts.first(where: { $0.id == scriptId })
        ZStack(alignment: .bottom) {
            FoyerTheme.bgDeep.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    BackBar(crumbs: ["Scripts", script?.name ?? "Script"], onBack: { router.pop() })
                    if let s = script {
                        scriptHeader(s)
                        stepsList
                    }
                    Spacer().frame(height: 140)
                }
                .padding(.top, 8)
            }
            defaultToggle
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func scriptHeader(_ s: ScriptSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "\(s.stepCount) steps", color: FoyerTheme.gold)
            Text(s.name)
                .foyerDisplay(28)
                .foregroundStyle(FoyerTheme.cream)
            Text(s.description)
                .font(.system(size: 13))
                .foregroundStyle(FoyerTheme.textDim)
                .lineSpacing(2)
                .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 18)
    }

    private var stepsList: some View {
        // Step labels live in ScriptStepLookup (mirror of pipeline/scripts.py).
        // We only know labels client-side; verbatim quotes live in the
        // backend and can be fetched via /scripts/{id} when we want a
        // richer preview here.
        let ordered: [String] = [
            "opener", "buyer_timeline", "buyer_search_history",
            "buyer_pain", "buyer_offer_check", "buyer_lender",
            "buyer_release", "buyer_reengage", "buyer_close_rebate",
            "seller_pricing", "seller_curiosity", "seller_marketing",
            "seller_comp",
        ]
        return VStack(spacing: 8) {
            ForEach(ordered, id: \.self) { id in
                HStack {
                    Text(ScriptStepLookup.label(for: id))
                        .font(.system(size: 14))
                        .foregroundStyle(FoyerTheme.cream)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(FoyerTheme.bgCard, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(FoyerTheme.border, lineWidth: 0.5))
            }
        }
        .padding(.horizontal, 20)
    }

    private var defaultToggle: some View {
        let isDefault = store.defaultScriptId == scriptId
        return Button {
            store.defaultScriptId = isDefault ? nil : scriptId
        } label: {
            Text(isDefault ? "Remove as default" : "Set as default")
        }
        .buttonStyle(isDefault ? AnyButtonStyle(FoyerGhostButton()) : AnyButtonStyle(FoyerPrimaryButton()))
        .padding(.horizontal, 20)
        .padding(.bottom, 36)
    }
}

// Helper — wrap two ButtonStyles so we can conditionally apply one.
struct AnyButtonStyle: ButtonStyle {
    private let _makeBody: (ButtonStyleConfiguration) -> AnyView
    init<S: ButtonStyle>(_ style: S) {
        _makeBody = { config in AnyView(style.makeBody(configuration: config)) }
    }
    func makeBody(configuration: Configuration) -> some View {
        _makeBody(configuration)
    }
}

// MARK: – All visitors (across sessions)

struct AllVisitorsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router

    @State private var rows: [VisitorRow] = []
    @State private var loading = true
    @State private var error: String?
    @State private var query: String = ""
    @State private var tagFilter: String = "all"
    @State private var stateFilter: String = "needs"   // needs | snoozed | done | all

    struct VisitorRow: Identifiable {
        let id: String
        let visitor: VisitorResult
        let sessionId: String
        let sessionAddress: String?
        let sessionDate: String
        let sessionCreatedAt: Date?
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            FoyerTheme.bgDeep.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    BackBar(crumbs: ["Visitors"], onBack: { dismiss() }) {
                        StatusPill(text: "\(filteredRows.count)", tone: .gold)
                    }
                    header
                    searchField
                    stateChips
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
        // Re-pull on appear so state changes made on the detail screen are
        // reflected immediately when the agent comes back to the inbox.
        .onAppear { Task { await load() } }
    }

    private var stateChips: some View {
        HStack(spacing: 6) {
            ForEach([("needs","Needs action"),("snoozed","Snoozed"),("done","Done"),("all","All")], id: \.0) { kv in
                GlassChip(text: kv.1, active: stateFilter == kv.0) { stateFilter = kv.0 }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
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
        GlassSurface(cornerRadius: 10) {
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
        let filtered = rows.filter { r in
            let kind = r.visitor.analysis.tagToken
            let tagOK = tagFilter == "all" || kind == tagFilter
            guard tagOK else { return false }
            let bucket = stateBucket(r.visitor.leadState)
            let stateOK = stateFilter == "all" || stateFilter == bucket
            guard stateOK else { return false }
            let q = query.lowercased().trimmingCharacters(in: .whitespaces)
            if q.isEmpty { return true }
            if r.visitor.visitor.name.lowercased().contains(q) { return true }
            if r.sessionAddress?.lowercased().contains(q) == true { return true }
            return r.visitor.analysis.signals.contains { $0.lowercased().contains(q) }
        }
        return filtered.sorted { a, b in
            // Needs-action first, then snoozed, then done. Within each
            // bucket: newest session first, ties broken by score desc.
            let ra = bucketRank(stateBucket(a.visitor.leadState))
            let rb = bucketRank(stateBucket(b.visitor.leadState))
            if ra != rb { return ra < rb }
            let da = a.sessionCreatedAt ?? .distantPast
            let db = b.sessionCreatedAt ?? .distantPast
            if da != db { return da > db }
            return a.visitor.analysis.score > b.visitor.analysis.score
        }
    }

    // Collapses (status, snoozedUntil) into a single inbox bucket. Sent +
    // snoozed-in-future → "snoozed". Drafted or sent-without-snooze →
    // "needs". Replied + archived → "done".
    private func stateBucket(_ s: LeadState?) -> String {
        guard let s else { return "needs" }
        if s.isSnoozedNow { return "snoozed" }
        switch s.status {
        case .drafted:           return "needs"
        case .sent:              return "needs"
        case .replied, .archived: return "done"
        }
    }

    private func bucketRank(_ bucket: String) -> Int {
        switch bucket {
        case "needs":   return 0
        case "snoozed": return 1
        case "done":    return 2
        default:        return 3
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
        GlassSurface(cornerRadius: 10) {
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
                    HStack(spacing: 6) {
                        Text(r.visitor.visitor.name)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(FoyerTheme.cream)
                        stateBadge(r.visitor.leadState)
                    }
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

    @ViewBuilder
    private func stateBadge(_ s: LeadState?) -> some View {
        if let s {
            let (label, tone): (String, Color) = {
                if s.isSnoozedNow { return ("SNOOZED", FoyerTheme.creamDim) }
                switch s.status {
                case .drafted:  return ("DRAFT", FoyerTheme.gold)
                case .sent:     return ("SENT", FoyerTheme.sage)
                case .replied:  return ("REPLIED", FoyerTheme.sage)
                case .archived: return ("ARCHIVED", FoyerTheme.textMuted)
                }
            }()
            Text(label)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(tone)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(tone.opacity(0.12), in: Capsule())
                .overlay(Capsule().stroke(tone.opacity(0.4), lineWidth: 0.5))
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
                        sessionDate: dateLabel,
                        sessionCreatedAt: summary.createdDate
                    ))
                }
            }
        }
        // Final ordering happens in filteredRows so state-bucket priority
        // (needs → snoozed → done) wins over recency.
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

// MARK: – Kiosk sign-in

struct KioskSignInView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var pendingGuests: [VisitorInput] = []

    var body: some View {
        ZStack(alignment: .bottom) {
            FoyerTheme.bgDeep.ignoresSafeArea()
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
        GlassSurface(cornerRadius: 10) {
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
        SessionStore.shared.pendingKioskGuests = pendingGuests
        dismiss()
    }
}

// MARK: – Script editor (create a new custom script)

// Agent flow: name + description up top, then a list of editable step rows.
// Each step has a label ("Step 1 — Timeline"), the verbatim line they want
// to say, and a short note on intent. Save POSTs to /scripts.
struct ScriptEditView: View {
    @Environment(AppRouter.self) private var router
    @State private var store = SessionStore.shared
    @State private var name: String = ""
    @State private var description: String = ""
    @State private var steps: [ScriptStepDraft] = [ScriptStepDraft(label: "Step 1")]
    @State private var saving = false
    @State private var saveError: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            FoyerTheme.bgDeep.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    BackBar(crumbs: ["Scripts", "New"], onBack: { router.pop() })
                    title
                    nameAndDesc
                    stepsSection
                    if let err = saveError { errorBanner(err) }
                    Spacer().frame(height: 140)
                }
                .padding(.top, 8)
            }
            saveBar
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "Custom script", color: FoyerTheme.gold)
            Text("New script")
                .foyerDisplay(28)
                .foregroundStyle(FoyerTheme.cream)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 18)
    }

    private var nameAndDesc: some View {
        VStack(spacing: 10) {
            textField("Script name", text: $name, placeholder: "My buyer flow")
            textField("Description", text: $description, placeholder: "Lead qualification + rebate close")
        }
        .padding(.horizontal, 20)
    }

    private func textField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        GlassSurface(cornerRadius: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: label, color: FoyerTheme.gold)
                TextField("", text: text,
                          prompt: Text(placeholder).foregroundStyle(FoyerTheme.textMuted.opacity(0.7)))
                    .font(.system(size: 15))
                    .foregroundStyle(FoyerTheme.cream)
                    .tint(FoyerTheme.gold)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow(text: "Steps · \(steps.count)")
                Spacer()
                Button { addStep() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                        Text("ADD STEP")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .tracking(1.4)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .foregroundStyle(FoyerTheme.gold)
                    .background(FoyerTheme.goldSoft, in: Capsule())
                    .overlay(Capsule().stroke(FoyerTheme.gold.opacity(0.4), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)

            VStack(spacing: 10) {
                ForEach($steps) { $step in
                    stepCard($step, index: steps.firstIndex(where: { $0.id == step.id }) ?? 0)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 22)
    }

    private func stepCard(_ step: Binding<ScriptStepDraft>, index: Int) -> some View {
        GlassSurface(cornerRadius: 10) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("STEP \(index + 1)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(FoyerTheme.gold)
                    Spacer()
                    if steps.count > 1 {
                        Button { removeStep(id: step.id) } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundStyle(FoyerTheme.terracotta)
                        }
                        .buttonStyle(.plain)
                    }
                }
                miniField("Label", text: step.label, placeholder: "Establish the timeline")
                miniField("What you'll say", text: step.quote, placeholder: "So are you getting close to making a move?", multiline: true)
                miniField("Why it matters", text: step.intent, placeholder: "Sorts active buyers from window-shoppers", multiline: true)
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private func miniField(_ label: String, text: Binding<String>, placeholder: String, multiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(text: label)
            if multiline {
                TextField("", text: text,
                          prompt: Text(placeholder).foregroundStyle(FoyerTheme.textMuted.opacity(0.7)),
                          axis: .vertical)
                    .font(.system(size: 14))
                    .foregroundStyle(FoyerTheme.cream)
                    .tint(FoyerTheme.gold)
                    .lineLimit(2...5)
            } else {
                TextField("", text: text,
                          prompt: Text(placeholder).foregroundStyle(FoyerTheme.textMuted.opacity(0.7)))
                    .font(.system(size: 14))
                    .foregroundStyle(FoyerTheme.cream)
                    .tint(FoyerTheme.gold)
            }
        }
    }

    private func errorBanner(_ msg: String) -> some View {
        GlassSurface(cornerRadius: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(FoyerTheme.terracotta)
                Text(msg)
                    .font(.system(size: 13))
                    .foregroundStyle(FoyerTheme.cream)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var saveBar: some View {
        Button(action: save) {
            Text(saving ? "Saving…" : "Save script")
        }
        .buttonStyle(FoyerPrimaryButton())
        .padding(.horizontal, 20)
        .padding(.bottom, 36)
        .disabled(!canSave || saving)
        .opacity(canSave && !saving ? 1 : 0.4)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        steps.contains { !$0.label.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func addStep() {
        withAnimation { steps.append(ScriptStepDraft(label: "Step \(steps.count + 1)")) }
    }

    private func removeStep(id: String) {
        withAnimation { steps.removeAll { $0.id == id } }
    }

    private func save() {
        saving = true
        saveError = nil
        let cleaned = steps.filter { !$0.label.trimmingCharacters(in: .whitespaces).isEmpty }
        Task {
            do {
                _ = try await APIClient.shared.createScript(
                    name: name.trimmingCharacters(in: .whitespaces),
                    description: description.trimmingCharacters(in: .whitespaces),
                    steps: cleaned
                )
                await store.refreshScripts()
                await MainActor.run {
                    saving = false
                    router.pop()
                }
            } catch {
                await MainActor.run {
                    saving = false
                    saveError = error.localizedDescription
                }
            }
        }
    }
}
