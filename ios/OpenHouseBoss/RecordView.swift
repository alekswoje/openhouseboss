import SwiftUI

// Pre-session setup — breadcrumb back, address field, expected-guests
// picker (drives AssemblyAI diarization), capture sources, gold CTA.
struct SetupView: View {
    @Environment(AppRouter.self) private var router
    @State private var store = SessionStore.shared
    @State private var address: String = ""
    @State private var scriptId: String? = nil
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            FoyerTheme.bgDeep.ignoresSafeArea()
            WarmBg(tone: .gold)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    BackBar(crumbs: ["Sessions", "New open house"], onBack: { router.pop() }) {
                        StatusPill(text: "Draft", tone: .gold)
                    }
                    title
                    propertyCard
                    scriptPicker
                    sourcesSection
                    Spacer().frame(height: 200)
                }
                .padding(.top, 8)
            }

            beginButton
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { focused = true }
        .task { await store.refreshScripts() }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Where are you")
                .foyerDisplay(32)
                .foregroundStyle(FoyerTheme.cream)
            HStack(spacing: 0) {
                Text("hosting ")
                    .foyerDisplay(32)
                    .foregroundStyle(FoyerTheme.cream)
                Text("today?")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(FoyerTheme.gold)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    private var propertyCard: some View {
        GlassSurface(cornerRadius: 20, strong: true) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Eyebrow(text: "Property", color: FoyerTheme.gold)
                    Spacer()
                    Text("Optional")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(FoyerTheme.textMuted)
                }
                TextField("", text: $address,
                          prompt: Text("412 W 78th · Apt 4-A").foregroundStyle(FoyerTheme.textMuted.opacity(0.7)))
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(FoyerTheme.cream)
                    .tint(FoyerTheme.gold)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($focused)
                Rectangle().fill(FoyerTheme.borderStrong).frame(height: 0.5)
                Text("Used to label this session in your history.")
                    .font(.system(size: 12))
                    .foregroundStyle(FoyerTheme.textDim)
            }
            .padding(18)
        }
        .padding(.horizontal, 20)
    }

    // Script picker — agents attach a script and we'll grade their actual
    // conversation against it after the session. "None" leaves coverage off.
    private var scriptPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow(text: "Script (optional)", color: FoyerTheme.gold)
                Spacer()
                Text("COACHING AFTER RECORDING")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(FoyerTheme.textMuted)
            }
            scriptRow(id: nil, name: "No script", subtitle: "SKIP COVERAGE GRADING")
            ForEach(store.availableScripts) { s in
                scriptRow(id: s.id, name: s.name, subtitle: "\(s.stepCount) STEPS · \(s.description.uppercased())")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
    }

    private func scriptRow(id: String?, name: String, subtitle: String) -> some View {
        let active = scriptId == id
        return Button { scriptId = id } label: {
            GlassSurface(cornerRadius: 12, strong: active) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(active ? FoyerTheme.gold : FoyerTheme.borderStrong, lineWidth: 1)
                        if active {
                            Circle()
                                .fill(FoyerTheme.gold)
                                .frame(width: 10, height: 10)
                        }
                    }
                    .frame(width: 18, height: 18)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name)
                            .font(.system(size: 14, weight: active ? .semibold : .medium))
                            .foregroundStyle(active ? FoyerTheme.gold : FoyerTheme.cream)
                        Text(subtitle)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .tracking(1.4)
                            .foregroundStyle(FoyerTheme.textMuted)
                            .lineLimit(2)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(active ? FoyerTheme.gold.opacity(0.4) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Capture sources")
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 4)
            GlassSurface(cornerRadius: 14) {
                HStack(spacing: 12) {
                    iconBadge(systemName: "mic.fill")
                    VStack(alignment: .leading, spacing: 3) {
                        Text("iPhone microphone")
                            .font(.system(size: 13))
                            .foregroundStyle(FoyerTheme.cream)
                        Text("KEEPS RUNNING IF YOU LOCK THE PHONE")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .tracking(1.4)
                            .foregroundStyle(FoyerTheme.textMuted)
                    }
                    Spacer()
                    StatusPill(text: "On", tone: .sage)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .padding(.horizontal, 20)

            helperRow("01", "Begin recording — phone can stay in your pocket or lock screen.")
            helperRow("02", "Talk naturally with each guest who walks in.")
            helperRow("03", "End session — we transcribe, identify each guest, and draft a follow-up.")
        }
    }

    private func iconBadge(systemName: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(FoyerTheme.goldSoft)
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(FoyerTheme.gold)
        }
        .frame(width: 30, height: 30)
    }

    private func helperRow(_ num: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(num)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(FoyerTheme.gold)
                .frame(width: 24, alignment: .leading)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(FoyerTheme.cream)
                .lineSpacing(2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Hairline().padding(.horizontal, 20) }
    }

    private var beginButton: some View {
        VStack(spacing: 10) {
            Button {
                let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
                SessionStore.shared.pendingAddress = trimmed.isEmpty ? nil : trimmed
                // No guest-count hint up front — open-house traffic is
                // unpredictable. If diarization undercounts, re-run from the
                // Summary screen with a corrected count.
                SessionStore.shared.pendingSpeakersExpected = nil
                SessionStore.shared.pendingScriptId = scriptId
                router.push(.live)
            } label: {
                HStack(spacing: 10) {
                    Circle().fill(FoyerTheme.inkOnGold).frame(width: 10, height: 10)
                    Text("Begin recording")
                }
            }
            .buttonStyle(FoyerPrimaryButton())

            Text("RECORDINGS SAVED TO FILES APP · OPENHOUSEBOSS / RECORDINGS")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(FoyerTheme.textMuted)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 36)
    }
}

// Flow layout — wraps children left-to-right onto multiple lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let result = arrange(subviews: subviews, width: width)
        return CGSize(width: width, height: result.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placements = arrange(subviews: subviews, width: bounds.width).placements
        for (i, p) in placements.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> (height: CGFloat, placements: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        var placements: [CGPoint] = []
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            placements.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (y + rowHeight, placements)
    }
}
