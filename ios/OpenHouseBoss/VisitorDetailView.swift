import SwiftUI

// Single visitor — signals chips + summary + tag + score. Driven by a real
// VisitorResult from the backend analysis.
struct VisitorDetailView: View {
    let visitor: VisitorResult
    @State private var goFollowup = false
    @Environment(\.dismiss) private var dismiss

    private var v: VisitorInfo { visitor.visitor }
    private var a: AnalysisResult { visitor.analysis }

    var body: some View {
        ZStack(alignment: .bottom) {
            FoyerTheme.bgDeep.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    headerRow
                    Text(v.name).foyerDisplay(30).foregroundStyle(FoyerTheme.cream)
                        .padding(.horizontal, 20).padding(.top, 14)
                    Text("\(a.tag.uppercased()) · SPOKE \(a.wordsSpoken) WORDS")
                        .font(.system(size: 10, design: .monospaced)).tracking(1.4)
                        .foregroundStyle(FoyerTheme.textMuted)
                        .padding(.horizontal, 20).padding(.top, 4)

                    signalsSection
                    summarySection
                    reasonSection
                    Spacer().frame(height: 140)
                }
            }

            actionsBar
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $goFollowup) { FollowupView(visitor: visitor) }
    }

    private var headerRow: some View {
        HStack {
            Button { dismiss() } label: {
                Text("← Session")
                    .font(.system(size: 11, design: .monospaced)).tracking(1.4)
                    .foregroundStyle(FoyerTheme.gold)
            }
            Spacer()
            if let kind = TagPill.Kind(a.tagToken) {
                TagPill(kind: kind, text: "\(a.score)")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var signalsSection: some View {
        Group {
            if !a.signals.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: "Signals")
                    FlowLayout(spacing: 6) {
                        ForEach(a.signals, id: \.self) { s in
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles").font(.system(size: 9))
                                Text(s).font(.system(size: 11))
                            }
                            .foregroundStyle(FoyerTheme.gold)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(FoyerTheme.goldSoft, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Summary")
            Text(a.summary)
                .font(.system(size: 13))
                .foregroundStyle(FoyerTheme.cream)
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
                .foregroundStyle(FoyerTheme.creamDim)
                .lineSpacing(3)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private var actionsBar: some View {
        HStack(spacing: 10) {
            Button {} label: { Text("Call") }
                .buttonStyle(FoyerGhostButton())
                .frame(maxWidth: .infinity)
            Button { goFollowup = true } label: { Text("Review follow-up →") }
                .buttonStyle(FoyerPrimaryButton())
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 36)
    }
}

#Preview {
    NavigationStack {
        // Preview-only stub.
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
