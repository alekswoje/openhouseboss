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
            .background(HorizontalDominanceGate(nudge: router.path.count))
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

// MARK: – Horizontal dominance gate
//
// Stops the paged horizontal ScrollView from grabbing near-vertical pans.
// Without this, a downward swipe with a small lateral drift can swing the
// pager to the next tab instead of scrolling the inner vertical list.
//
// Strategy: wrap the outer horizontal UIScrollView's pan gesture delegate.
// `gestureRecognizerShouldBegin` is intercepted to reject pans whose
// initial velocity is more vertical than horizontal — the pager simply
// never starts in that case, so the inner vertical scroll picks up the
// gesture as it would for any other touch. All other delegate methods
// pass through to the scroll view's own implementation.
private struct HorizontalDominanceGate: UIViewRepresentable {
    // Bumped whenever the navigation stack changes. The actual value is
    // unused — its only job is to force SwiftUI to invoke updateUIView,
    // which re-asserts our pan delegate after a push/pop that may have
    // knocked it off.
    var nudge: Int = 0

    func makeUIView(context: Context) -> UIView {
        let v = ProbeView()
        v.isUserInteractionEnabled = false
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        (uiView as? ProbeView)?.reassertSoon()
    }

    final class ProbeView: UIView {
        private let proxy = PanDelegateProxy()
        private var lifecycleObservers: [NSObjectProtocol] = []

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                installLifecycleObservers()
            } else {
                removeLifecycleObservers()
            }
            DispatchQueue.main.async { [weak self] in self?.ensureInstalled() }
        }

        // Called from updateUIView when the navigation stack changes, and
        // from app/scene lifecycle notifications. The pop or foreground
        // animation may still be running, so we re-check on the next
        // runloop and again after a short delay to catch the post-animation
        // state where the scroll view has settled and a stale delegate
        // would otherwise win.
        func reassertSoon() {
            DispatchQueue.main.async { [weak self] in self?.ensureInstalled() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.ensureInstalled()
            }
        }

        // Re-verify on every layout pass. UIKit/SwiftUI can reset the
        // scroll view's pan-gesture delegate during navigation transitions
        // (e.g. pushing/popping a session detail), which would silently
        // drop our directional filter. Re-asserting on layout keeps it
        // attached without needing notifications or display links.
        override func layoutSubviews() {
            super.layoutSubviews()
            ensureInstalled()
        }

        private func installLifecycleObservers() {
            guard lifecycleObservers.isEmpty else { return }
            // Catch app-foreground / scene-activation. After the app is
            // backgrounded and reopened, SwiftUI sometimes rebuilds parts
            // of the hierarchy or otherwise nils out the pan delegate
            // before our usual hooks have a chance to fire.
            let names: [NSNotification.Name] = [
                UIApplication.didBecomeActiveNotification,
                UIScene.willEnterForegroundNotification,
                UIScene.didActivateNotification,
            ]
            for name in names {
                let obs = NotificationCenter.default.addObserver(
                    forName: name,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.reassertSoon()
                }
                lifecycleObservers.append(obs)
            }
        }

        private func removeLifecycleObservers() {
            for obs in lifecycleObservers {
                NotificationCenter.default.removeObserver(obs)
            }
            lifecycleObservers.removeAll()
        }

        deinit { removeLifecycleObservers() }

        private func ensureInstalled() {
            guard window != nil, let scroll = findScroll() else { return }
            let pan = scroll.panGestureRecognizer
            guard pan.delegate !== proxy else { return }
            // Always set the scroll view as the proxy's fallback. UIKit's
            // canonical setup is pan.delegate === scrollView; if the
            // delegate has been reset to nil or to a stale (dealloc'd
            // sibling) proxy during a lifecycle transition, deferring to
            // the scroll view itself is still the correct behavior and
            // preserves built-in nested-scroll handling.
            proxy.fallback = scroll as? UIGestureRecognizerDelegate
            pan.delegate = proxy
        }

        private func findScroll() -> UIScrollView? {
            var view: UIView? = superview
            while let cur = view {
                if let scroll = cur as? UIScrollView { return scroll }
                view = cur.superview
            }
            return nil
        }
    }

    final class PanDelegateProxy: NSObject, UIGestureRecognizerDelegate {
        weak var fallback: UIGestureRecognizerDelegate?

        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            if let pan = g as? UIPanGestureRecognizer {
                let v = pan.velocity(in: pan.view)
                let t = pan.translation(in: pan.view)
                // Use translation when available (more stable than velocity
                // at the moment shouldBegin fires for slow drags), but fall
                // back to velocity for fast flicks where translation is
                // still small.
                let dx = max(abs(v.x), abs(t.x) * 6)
                let dy = max(abs(v.y), abs(t.y) * 6)
                // Only let the pager claim a gesture that is clearly
                // horizontal-dominant. Requiring dx > 1.5 * dy limits tab
                // swipes to roughly within 34° of horizontal — anything
                // steeper (including ordinary diagonal scroll drift) falls
                // through so the inner vertical scroll takes the gesture.
                if dx <= dy * 1.5 {
                    return false
                }
            }
            return fallback?.gestureRecognizerShouldBegin?(g) ?? true
        }

        func gestureRecognizer(
            _ g: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            return fallback?.gestureRecognizer?(
                g, shouldRecognizeSimultaneouslyWith: other
            ) ?? false
        }

        func gestureRecognizer(
            _ g: UIGestureRecognizer,
            shouldRequireFailureOf other: UIGestureRecognizer
        ) -> Bool {
            return fallback?.gestureRecognizer?(
                g, shouldRequireFailureOf: other
            ) ?? false
        }

        func gestureRecognizer(
            _ g: UIGestureRecognizer,
            shouldBeRequiredToFailBy other: UIGestureRecognizer
        ) -> Bool {
            return fallback?.gestureRecognizer?(
                g, shouldBeRequiredToFailBy: other
            ) ?? false
        }

        func gestureRecognizer(
            _ g: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            return fallback?.gestureRecognizer?(g, shouldReceive: touch) ?? true
        }

        func gestureRecognizer(
            _ g: UIGestureRecognizer,
            shouldReceive press: UIPress
        ) -> Bool {
            return fallback?.gestureRecognizer?(g, shouldReceive: press) ?? true
        }

        func gestureRecognizer(
            _ g: UIGestureRecognizer,
            shouldReceive event: UIEvent
        ) -> Bool {
            return fallback?.gestureRecognizer?(g, shouldReceive: event) ?? true
        }
    }
}

// MARK: – Sessions tab content

struct SessionsTabContent: View {
    @Environment(AppRouter.self) private var router
    @State private var store = SessionStore.shared
    @State private var showLocalRecordingsSheet = false
    // Recomputed when the sheet opens so the user always sees current state.
    @State private var localRecordings: [SessionStore.LocalRecordingInfo] = []

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                startSessionCard
                statsCard
                sessionsList
                Spacer().frame(height: 120)
            }
            .padding(.top, 8)
        }
        .background(FoyerTheme.bgDeep)
        .refreshable { await store.refreshSessions() }
        .onAppear { Log.ui("SessionsTabContent appeared") }
        .task {
            await store.refreshSessions()
            await store.refreshScripts()
        }
        .sheet(isPresented: $showLocalRecordingsSheet) {
            LocalRecordingsPickerSheet(
                recordings: localRecordings,
                onPick: { info in
                    showLocalRecordingsSheet = false
                    store.uploadLocalRecording(at: info.url, address: nil, name: nil)
                    router.path = [.summary]
                },
                onDismiss: { showLocalRecordingsSheet = false }
            )
        }
    }

    // Local recordings folders that aren't the one being recorded right now.
    // Used by the Home banner — when this is non-empty the agent can recover
    // any prior recording whose upload failed or never happened.
    private var orphanedLocalRecordings: [SessionStore.LocalRecordingInfo] {
        let activeName = AudioRecorder.shared.chunksDirectoryName
        return store.listLocalRecordings().filter { $0.id != activeName }
    }

    // Primary action — the whole reason an agent opens this tab during an
    // open house. Big, unmistakable, mic-icon-first. Tapping is the same as
    // the old top-right NEW button (which is now gone): reset transient
    // session state, push into the listings picker.
    private var startSessionCard: some View {
        Button {
            store.reset()
            router.push(.picker)
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(FoyerTheme.inkOnGold.opacity(0.18))
                    Image(systemName: "mic.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(FoyerTheme.inkOnGold)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Start an open house")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(FoyerTheme.inkOnGold)
                    Text("TAP TO BEGIN RECORDING")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1.6)
                        .foregroundStyle(FoyerTheme.inkOnGold.opacity(0.7))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(FoyerTheme.inkOnGold.opacity(0.8))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [FoyerTheme.gold, FoyerTheme.gold.opacity(0.85)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 18)
            )
            .shadow(color: FoyerTheme.gold.opacity(0.35), radius: 14, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
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

    private var statsCard: some View {
        GlassSurface(cornerRadius: 12) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: "This month")
                    HStack(spacing: 22) {
                        statBlock(value: "\(openHousesCount)", label: "Open houses")
                        statBlock(value: "\(totalGuests)", label: "Leads")
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

    // Recorded sessions only — manual leads aren't open houses.
    private var openHousesCount: Int {
        store.pastSessions.filter { $0.kind != "manual" }.count
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
        VStack(alignment: .leading, spacing: 12) {
            if store.unfinishedRecording != nil {
                unfinishedRecordingBanner
            }
            let orphans = orphanedLocalRecordings
            if !orphans.isEmpty {
                localRecordingsBanner(count: orphans.count, largestBytes: orphans.map(\.totalBytes).max() ?? 0)
            }
            if let err = store.listError {
                errorState(err)
            } else if store.pastSessions.isEmpty && !store.listLoading {
                emptyState
            } else {
                buckets
            }
        }
    }

    // Surfaced whenever Documents/Recordings contains a chunk folder that
    // isn't the active recording. Covers two cases the iPhone path used to
    // drop on the floor: (a) End-Session upload timed out before a backend
    // session was even created, so there's no Re-analyze button and no
    // InFlightRecording either; (b) older builds that didn't write the
    // InFlightRecording at all. Tapping opens a picker with the size + date
    // for each recording so the agent can re-upload the right one.
    private func localRecordingsBanner(count: Int, largestBytes: Int64) -> some View {
        Button {
            localRecordings = orphanedLocalRecordings
            showLocalRecordingsSheet = true
        } label: {
            GlassSurface(cornerRadius: 14, strong: true) {
                HStack(spacing: 12) {
                    Image(systemName: "tray.and.arrow.up.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FoyerTheme.gold)
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow(text: "Recordings on this device", color: FoyerTheme.gold)
                        Text("\(count) recording\(count == 1 ? "" : "s") not yet uploaded · largest \(formatBytes(largestBytes)). Tap to recover.")
                            .font(.system(size: 12))
                            .foregroundStyle(FoyerTheme.creamDim)
                            .lineSpacing(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FoyerTheme.textMuted)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }

    // Surfaced on launch when the app finds an InFlightRecording with
    // cleanlyEnded=false on disk — the prior run died mid-session. Tapping
    // Recover finalizes whatever chunks are on disk through the standard
    // snapshot pipeline; Discard drops the record (chunks stay on disk for
    // manual rescue via Files.app).
    private var unfinishedRecordingBanner: some View {
        GlassSurface(cornerRadius: 14, strong: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FoyerTheme.terracotta)
                    Eyebrow(text: "Unfinished recording", color: FoyerTheme.terracotta)
                    Spacer()
                }
                Text(unfinishedRecordingSubtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(FoyerTheme.creamDim)
                    .lineSpacing(2)
                HStack(spacing: 10) {
                    Button {
                        store.recoverUnfinishedRecording()
                        router.path = [.summary]
                    } label: {
                        Text("Recover")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(FoyerTheme.inkOnGold)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(FoyerTheme.gold, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button { store.dismissUnfinishedRecording() } label: {
                        Text("Discard")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(FoyerTheme.creamDim)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private var unfinishedRecordingSubtitle: String {
        guard let r = store.unfinishedRecording else { return "" }
        let label = r.name ?? r.address ?? "Open house"
        let when: String = {
            let delta = max(0, Date().timeIntervalSince(r.startedAt))
            let h = Int(delta / 3600)
            let m = Int((delta.truncatingRemainder(dividingBy: 3600)) / 60)
            if h > 0 { return "\(h)h \(m)m ago" }
            if m > 0 { return "\(m)m ago" }
            return "just now"
        }()
        return "\(label) · started \(when). Upload the audio captured so far."
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
            if !b.live.isEmpty     { section(title: "In progress", rows: b.live) }
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
                    if s.isLive {
                        Text("·")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(FoyerTheme.textMuted)
                        Text("PARTIAL — STILL RECORDING")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .tracking(1.4)
                            .foregroundStyle(FoyerTheme.terracotta)
                    }
                }
            }
            Spacer(minLength: 0)
            statusChip(for: s)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func statusChip(for s: SessionSummary) -> some View {
        if s.isLive {
            StatusPill(text: "LIVE", tone: .live, pulsing: true)
        } else {
            switch s.status {
            case "ready":      StatusPill(text: "Ready",      tone: .sage)
            case "processing": StatusPill(text: "Processing", tone: .gold, pulsing: true)
            case "error":      StatusPill(text: "Error",      tone: .live)
            default:
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FoyerTheme.textMuted)
            }
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
        var live: [SessionSummary] = []
        var today: [SessionSummary] = []
        var thisWeek: [SessionSummary] = []
        var older: [SessionSummary] = []
    }
    private func bucketSessions() -> Buckets {
        let cal = Calendar.current
        var b = Buckets()
        for s in store.pastSessions where s.kind != "manual" {
            // Still-recording sessions get pinned to the top under their
            // own "In progress" header so the agent isn't hunting for a
            // partial-data row mixed in with finished open houses.
            if s.isLive { b.live.append(s); continue }
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

// MARK: – Local recordings recovery picker

// Sheet driven by the Home "Recordings on this device" banner. Lists every
// chunks folder under Documents/Recordings/ that isn't the live one, with
// size + date so the agent can identify the right one and re-upload. Each
// row's Upload button calls SessionStore.uploadLocalRecording, which adopts
// the chunks and routes a full-depth tick through the standard processing
// flow → Summary view. Also reused by SummaryView's "Finalize from device
// audio" rescue path when no InFlightRecording auto-resolves the folder.
struct LocalRecordingsPickerSheet: View {
    let recordings: [SessionStore.LocalRecordingInfo]
    var onPick: (SessionStore.LocalRecordingInfo) -> Void
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                FoyerTheme.bgDeep.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Pick a recording to upload. Each one is the raw audio captured on this device — the most recent is at the top.")
                            .font(.system(size: 13))
                            .foregroundStyle(FoyerTheme.creamDim)
                            .lineSpacing(3)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                        ForEach(recordings) { info in
                            row(info)
                                .padding(.horizontal, 20)
                        }
                        if recordings.isEmpty {
                            Text("No local recordings found.")
                                .font(.system(size: 13))
                                .foregroundStyle(FoyerTheme.textDim)
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                        }
                        Spacer().frame(height: 40)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Local recordings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onDismiss)
                        .foregroundStyle(FoyerTheme.gold)
                }
            }
        }
    }

    private func row(_ info: SessionStore.LocalRecordingInfo) -> some View {
        Button { onPick(info) } label: {
            GlassSurface(cornerRadius: 14) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(info.id)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(FoyerTheme.cream)
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            Text(formattedDate(info.modifiedAt))
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .tracking(1.4)
                                .foregroundStyle(FoyerTheme.textMuted)
                            Text("·")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(FoyerTheme.textMuted)
                            Text("\(info.chunkCount) chunks · \(formattedSize(info.totalBytes))".uppercased())
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .tracking(1.4)
                                .foregroundStyle(FoyerTheme.textMuted)
                        }
                    }
                    Spacer(minLength: 0)
                    Text("Upload")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(FoyerTheme.inkOnGold)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(FoyerTheme.gold, in: Capsule())
                }
                .padding(14)
            }
        }
        .buttonStyle(.plain)
    }

    private func formattedDate(_ d: Date?) -> String {
        guard let d else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "MMM d · h:mm a"
        return f.string(from: d).uppercased()
    }

    private func formattedSize(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}

// MARK: – Visitors tab content

struct VisitorsTabContent: View {
    @Environment(AppRouter.self) private var router
    @State private var store = SessionStore.shared
    @State private var addLeadSheet = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    allLeadsCard
                    Spacer().frame(height: 120)
                }
                .padding(.top, 8)
            }
            .background(FoyerTheme.bgDeep)
            .refreshable { await store.refreshSessions() }
            addButton
        }
        .task { await store.refreshSessions() }
        .sheet(isPresented: $addLeadSheet) { AddLeadSheet() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "Database", color: FoyerTheme.gold)
            Text("Leads")
                .foyerDisplay(38)
                .foregroundStyle(FoyerTheme.cream)
        }
        .padding(.horizontal, 20)
        .padding(.top, 56)
        .padding(.bottom, 18)
    }

    // Top-right "NEW" action — mirrors the Sessions tab. Opens the
    // manual-entry sheet for adding a lead the agent didn't record.
    private var addButton: some View {
        Button { addLeadSheet = true } label: {
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

    private var allLeadsCard: some View {
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
                        Text("All leads")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(FoyerTheme.cream)
                        Text("RECORDED + MANUALLY ADDED")
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
    @State private var auth = AuthStore.shared
    @State private var defaultScriptSheet = false
    @State private var fubSheet = false
    @State private var fubConnectedName: String? = nil
    @State private var showSignOutConfirm = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                accountCard
                statsCard
                defaultScriptRow
                kioskRow
                fubRow
                signOutRow
                versionLabel
                Spacer().frame(height: 120)
            }
            .padding(.top, 8)
        }
        .background(FoyerTheme.bgDeep)
        .sheet(isPresented: $defaultScriptSheet) { defaultScriptPicker }
        .sheet(isPresented: $fubSheet) {
            FUBConnectSheet(connectedName: $fubConnectedName)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Sign out of Open House Copilot?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { auth.signOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to sign in with Google again to see your leads.")
        }
        .task {
            await store.refreshScripts()
            // Reflect Keychain state on the Profile row without forcing a
            // network call until the agent taps in.
            if FUBCredential.isConnected, fubConnectedName == nil {
                fubConnectedName = "Connected"
            }
        }
    }

    private var fubRow: some View {
        Button { fubSheet = true } label: {
            settingsRow(
                icon: "arrow.up.right.square",
                label: "Follow Up Boss",
                value: FUBCredential.isConnected ? (fubConnectedName ?? "Connected") : "Not connected"
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private var accountCard: some View {
        GlassSurface(cornerRadius: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(FoyerTheme.goldSoft)
                    Text(initials(for: auth.currentUser?.name))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FoyerTheme.gold)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(auth.currentUser?.name ?? "Signed in")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(FoyerTheme.cream)
                    Text((auth.currentUser?.email ?? "").uppercased())
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(FoyerTheme.textMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    private var signOutRow: some View {
        Button { showSignOutConfirm = true } label: {
            settingsRow(
                icon: "arrow.right.square",
                label: "Sign out",
                value: "End this device's session"
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private func initials(for name: String?) -> String {
        let parts = (name ?? "").split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }
        let s = String(letters).uppercased()
        return s.isEmpty ? "?" : s
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

    // MLS autocomplete state. `suggestions` drives the dropdown; the active
    // `searchTask` is cancelled when the agent types again so we only ever
    // hit the backend once per pause. `selectedListingId` non-nil = the
    // address came from a chosen suggestion (we stop searching to prevent
    // a flicker of stale results).
    @State private var suggestions: [APIClient.MLSSuggestion] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedListingId: String?
    @State private var isFetchingDetail = false

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
            // Address field doubles as the MLS search input. Typing fires
            // debounced /mls/autocomplete; tapping a suggestion auto-fills
            // every other field from the chosen listing. Manual entry still
            // works — just type a custom address and leave the suggestions
            // alone.
            VStack(spacing: 0) {
                textField("Address", text: $address, placeholder: "Search MLS or type an address")
                    .focused($focused)
                    .onChange(of: address) { _, newValue in onAddressChange(newValue) }
                if !suggestions.isEmpty {
                    suggestionsList
                }
            }
            if selectedListingId != nil {
                mlsFilledBadge
            }
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

    private var suggestionsList: some View {
        VStack(spacing: 0) {
            ForEach(suggestions) { s in
                Button { pickSuggestion(s) } label: { suggestionRow(s) }
                    .buttonStyle(.plain)
                if s.id != suggestions.last?.id {
                    Divider().background(FoyerTheme.border)
                }
            }
        }
        .padding(.top, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(FoyerTheme.bgElev)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(FoyerTheme.border, lineWidth: 1)
                )
        )
    }

    private func suggestionRow(_ s: APIClient.MLSSuggestion) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.address ?? "Untitled listing")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(FoyerTheme.cream)
                    .lineLimit(2)
                Text(suggestionSubtitle(s))
                    .font(.system(size: 12))
                    .foregroundStyle(FoyerTheme.textMuted)
            }
            Spacer(minLength: 8)
            if let p = s.list_price {
                Text(formatPrice(p))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FoyerTheme.gold)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var mlsFilledBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 11, weight: .semibold))
            Text("Auto-filled from MLS")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(FoyerTheme.gold)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(FoyerTheme.gold.opacity(0.12))
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func suggestionSubtitle(_ s: APIClient.MLSSuggestion) -> String {
        var bits: [String] = []
        if let beds = s.bedrooms, beds > 0 { bits.append("\(beds) bd") }
        if let baths = s.bathrooms_total, baths > 0 {
            let label = baths.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(baths))" : String(format: "%.1f", baths)
            bits.append("\(label) ba")
        }
        if let sqft = s.living_area, sqft > 0 { bits.append("\(sqft.formatted()) sf") }
        if bits.isEmpty, let city = s.city { return city }
        return bits.joined(separator: " · ")
    }

    private func formatPrice(_ price: Int) -> String {
        if price >= 1_000_000 {
            let m = Double(price) / 1_000_000
            return String(format: "$%.2fM", m).replacingOccurrences(of: ".00M", with: "M")
        }
        return "$\(price.formatted())"
    }

    private func onAddressChange(_ value: String) {
        // Once the agent picks a suggestion, subsequent edits to `address`
        // (or any other field) shouldn't re-fire the search — they're
        // refining the auto-filled record, not searching for a new one.
        if selectedListingId != nil {
            return
        }
        searchTask?.cancel()
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            suggestions = []
            return
        }
        searchTask = Task { @MainActor in
            // Light debounce — fast enough to feel live, slow enough to
            // collapse a burst of keystrokes into one network call.
            try? await Task.sleep(nanoseconds: 220_000_000)
            if Task.isCancelled { return }
            do {
                let results = try await APIClient.shared.mlsAutocomplete(query: trimmed)
                if Task.isCancelled { return }
                self.suggestions = results
            } catch {
                self.suggestions = []
            }
        }
    }

    private func pickSuggestion(_ s: APIClient.MLSSuggestion) {
        searchTask?.cancel()
        suggestions = []
        selectedListingId = s.listing_id
        // Optimistic fill from the autocomplete card so the form snaps
        // into place even before the detail fetch returns.
        if let a = s.address { address = a }
        if let beds = s.bedrooms { self.beds = max(0, beds) }
        if let baths = s.bathrooms_total { self.baths = max(0, baths) }
        if let sqft = s.living_area { self.sqft = String(sqft) }
        if let p = s.list_price { self.price = String(p) }
        if let city = s.city, neighborhood.isEmpty { neighborhood = city }
        focused = false
        isFetchingDetail = true
        Task { @MainActor in
            defer { isFetchingDetail = false }
            do {
                let full = try await APIClient.shared.mlsProperty(listingId: s.listing_id)
                applyFullProperty(full)
            } catch {
                // Optimistic fill already covers the visible fields, so
                // a failed detail fetch isn't user-fatal.
            }
        }
    }

    private func applyFullProperty(_ p: APIClient.MLSProperty) {
        if let a = p.address { address = a }
        if let p2 = p.list_price { price = String(p2) }
        if let b = p.bedrooms { beds = max(0, b) }
        if let b = p.bathrooms_total { baths = max(0, b) }
        if let s = p.living_area { sqft = String(s) }
        // Prefer subdivision (MLS-assigned neighborhood name); fall back to
        // city if the listing is in an unsubdivided area.
        neighborhood = (p.subdivision?.isEmpty == false ? p.subdivision : p.city) ?? neighborhood
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
                    BackBar(crumbs: ["Leads"], onBack: { dismiss() }) {
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
            Text("All leads")
                .foyerDisplay(32)
                .foregroundStyle(FoyerTheme.cream)
            Text("\(rows.count) total · \(openHouseCount) open houses".uppercased())
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(FoyerTheme.textMuted)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    // Recorded sessions only — manual leads aren't open houses, so they
    // shouldn't inflate that count in the inbox header.
    private var openHouseCount: Int {
        SessionStore.shared.pastSessions.filter { $0.kind != "manual" }.count
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

// MARK: – Follow Up Boss connect sheet

// Standalone sheet for pasting (or clearing) an FUB API key. Tests the key
// against /identity before saving so the agent gets immediate feedback if
// they pasted the wrong thing. The key never leaves the device except to
// FUB itself — stored in Keychain via FUBCredential.
struct FUBConnectSheet: View {
    @Binding var connectedName: String?
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey: String = ""
    @State private var testing = false
    @State private var testError: String?
    @State private var alreadyConnected: Bool = FUBCredential.isConnected

    var body: some View {
        NavigationStack {
            ZStack {
                FoyerTheme.bgDeep.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        intro
                        if alreadyConnected {
                            connectedCard
                        } else {
                            keyField
                            connectButton
                        }
                        if let err = testError {
                            errorCard(err)
                        }
                        howToFind
                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Follow Up Boss")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "CRM integration", color: FoyerTheme.gold)
            Text("Push captured leads automatically")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(FoyerTheme.cream)
            Text("When you Send a follow-up draft, Open House Copilot creates the contact in FUB, attaches the session notes, and schedules a follow-up task.")
                .font(.system(size: 13))
                .foregroundStyle(FoyerTheme.creamDim)
                .lineSpacing(3)
                .padding(.top, 4)
        }
        .padding(.top, 6)
    }

    private var keyField: some View {
        GlassSurface(cornerRadius: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: "API key", color: FoyerTheme.gold)
                SecureField(
                    "",
                    text: $apiKey,
                    prompt: Text("Paste from FUB → Settings → API").foregroundStyle(FoyerTheme.textMuted.opacity(0.7))
                )
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(FoyerTheme.cream)
                .tint(FoyerTheme.gold)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private var connectButton: some View {
        Button(action: testAndSave) {
            HStack(spacing: 8) {
                if testing { ProgressView().tint(FoyerTheme.inkOnGold).scaleEffect(0.8) }
                Text(testing ? "Connecting…" : "Test & connect")
            }
        }
        .buttonStyle(FoyerPrimaryButton())
        .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty || testing)
        .opacity(apiKey.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
    }

    private var connectedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassSurface(cornerRadius: 12, strong: true) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(FoyerTheme.sage)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connected")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(FoyerTheme.cream)
                        Text(connectedName ?? "Sending leads to your FUB account.")
                            .font(.system(size: 12))
                            .foregroundStyle(FoyerTheme.creamDim)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(role: .destructive, action: disconnect) {
                Text("Disconnect")
            }
            .buttonStyle(FoyerGhostButton())
        }
    }

    private func errorCard(_ msg: String) -> some View {
        GlassSurface(cornerRadius: 12) {
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
    }

    private var howToFind: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "Where do I find this?")
            Text("In Follow Up Boss, click your profile → Settings → API. Create or copy a key with read + write access. The key stays in this device's Keychain — it never goes to our servers.")
                .font(.system(size: 12))
                .foregroundStyle(FoyerTheme.textDim)
                .lineSpacing(3)
        }
        .padding(.top, 6)
    }

    private func testAndSave() {
        let key = apiKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        testing = true
        testError = nil
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
                    testError = "That key didn't work: \(error.localizedDescription)"
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

// MARK: – Add Lead sheet (manual entry)

// Sheet form for capturing a lead the agent didn't record — someone they
// chatted with at the door, met after the open house ended, got a referral
// for, etc. Creates a kind="manual" session on the backend with a single
// visitor and a templated follow-up draft the agent can edit before sending.
struct AddLeadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @State private var store = SessionStore.shared

    @State private var name: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var tag: String = "Buyer"
    @State private var address: String = ""
    @State private var saving = false
    @State private var saveError: String?
    @FocusState private var focused: Bool

    private let tagOptions = ["Buyer", "Seller", "Browser"]

    var body: some View {
        NavigationStack {
            ZStack {
                FoyerTheme.bgDeep.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        intro
                        field("Name", text: $name, placeholder: "Jane Marchetti", contentType: .name)
                            .focused($focused)
                        field("Email", text: $email, placeholder: "jane@example.com", contentType: .emailAddress, keyboard: .emailAddress)
                        field("Phone", text: $phone, placeholder: "555-0123", contentType: .telephoneNumber, keyboard: .phonePad)
                        tagPicker
                        listingPicker
                        if let err = saveError { errorCard(err) }
                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Add lead")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(FoyerTheme.creamDim)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Text(saving ? "Saving…" : "Save") }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { focused = true }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "Manual entry", color: FoyerTheme.gold)
            Text("Someone you talked to but didn't record")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(FoyerTheme.cream)
            Text("They'll land in your Needs action queue with a starter follow-up draft you can edit before sending.")
                .font(.system(size: 12))
                .foregroundStyle(FoyerTheme.creamDim)
                .lineSpacing(3)
                .padding(.top, 2)
        }
        .padding(.top, 6)
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String, contentType: UITextContentType, keyboard: UIKeyboardType = .default) -> some View {
        GlassSurface(cornerRadius: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: label, color: FoyerTheme.gold)
                TextField("",
                          text: text,
                          prompt: Text(placeholder).foregroundStyle(FoyerTheme.textMuted.opacity(0.7)))
                    .font(.system(size: 15))
                    .foregroundStyle(FoyerTheme.cream)
                    .tint(FoyerTheme.gold)
                    .textContentType(contentType)
                    .keyboardType(keyboard)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private var tagPicker: some View {
        GlassSurface(cornerRadius: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Tag", color: FoyerTheme.gold)
                HStack(spacing: 6) {
                    ForEach(tagOptions, id: \.self) { opt in
                        Button { tag = opt } label: {
                            Text(opt)
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .foregroundStyle(tag == opt ? FoyerTheme.inkOnGold : FoyerTheme.cream)
                                .background(tag == opt ? FoyerTheme.gold : FoyerTheme.bgElev, in: Capsule())
                                .overlay(Capsule().stroke(tag == opt ? Color.clear : FoyerTheme.border, lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private var listingPicker: some View {
        let suggestions = store.listings.prefix(4).map { $0.address }
        GlassSurface(cornerRadius: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Address (optional)", color: FoyerTheme.gold)
                TextField("",
                          text: $address,
                          prompt: Text("1936 17th Ave NE").foregroundStyle(FoyerTheme.textMuted.opacity(0.7)))
                    .font(.system(size: 15))
                    .foregroundStyle(FoyerTheme.cream)
                    .tint(FoyerTheme.gold)
                    .autocorrectionDisabled()
                if !suggestions.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(suggestions, id: \.self) { addr in
                            Button { address = addr } label: {
                                Text(addr)
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .foregroundStyle(FoyerTheme.gold)
                                    .background(FoyerTheme.goldSoft, in: Capsule())
                                    .overlay(Capsule().stroke(FoyerTheme.gold.opacity(0.4), lineWidth: 0.5))
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private func errorCard(_ msg: String) -> some View {
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
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        saving = true
        saveError = nil
        let trimmedAddress = address.trimmingCharacters(in: .whitespaces)
        Task {
            do {
                let newSession = try await APIClient.shared.createManualLead(
                    name: trimmedName,
                    email: email.trimmingCharacters(in: .whitespaces),
                    phone: phone.trimmingCharacters(in: .whitespaces),
                    tag: tag,
                    address: trimmedAddress.isEmpty ? nil : trimmedAddress
                )
                await store.refreshSessions()
                await MainActor.run {
                    saving = false
                    // Land the agent on the new lead's follow-up draft —
                    // they came here to add a lead, the natural next step is
                    // editing the email. Solves the "I added a lead but
                    // didn't see it" UX gap by making the result visible
                    // immediately instead of hiding it in an inbox tap-away.
                    if let visitor = newSession.result?.visitors.first {
                        store.session = newSession
                        router.push(.followup(visitor))
                    }
                    dismiss()
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
