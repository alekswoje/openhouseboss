import SwiftUI

// Drafted follow-up — v2 editorial. Breadcrumb back row, italic gold title
// flourish, glass cards for To / Subject / Body, ghost + gold CTAs.
struct FollowupView: View {
    let visitor: VisitorResult
    @Environment(AppRouter.self) private var router
    @State private var store = SessionStore.shared
    @State private var draft: String
    @State private var leadState: LeadState
    @State private var sending = false
    @State private var sendError: String?

    private var sent: Bool { leadState.status == .sent || leadState.status == .replied }

    init(visitor: VisitorResult) {
        self.visitor = visitor
        self._draft = State(initialValue: visitor.analysis.followUpDraft)
        self._leadState = State(initialValue: visitor.leadState ?? .defaultDrafted)
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
        VStack(spacing: 8) {
            if let err = sendError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(FoyerTheme.terracotta)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 10) {
                Button {} label: { Text("Schedule") }
                    .buttonStyle(FoyerGhostButton())
                    .frame(maxWidth: .infinity)
                Button(action: sendNow) {
                    HStack(spacing: 8) {
                        if sending {
                            ProgressView().tint(FoyerTheme.inkOnGold).scaleEffect(0.8)
                        } else {
                            Image(systemName: sent ? "checkmark" : "paperplane.fill")
                                .font(.system(size: 12))
                        }
                        Text(sent ? "Sent" : (sending ? "Sending…" : "Send now"))
                    }
                }
                .buttonStyle(FoyerPrimaryButton())
                .frame(maxWidth: .infinity)
                .disabled(visitor.visitor.email.isEmpty || sent || sending)
                .opacity((visitor.visitor.email.isEmpty || sent || sending) ? 0.5 : 1)
            }
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
        // Real send is Phase 2 (mailto:). Phase 1: persist the agent's
        // "I've handled this lead" intent so it leaves the needs-action
        // queue in the inbox. The toast still fires for confirmation.
        guard let sessionId = store.session?.id else {
            sendError = "Session not loaded — pull to refresh and try again."
            return
        }
        sendError = nil
        sending = true
        let previous = leadState
        leadState.status = .sent
        Task {
            do {
                let updated = try await APIClient.shared.updateLeadState(
                    sessionId: sessionId,
                    visitorName: visitor.visitor.name,
                    visitorSpeaker: visitor.visitor.speaker,
                    status: .sent
                )
                await MainActor.run {
                    leadState = updated
                    sending = false
                }
                try? await Task.sleep(for: .seconds(1.2))
                await MainActor.run {
                    withAnimation { router.pop() }
                }
            } catch {
                await MainActor.run {
                    leadState = previous
                    sending = false
                    sendError = error.localizedDescription
                }
            }
        }
    }
}
