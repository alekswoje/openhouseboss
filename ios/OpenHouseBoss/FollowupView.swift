import SwiftUI

// Drafted follow-up — shows the real `follow_up_draft` returned from the
// backend analysis, editable inline. Send simulates sending (Mail.app / API
// wire-up is out of scope for the first cut).
struct FollowupView: View {
    let visitor: VisitorResult
    @State private var draft: String
    @State private var sent = false
    @Environment(\.dismiss) private var dismiss

    init(visitor: VisitorResult) {
        self.visitor = visitor
        self._draft = State(initialValue: visitor.analysis.followUpDraft)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            FoyerTheme.bgDeep.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    backRow
                    title
                    toCard
                    subjectCard
                    bodyEditor
                    Spacer().frame(height: 130)
                }
            }

            actionsBar
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) {
            if sent { sentToast.padding(.top, 60) }
        }
    }

    private var backRow: some View {
        Button { dismiss() } label: {
            Text("← \(visitor.visitor.name)")
                .font(.system(size: 11, design: .monospaced)).tracking(1.4)
                .foregroundStyle(FoyerTheme.gold)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Drafted follow-up").foyerDisplay(26).foregroundStyle(FoyerTheme.cream)
            Text("WRITTEN IN YOUR VOICE · \(visitor.analysis.followUpDraft.split(separator: " ").count) WORDS")
                .font(.system(size: 10, design: .monospaced)).tracking(1.4)
                .foregroundStyle(FoyerTheme.textMuted)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private var toCard: some View {
        labeledCard(label: "To", value: visitor.visitor.email.isEmpty
                    ? "\(visitor.visitor.name) — no email captured"
                    : "\(visitor.visitor.name) · \(visitor.visitor.email)")
            .padding(.top, 18)
    }

    private var subjectCard: some View {
        labeledCard(label: "Subject", value: "Great meeting you at the open house")
            .padding(.top, 12)
    }

    private func labeledCard(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: label)
            Text(value).font(.system(size: 13)).foregroundStyle(FoyerTheme.cream)
        }
        .padding(14)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(FoyerTheme.hairline, lineWidth: 0.5))
        .padding(.horizontal, 20)
    }

    private var bodyEditor: some View {
        TextEditor(text: $draft)
            .font(.system(size: 13.5))
            .scrollContentBackground(.hidden)
            .foregroundStyle(FoyerTheme.creamDim)
            .lineSpacing(4)
            .padding(12)
            .frame(minHeight: 280)
            .background(FoyerTheme.goldSoft.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(FoyerTheme.borderStrong, lineWidth: 1))
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
                    Image(systemName: "paperplane.fill")
                    Text("Send now")
                }
            }
            .buttonStyle(FoyerPrimaryButton())
            .disabled(visitor.visitor.email.isEmpty || sent)
            .opacity((visitor.visitor.email.isEmpty || sent) ? 0.5 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 36)
    }

    private var sentToast: some View {
        HStack(spacing: 10) {
            Circle().fill(FoyerTheme.sage).frame(width: 8, height: 8)
                .shadow(color: FoyerTheme.sage, radius: 4)
            Text("Sent to \(visitor.visitor.name)")
                .font(.system(size: 11, design: .monospaced)).tracking(1.4)
                .foregroundStyle(FoyerTheme.cream)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(FoyerTheme.borderStrong, lineWidth: 1))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func sendNow() {
        withAnimation { sent = true }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { dismiss() }
        }
    }
}
