import MessageUI
import SwiftUI
import UIKit

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
    @State private var showingMail = false

    private var sent: Bool { leadState.status == .sent || leadState.status == .replied }

    init(visitor: VisitorResult) {
        self.visitor = visitor
        self._draft = State(initialValue: visitor.analysis.followUpDraft)
        self._leadState = State(initialValue: visitor.leadState ?? .defaultDrafted)
    }

    private var emailSubject: String {
        if let addr = store.session?.address, !addr.isEmpty {
            return "Great meeting you at \(addr)"
        }
        return "Great meeting you at the open house"
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
        .sheet(isPresented: $showingMail) {
            MailComposeSheet(
                to: [visitor.visitor.email],
                subject: emailSubject,
                body: draft,
                onResult: handleMailResult
            )
            .ignoresSafeArea()
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

    // Send flow: prefer the in-app Mail compose sheet so we get a delegate
    // callback and only mark the lead "sent" when the agent actually taps
    // Send. If no Mail account is configured, fall back to a mailto: URL —
    // there's no callback in that path, so we mark sent on tap (best effort,
    // the agent can manually flip it back from the detail screen menu).
    private func sendNow() {
        sendError = nil
        if MFMailComposeViewController.canSendMail() {
            showingMail = true
        } else if openMailtoFallback() {
            // No callback from Mail.app — assume they'll send and persist
            // the workflow state so the inbox reflects it.
            markSent(popAfter: false)
        } else {
            sendError = "No mail app available. Set up Mail in iOS Settings, or copy the draft into your client."
        }
    }

    private func handleMailResult(_ result: MFMailComposeResult) {
        switch result {
        case .sent:
            markSent(popAfter: true)
        case .saved:
            // Agent hit "Save Draft" in Mail.app — treat as still drafted
            // here; the email is sitting in their Mail Drafts folder.
            break
        case .cancelled:
            break
        case .failed:
            sendError = "Mail couldn't send the message. Try again or use a different account."
        @unknown default:
            break
        }
    }

    private func markSent(popAfter: Bool) {
        guard let sessionId = store.session?.id else {
            sendError = "Session not loaded — pull to refresh and try again."
            return
        }
        sending = true
        let previous = leadState
        leadState.status = .sent
        let sessionAddress = store.session?.address
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

                // Best-effort push to Follow Up Boss if connected. Failures
                // don't roll back the "sent" flip — the email already went
                // out via Mail.app; the CRM push is bonus. We surface the
                // error inline so the agent knows to retry from the visitor
                // detail menu (eventually) or re-send manually in FUB.
                if FUBCredential.isConnected {
                    do {
                        _ = try await APIClient.shared.fubPushLead(
                            visitor: visitor,
                            sessionAddress: sessionAddress,
                            snoozedUntil: updated.snoozedUntilDate
                        )
                    } catch {
                        await MainActor.run {
                            sendError = "Sent — but FUB push failed: \(error.localizedDescription)"
                        }
                    }
                }

                if popAfter {
                    try? await Task.sleep(for: .seconds(1.2))
                    await MainActor.run { withAnimation { router.pop() } }
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

    // mailto: builder that percent-encodes the body and subject. Used only
    // when MFMailComposeViewController can't send — typically when the user
    // hasn't configured any Mail account in iOS Settings.
    private func openMailtoFallback() -> Bool {
        var comps = URLComponents()
        comps.scheme = "mailto"
        comps.path = visitor.visitor.email
        comps.queryItems = [
            URLQueryItem(name: "subject", value: emailSubject),
            URLQueryItem(name: "body", value: draft),
        ]
        guard let url = comps.url, UIApplication.shared.canOpenURL(url) else { return false }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        return true
    }
}

// MARK: – MFMailComposeViewController wrapper

// Lets SwiftUI present the native Mail compose sheet with a pre-filled
// recipient/subject/body and a callback that fires when the user actually
// taps Send (or Cancel/Save Draft). Falls back to a mailto: URL elsewhere.
struct MailComposeSheet: UIViewControllerRepresentable {
    let to: [String]
    let subject: String
    let body: String
    let onResult: (MFMailComposeResult) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.setToRecipients(to)
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        vc.mailComposeDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onResult: (MFMailComposeResult) -> Void
        init(onResult: @escaping (MFMailComposeResult) -> Void) { self.onResult = onResult }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true) { [onResult] in
                onResult(result)
            }
        }
    }
}
