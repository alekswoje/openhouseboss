import SwiftUI

// Visitor detail — v2 editorial. Breadcrumb back row, large serif name +
// italic gold accents, signal chips in brass, glass cards for transcript
// snippets, gold + ghost CTAs at the bottom.
struct VisitorDetailView: View {
    let visitor: VisitorResult
    @Environment(AppRouter.self) private var router

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
            )
        ))
    }
}
