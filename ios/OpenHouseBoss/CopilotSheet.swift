import SwiftUI

// MARK: – Copilot — global "ask anything" agent
//
// Surfaced as a floating pill from the home screen + side rail. Each turn
// streams the full chat history to /agent/chat, which runs Claude with a
// tool-use loop over the user's sessions/leads/stats and returns either a
// plain-text answer or text + a navigation action.
//
// Two visible types:
//   - `CopilotLauncher` — the always-visible "Ask" pill the agent taps to
//     open the sheet. Used from IPadHome (hero card variant) and from a
//     floating-FAB overlay on every other screen.
//   - `CopilotSheet` — the chat surface itself. Stateless wrapper over
//     the [CopilotTurn] history; on an action, dismisses and forwards to
//     the parent's `onAction` so the parent (IPadAgentApp) can navigate.

struct CopilotAction: Hashable {
    let target: String        // matches APIClient.CopilotAction.target
    let sessionId: String?
    let name: String?
    let speaker: String?
}

// MARK: – Hero entry on Home

// Big tap target at the top of IPadHome. Looks like a search bar / Spotlight
// pill, gold accent on the leading icon so the user knows this is THE thing
// to tap when they want to do something.
struct CopilotHeroCard: View {
    var onTap: () -> Void

    @Environment(\.horizontalSizeClass) private var hSize
    private var isCompact: Bool { hSize == .compact }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(FoyerTheme.goldSoft)
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(FoyerTheme.gold)
                }
                .frame(width: isCompact ? 38 : 44, height: isCompact ? 38 : 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask Copilot")
                        .font(.system(size: isCompact ? 15 : 16, weight: .semibold))
                        .foregroundStyle(FoyerTheme.cream)
                    Text("Show me last Sunday's open house · Draft a follow-up · How am I doing this month")
                        .font(.system(size: isCompact ? 11 : 12))
                        .foregroundStyle(FoyerTheme.textDim)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FoyerTheme.gold)
            }
            .padding(.horizontal, isCompact ? 14 : 18)
            .padding(.vertical, isCompact ? 12 : 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: isCompact ? 16 : 18, style: .continuous)
                    .fill(FoyerTheme.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: isCompact ? 16 : 18, style: .continuous)
                    .stroke(FoyerTheme.gold.opacity(0.30), lineWidth: 1)
            )
            .shadow(color: FoyerTheme.gold.opacity(0.18), radius: 14, y: 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: – Floating "Ask" FAB shown on every screen but Home

// Smaller, persistent affordance for the moments the agent thinks of
// something while looking at a session detail or the leads inbox. Sits
// above the LiveSessionBar / tab bar in the safe area.
struct CopilotFloatingPill: View {
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                Text("Ask")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(FoyerTheme.inkOnGold)
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(Capsule().fill(FoyerTheme.gold))
            .shadow(color: FoyerTheme.gold.opacity(0.40), radius: 14, y: 4)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: – Sheet (chat thread)

struct CopilotSheet: View {
    var onDismiss: () -> Void
    // Fires when the user taps "Open …" on an assistant turn that carries
    // an action. The parent IPadAgentApp interprets the target + ids and
    // routes (set tab, viewingPastSession, etc.).
    var onAction: (CopilotAction) -> Void

    @State private var turns: [APIClient.CopilotTurn] = []
    // toolCalls / action are keyed by message position (index into turns).
    // We track them in parallel arrays instead of muddling them into the
    // CopilotTurn struct so the wire payload stays plain {role, text}.
    @State private var assistantExtras: [Int: AssistantExtras] = [:]
    @State private var input: String = ""
    @State private var loading: Bool = false
    @State private var errorMessage: String?
    @FocusState private var inputFocused: Bool

    private struct AssistantExtras {
        var toolCalls: [APIClient.CopilotToolCall] = []
        var action: APIClient.CopilotAction?
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                conversation
                composer
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Copilot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onDismiss)
                        .foregroundStyle(FoyerTheme.creamDim)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { inputFocused = true }
    }

    // MARK: – Conversation

    @ViewBuilder
    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if turns.isEmpty {
                        suggestions
                    }
                    ForEach(Array(turns.enumerated()), id: \.offset) { idx, t in
                        messageView(index: idx, turn: t)
                            .id(idx)
                    }
                    if loading {
                        thinkingView
                            .id("thinking")
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(FoyerTheme.terracotta)
                            .padding(.horizontal, 18)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .onChange(of: turns.count) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(turns.count - 1, anchor: .bottom)
                }
            }
            .onChange(of: loading) { _, isLoading in
                if isLoading {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo("thinking", anchor: .bottom)
                    }
                }
            }
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FoyerTheme.gold)
                Text("TRY ASKING")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(FoyerTheme.textDim)
            }
            .padding(.top, 8)
            ForEach(starterPrompts, id: \.self) { prompt in
                Button {
                    input = prompt
                    Task { await send() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(FoyerTheme.gold)
                        Text(prompt)
                            .font(.system(size: 14))
                            .foregroundStyle(FoyerTheme.cream)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(FoyerTheme.bgCard)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 6)
    }

    private let starterPrompts: [String] = [
        "How did my last open house go?",
        "Who are my hottest buyer leads right now?",
        "Show me this month's stats",
        "Draft a follow-up to my most recent visitor",
    ]

    @ViewBuilder
    private func messageView(index: Int, turn: APIClient.CopilotTurn) -> some View {
        if turn.role == "user" {
            HStack {
                Spacer(minLength: 40)
                Text(turn.text)
                    .font(.system(size: 15))
                    .foregroundStyle(FoyerTheme.inkOnGold)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(FoyerTheme.gold, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(turn.text)
                    .font(.system(size: 15))
                    .foregroundStyle(FoyerTheme.cream)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let extras = assistantExtras[index] {
                    if !extras.toolCalls.isEmpty {
                        toolCallChips(extras.toolCalls)
                    }
                    if let action = extras.action {
                        actionButton(action)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(FoyerTheme.bgCard)
            )
        }
    }

    private func toolCallChips(_ calls: [APIClient.CopilotToolCall]) -> some View {
        // Wrapping chip strip — visual hint at what the agent did under the
        // hood. Reads like "Reviewed 12 sessions · Looked up Maple St".
        // FlowLayout lives in RecordView.swift (shared with VisitorDetailView's
        // signal chips); default spacing of 8 is what we want here too.
        FlowLayout(spacing: 6) {
            ForEach(calls) { c in
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                    Text(c.summary)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(FoyerTheme.textDim)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.white.opacity(0.05), in: Capsule())
            }
        }
    }

    private func actionButton(_ action: APIClient.CopilotAction) -> some View {
        Button {
            onAction(CopilotAction(
                target: action.target,
                sessionId: action.sessionId,
                name: action.name,
                speaker: action.speaker
            ))
            onDismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: actionIcon(action.target))
                    .font(.system(size: 13, weight: .semibold))
                Text(actionLabel(action.target))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(FoyerTheme.inkOnGold)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(FoyerTheme.gold, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private func actionLabel(_ target: String) -> String {
        switch target {
        case "session":   return "Open session"
        case "lead":      return "Open lead"
        case "followup":  return "Edit follow-up"
        case "leads":     return "Open Leads inbox"
        case "insights":  return "Open Insights"
        case "record":    return "Start recording"
        case "kiosk":     return "Open Kiosk"
        default:          return "Open"
        }
    }

    private func actionIcon(_ target: String) -> String {
        switch target {
        case "session":   return "house.fill"
        case "lead":      return "person.fill"
        case "followup":  return "envelope.fill"
        case "leads":     return "tray.fill"
        case "insights":  return "chart.bar.fill"
        case "record":    return "waveform.circle.fill"
        case "kiosk":     return "person.badge.plus.fill"
        default:          return "arrow.up.right"
        }
    }

    private var thinkingView: some View {
        HStack(spacing: 10) {
            FoyerLoadingView(size: 28, cornerRadius: 6)
            Text("Thinking…")
                .font(.system(size: 13))
                .foregroundStyle(FoyerTheme.textDim)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(FoyerTheme.bgCard)
        )
    }

    // MARK: – Composer

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ZStack(alignment: .topLeading) {
                if input.isEmpty {
                    Text("Ask anything…")
                        .font(.system(size: 15))
                        .foregroundStyle(FoyerTheme.textMuted)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $input)
                    .font(.system(size: 15))
                    .foregroundStyle(FoyerTheme.cream)
                    .tint(FoyerTheme.gold)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .frame(minHeight: 44, maxHeight: 140)
                    .focused($inputFocused)
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(FoyerTheme.bgCard)
            )

            Button { Task { await send() } } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(canSend ? FoyerTheme.inkOnGold : FoyerTheme.textMuted)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle().fill(canSend ? FoyerTheme.gold : Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .background(
            Rectangle()
                .fill(Color.black)
                .overlay(alignment: .top) {
                    Rectangle().fill(FoyerTheme.hairline).frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !loading
    }

    @MainActor
    private func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !loading else { return }
        input = ""
        errorMessage = nil
        turns.append(APIClient.CopilotTurn(role: "user", text: text))
        loading = true
        defer { loading = false }

        do {
            let reply = try await APIClient.shared.askCopilot(turns: turns)
            let replyTurn = APIClient.CopilotTurn(role: "assistant", text: reply.text)
            turns.append(replyTurn)
            assistantExtras[turns.count - 1] = AssistantExtras(
                toolCalls: reply.toolCalls,
                action: reply.action
            )
        } catch {
            errorMessage = "Copilot couldn't reply: \(error.localizedDescription)"
        }
    }
}

