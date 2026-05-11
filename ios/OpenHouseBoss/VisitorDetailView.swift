import SwiftUI

// Visitor detail — v2 editorial. Breadcrumb back row, large serif name +
// italic gold accents, signal chips in brass, glass cards for transcript
// snippets, gold + ghost CTAs at the bottom.
struct VisitorDetailView: View {
    let visitor: VisitorResult
    @Environment(AppRouter.self) private var router
    @State private var store = SessionStore.shared
    @State private var leadState: LeadState
    @State private var stateError: String?

    init(visitor: VisitorResult) {
        self.visitor = visitor
        self._leadState = State(initialValue: visitor.leadState ?? .defaultDrafted)
    }

    private var v: VisitorInfo { visitor.visitor }
    private var a: AnalysisResult { visitor.analysis }

    var body: some View {
        ZStack(alignment: .bottom) {
            FoyerTheme.bgDeep.ignoresSafeArea()
            WarmBg(tone: .gold)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    BackBar(crumbs: ["Session", v.name], onBack: { router.pop() }) {
                        if let kind = TagPill.Kind(a.tagToken) {
                            TagPill(kind: kind, text: "\(a.score)")
                        }
                    }
                    nameBlock
                    leadStateRow
                    signalsSection
                    summarySection
                    reasonSection
                    Spacer().frame(height: 160)
                }
                .padding(.top, 8)
            }

            actionsBar
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // Inline state chip + menu — the agent's main control surface for moving
    // a lead through the inbox. Tap opens the action menu; the chip itself
    // doubles as a status indicator so they don't have to remember whether
    // they already sent.
    private var leadStateRow: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(LeadState.Status.allCases, id: \.self) { s in
                    Button {
                        applyStatus(s)
                    } label: {
                        Label(statusLabel(s), systemImage: leadState.status == s ? "checkmark" : "")
                    }
                }
                Divider()
                Button { snooze(days: 1) } label: { Label("Snooze · tomorrow", systemImage: "clock") }
                Button { snooze(days: 3) } label: { Label("Snooze · 3 days", systemImage: "clock") }
                Button { snooze(days: 7) } label: { Label("Snooze · 1 week", systemImage: "clock") }
                if leadState.snoozedUntil != nil {
                    Button { clearSnooze() } label: { Label("Clear snooze", systemImage: "alarm.slash") }
                }
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusTone(leadState.status))
                        .frame(width: 6, height: 6)
                    Text(currentStateLabel.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(FoyerTheme.cream)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(FoyerTheme.textMuted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(FoyerTheme.bgElev, in: Capsule())
                .overlay(Capsule().stroke(FoyerTheme.border, lineWidth: 0.5))
            }
            if let err = stateError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(FoyerTheme.terracotta)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private var currentStateLabel: String {
        if leadState.isSnoozedNow, let d = leadState.snoozedUntilDate {
            return "Snoozed · \(VisitorDetailView.snoozeFmt.string(from: d))"
        }
        return statusLabel(leadState.status)
    }

    private func statusLabel(_ s: LeadState.Status) -> String {
        switch s {
        case .drafted:  return "Drafted"
        case .sent:     return "Sent"
        case .replied:  return "Replied"
        case .archived: return "Archived"
        }
    }

    private func statusTone(_ s: LeadState.Status) -> Color {
        switch s {
        case .drafted:  return FoyerTheme.gold
        case .sent:     return FoyerTheme.sage
        case .replied:  return FoyerTheme.sage
        case .archived: return FoyerTheme.textMuted
        }
    }

    private static let snoozeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private func applyStatus(_ s: LeadState.Status) {
        guard s != leadState.status else { return }
        patch(status: s)
    }

    private func snooze(days: Int) {
        let date = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        patch(status: leadState.status == .drafted ? .sent : leadState.status,
              snoozedUntil: ISO8601DateFormatter.fractionalSeconds.string(from: date))
    }

    private func clearSnooze() {
        patch(status: leadState.status, snoozedUntil: nil)
    }

    private func patch(status: LeadState.Status, snoozedUntil: String?? = .none) {
        guard let sessionId = store.session?.id else {
            stateError = "Session not loaded — pull to refresh."
            return
        }
        stateError = nil
        let previous = leadState
        leadState.status = status
        if case .some(let val) = snoozedUntil { leadState.snoozedUntil = val }
        Task {
            do {
                let updated = try await APIClient.shared.updateLeadState(
                    sessionId: sessionId,
                    visitorName: v.name,
                    visitorSpeaker: v.speaker,
                    status: status,
                    snoozedUntil: snoozedUntil
                )
                await MainActor.run { leadState = updated }
            } catch {
                await MainActor.run {
                    leadState = previous
                    stateError = error.localizedDescription
                }
            }
        }
    }

    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            let parts = v.name.split(separator: " ", maxSplits: 1).map(String.init)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if parts.count == 2 {
                    Text(parts[0] + " ")
                        .foyerDisplay(32)
                        .foregroundStyle(FoyerTheme.cream)
                    Text(parts[1])
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(FoyerTheme.gold)
                } else {
                    Text(v.name)
                        .foyerDisplay(32)
                        .foregroundStyle(FoyerTheme.cream)
                }
            }
            Text("\(a.tag.uppercased()) · SPOKE \(a.wordsSpoken) WORDS")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(FoyerTheme.textMuted)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var signalsSection: some View {
        Group {
            if !a.signals.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow(text: "Signals")
                    FlowLayout(spacing: 6) {
                        ForEach(a.signals, id: \.self) { s in
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 9))
                                Text(s)
                                    .font(.system(size: 11))
                            }
                            .foregroundStyle(FoyerTheme.gold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(FoyerTheme.goldSoft, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(FoyerTheme.gold.opacity(0.30), lineWidth: 0.5)
                            )
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
            }
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Summary")
            Text(a.summary)
                .font(.system(size: 13))
                .foregroundStyle(FoyerTheme.creamDim)
                .lineSpacing(4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
    }

    private var reasonSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Why \(a.tag)")
            Text(a.tagReason)
                .font(.system(size: 12))
                .foregroundStyle(FoyerTheme.textDim)
                .lineSpacing(3)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private var actionsBar: some View {
        HStack(spacing: 10) {
            Button {} label: {
                HStack(spacing: 8) {
                    Image(systemName: "phone.fill").font(.system(size: 12))
                    Text("Call")
                }
            }
            .buttonStyle(FoyerGhostButton())
            .frame(maxWidth: .infinity)

            Button { router.push(.followup(visitor)) } label: {
                Text("Review follow-up →")
            }
            .buttonStyle(FoyerPrimaryButton())
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 36)
    }
}

#Preview {
    NavigationStack {
        VisitorDetailView(visitor: VisitorResult(
            visitor: VisitorInfo(name: "Sarah Chen", email: "", phone: "", speaker: "B"),
            analysis: AnalysisResult(
                summary: "Sample summary.",
                tag: "Buyer",
                tagReason: "Mentioned pre-approval.",
                score: 94,
                signals: ["Pre-approved $1.4M", "Close in 60 days"],
                followUpDraft: "Hi Sarah, …",
                wordsSpoken: 142
            ),
            leadState: nil
        ))
    }
}
