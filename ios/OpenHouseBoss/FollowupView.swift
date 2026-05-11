import SwiftUI

// Drafted follow-up — v2 editorial. Breadcrumb back row, italic gold title
// flourish, glass cards for To / Subject / Body, ghost + gold CTAs.
struct FollowupView: View {
    let visitor: VisitorResult
    @Environment(AppRouter.self) private var router
    @State private var draft: String
    @State private var sent = false

    init(visitor: VisitorResult) {
        self.visitor = visitor
        self._draft = State(initialValue: visitor.analysis.followUpDraft)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            FoyerTheme.bgDeep.ignoresSafeArea()
            WarmBg(tone: .gold)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    BackBar(crumbs: [visitor.visitor.name, "Follow-up"], onBack: { router.pop() }) {
                        StatusPill(text: "Draft · \(wordCount)w", tone: .gold)
                    }
                    title
                    toCard
                    subjectCard
                    bodyEditor
                    Spacer().frame(height: 140)
                }
                .padding(.top, 8)
            }

            actionsBar
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) {
            if sent { sentToast.padding(.top, 60) }
        }
    }

    private var wordCount: Int {
        draft.split(separator: " ").count
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "Written in your voice", color: FoyerTheme.gold)
            HStack(spacing: 0) {
                Text("Drafted ")
                    .foyerDisplay(28)
                    .foregroundStyle(FoyerTheme.cream)
                Text("follow-up")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(FoyerTheme.gold)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var toCard: some View {
        labeledCard(label: "To", value: visitor.visitor.email.isEmpty
                    ? "\(visitor.visitor.name) — no email captured"
                    : "\(visitor.visitor.name) · \(visitor.visitor.email)")
            .padding(.top, 18)
    }

    private var subjectCard: some View {
        labeledCard(label: "Subject", value: "Great meeting you at the open house")
            .padding(.top, 10)
    }

    private func labeledCard(label: String, value: String) -> some View {
        GlassSurface(cornerRadius: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: label, color: FoyerTheme.gold)
                Text(value)
                    .font(.system(size: 13))
                    .foregroundStyle(FoyerTheme.cream)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
    }

    private var bodyEditor: some View {
        GlassSurface(cornerRadius: 16, strong: true) {
            TextEditor(text: $draft)
                .font(.system(size: 13.5))
                .scrollContentBackground(.hidden)
                .foregroundStyle(FoyerTheme.creamDim)
                .lineSpacing(4)
                .padding(12)
                .frame(minHeight: 280)
                .tint(FoyerTheme.gold)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var actionsBar: some View {
        HStack(spacing: 10) {
            Button {} label: { Text("Schedule") }
                .buttonStyle(FoyerGhostButton())
                .frame(maxWidth: .infinity)
            Button(action: sendNow) {
                HStack(spacing: 8) {
                    Image(systemName: "paperplane.fill").font(.system(size: 12))
                    Text("Send now")
                }
            }
            .buttonStyle(FoyerPrimaryButton())
            .frame(maxWidth: .infinity)
            .disabled(visitor.visitor.email.isEmpty || sent)
            .opacity((visitor.visitor.email.isEmpty || sent) ? 0.5 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 36)
    }

    private var sentToast: some View {
        GlassSurface(cornerRadius: 14, strong: true) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(FoyerTheme.gold)
                Text("Sent to \(visitor.visitor.name)")
                    .font(.system(size: 13))
                    .foregroundStyle(FoyerTheme.cream)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .padding(.horizontal, 16)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func sendNow() {
        withAnimation { sent = true }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { router.pop() }
        }
    }
}
