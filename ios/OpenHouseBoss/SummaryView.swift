import SwiftUI

// Post-session summary — reads from the shared SessionStore. Renders an
// uploading/processing placeholder while the backend works, then swaps to
// real visitor cards backed by the analysis result.
struct SummaryView: View {
    // Pass an id to load a past session; omit to render whatever the store is
    // currently doing (live upload + processing flow).
    var pastSessionId: String? = nil

    @State private var store = SessionStore.shared
    @State private var openVisitor: VisitorResult?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .bottom) {
            FoyerTheme.bgDeep.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    content
                    Spacer().frame(height: 130)
                }
            }

            footerButton
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $openVisitor) { v in VisitorDetailView(visitor: v) }
        .task {
            if let id = pastSessionId {
                store.openPastSession(id: id)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: headerEyebrow)
            Text(headerTitle)
                .foyerDisplay(28).foregroundStyle(FoyerTheme.cream)
            if let sub = headerSubtitle {
                Text(sub).foyerDisplay(28).foregroundStyle(FoyerTheme.cream)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .idle, .uploading, .processing:
            processingCard
        case .failed(let msg):
            errorCard(msg)
        case .ready:
            visitorList
        }
    }

    private var processingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ProgressView()
                    .tint(FoyerTheme.gold)
                    .scaleEffect(0.9)
                Eyebrow(text: phaseLabel)
            }
            Text(phaseDescription)
                .font(.system(size: 13))
                .foregroundStyle(FoyerTheme.textDim)
                .lineSpacing(3)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FoyerTheme.goldSoft, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FoyerTheme.borderStrong, lineWidth: 1))
        .padding(.horizontal, 20)
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Couldn't process session", color: FoyerTheme.terracotta)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(FoyerTheme.cream)
                .lineSpacing(3)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FoyerTheme.terracottaSoft, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FoyerTheme.terracotta, lineWidth: 1))
        .padding(.horizontal, 20)
    }

    private var visitorList: some View {
        let visitors = store.session?.result?.visitors ?? []
        return VStack(spacing: 12) {
            if visitors.isEmpty {
                Text("No visitors detected. The recording might have been too short or only contained the agent's voice.")
                    .font(.system(size: 13))
                    .foregroundStyle(FoyerTheme.textDim)
                    .padding(.horizontal, 4)
            } else {
                ForEach(Array(visitors.enumerated()), id: \.element.id) { idx, v in
                    visitorCard(v, hot: idx == 0)
                        .onTapGesture { openVisitor = v }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private func visitorCard(_ v: VisitorResult, hot: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(v.visitor.name).font(.system(size: 15)).foregroundStyle(FoyerTheme.cream)
                    Text("SPOKE \(v.analysis.wordsSpoken)W · SPEAKER \(v.visitor.speaker ?? "?")")
                        .font(.system(size: 9, design: .monospaced)).tracking(1.4)
                        .foregroundStyle(FoyerTheme.textMuted)
                }
                Spacer()
                if let kind = TagPill.Kind(v.analysis.tagToken) {
                    TagPill(kind: kind, text: "\(v.analysis.score)")
                }
            }
            Text(v.analysis.summary)
                .font(.system(size: 12))
                .foregroundStyle(FoyerTheme.creamDim)
                .lineSpacing(2)
                .padding(.top, 12)
            if hot {
                Hairline().padding(.top, 12)
                HStack {
                    Text(v.analysis.tag.uppercased() + " · " + v.analysis.tagReason)
                        .font(.system(size: 9, design: .monospaced)).tracking(1.0)
                        .foregroundStyle(FoyerTheme.textMuted)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("Review →")
                        .font(.system(size: 12))
                        .foregroundStyle(FoyerTheme.gold)
                }
                .padding(.top, 10)
            }
        }
        .padding(16)
        .background(hot ? FoyerTheme.goldSoft.opacity(0.4) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(hot ? FoyerTheme.borderStrong : FoyerTheme.hairline, lineWidth: hot ? 1 : 0.5)
        )
    }

    @ViewBuilder
    private var footerButton: some View {
        switch store.phase {
        case .ready:
            Button {} label: { Text("Approve all & schedule") }
                .buttonStyle(FoyerPrimaryButton())
                .padding(.horizontal, 20)
                .padding(.bottom, 36)
        case .failed:
            Button { dismiss() } label: { Text("Back to recording") }
                .buttonStyle(FoyerGhostButton())
                .padding(.horizontal, 20)
                .padding(.bottom, 36)
        default:
            EmptyView()
        }
    }

    // MARK: – Header content per phase

    private var headerEyebrow: String {
        switch store.phase {
        case .idle, .uploading: return "Uploading recording…"
        case .processing:        return "Transcribing + analyzing…"
        case .ready:             return "Session complete"
        case .failed:            return "Session error"
        }
    }
    private var headerTitle: String {
        switch store.phase {
        case .idle, .uploading: return "One moment."
        case .processing:        return "Reading the room."
        case .ready:
            let n = store.session?.result?.visitors.count ?? 0
            return "\(n) \(n == 1 ? "guest" : "guests")."
        case .failed: return "Something broke."
        }
    }
    private var headerSubtitle: String? {
        store.phase == .ready ? "Drafts ready." : nil
    }
    private var phaseLabel: String {
        switch store.phase {
        case .uploading: return "Sending to backend"
        case .processing: return "Pipeline running"
        default: return "Working"
        }
    }
    private var phaseDescription: String {
        switch store.phase {
        case .uploading:
            return "Uploading the recording to the OpenHouseBoss API."
        case .processing:
            return "Transcribing with AssemblyAI Universal-2, identifying speakers, then drafting per-visitor summaries and follow-ups. Typically 30–90 seconds for a 1-hour open house."
        default:
            return "Just a moment."
        }
    }
}

#Preview { NavigationStack { SummaryView() } }
