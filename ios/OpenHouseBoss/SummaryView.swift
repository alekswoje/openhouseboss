import SwiftUI

// Post-session summary — v2 editorial. Breadcrumb back row + a trailing
// status pill, both exit to Sessions. Per-visitor approval happens inside
// each visitor card; the footer is just a Done that returns home.
struct SummaryView: View {
    var pastSessionId: String? = nil

    @Environment(AppRouter.self) private var router
    @State private var store = SessionStore.shared
    @State private var player = AudioPlayer()
    // Inline rename state — populated lazily from session.name when the
    // sheet opens so the user always sees what's currently saved.
    @State private var showRenameSheet = false
    @State private var renameText: String = ""
    @State private var continueError: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            FoyerTheme.bgDeep.ignoresSafeArea()
            WarmBg(tone: .gold)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    BackBar(crumbs: backCrumbs, onBack: { router.popToRoot() }) {
                        StatusPill(text: trailingPillText, tone: trailingPillTone, pulsing: isProcessing)
                    }
                    header
                    if let url = audioURL {
                        playbackBar(url: url)
                    }
                    content
                    Spacer().frame(height: 140)
                }
                .padding(.top, 8)
            }

            footerButton
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if let id = pastSessionId {
                store.openPastSession(id: id)
            }
            if let url = audioURL {
                player.load(url: url)
            }
        }
        .onChange(of: audioURL) { _, new in
            if let new { player.load(url: new) }
        }
        .onDisappear { player.stop() }
    }

    // Resolve the audio source: prefer the just-recorded local file (it's
    // already on this device, no round-trip), otherwise stream the saved
    // recording from the backend so a past session opened on a different
    // device still plays.
    private var audioURL: URL? {
        if let local = store.lastRecordedAudioURL { return local }
        if let id = store.session?.id {
            return Config.backendURL
                .appendingPathComponent("sessions")
                .appendingPathComponent(id)
                .appendingPathComponent("audio")
        }
        return nil
    }

    private var backCrumbs: [String] {
        ["Sessions", sessionLabel]
    }

    private var sessionLabel: String {
        if let n = store.session?.name, !n.isEmpty { return n }
        if let addr = store.session?.address, !addr.isEmpty { return addr }
        if let id = pastSessionId { return id.prefix(8).description }
        return "Today's open house"
    }

    private var trailingPillText: String {
        switch store.phase {
        case .idle, .uploading: return "Uploading"
        case .processing:        return "Processing"
        case .ready:             return "Drafts ready"
        case .failed:            return "Error"
        }
    }
    private var trailingPillTone: StatusPill.Tone {
        switch store.phase {
        case .ready:   return .sage
        case .failed:  return .live
        default:       return .gold
        }
    }
    private var isProcessing: Bool {
        switch store.phase {
        case .idle, .uploading, .processing: return true
        default: return false
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Eyebrow(text: headerEyebrow, color: FoyerTheme.gold)
                Spacer()
                // Rename affordance — visible whenever we have a session id
                // to PATCH against (live + past).
                if store.session?.id != nil {
                    Button {
                        renameText = store.session?.name ?? ""
                        showRenameSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil")
                                .font(.system(size: 10, weight: .medium))
                            Text("RENAME")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .tracking(1.4)
                        }
                        .foregroundStyle(FoyerTheme.creamDim)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(FoyerTheme.bgElev, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            // Session name (or fallback) prints above the phase title. This
            // is what the agent actually scans the list for — keep it big.
            if let label = sessionDisplayName {
                Text(label)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(FoyerTheme.creamDim)
            }
            Text(headerTitle)
                .foyerDisplay(32)
                .foregroundStyle(FoyerTheme.cream)
            if let sub = headerSubtitle {
                Text(sub)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(FoyerTheme.gold)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .alert("Rename session", isPresented: $showRenameSheet) {
            TextField("Session name", text: $renameText)
                .textInputAutocapitalization(.sentences)
            Button("Save") {
                if let id = store.session?.id {
                    store.renameSession(id: id, to: renameText)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Empty name clears the nickname (display falls back to address).")
        }
    }

    private var sessionDisplayName: String? {
        if let n = store.session?.name, !n.isEmpty { return n }
        if let a = store.session?.address, !a.isEmpty { return a }
        return nil
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

    // Local playback bar — only shown when we have an audioURL on hand.
    private func playbackBar(url: URL) -> some View {
        GlassSurface(cornerRadius: 16) {
            HStack(spacing: 14) {
                Button { player.playPause() } label: {
                    ZStack {
                        Circle()
                            .fill(FoyerTheme.gold)
                            .shadow(color: FoyerTheme.gold.opacity(0.5), radius: 10, y: 4)
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(FoyerTheme.inkOnGold)
                    }
                    .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "Recorded audio · tap to play", color: FoyerTheme.creamDim)
                    progressTrack
                    HStack {
                        Text(timeString(player.currentTime))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .tracking(1.2)
                            .foregroundStyle(FoyerTheme.textMuted)
                        Spacer()
                        Text(timeString(player.duration))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .tracking(1.2)
                            .foregroundStyle(FoyerTheme.textMuted)
                    }
                }
            }
            .padding(14)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    private var progressTrack: some View {
        GeometryReader { geo in
            let fraction = player.duration > 0 ? min(1, player.currentTime / player.duration) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(FoyerTheme.hairline).frame(height: 3)
                Capsule().fill(FoyerTheme.gold).frame(width: geo.size.width * fraction, height: 3)
                    .shadow(color: FoyerTheme.gold.opacity(0.4), radius: 6, y: 0)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        guard player.duration > 0 else { return }
                        let f = max(0, min(1, val.location.x / geo.size.width))
                        player.seek(to: f * player.duration)
                    }
            )
        }
        .frame(height: 14)
    }

    private func timeString(_ t: TimeInterval) -> String {
        guard t.isFinite else { return "0:00" }
        let total = Int(t)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var processingCard: some View {
        GlassSurface(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(FoyerTheme.gold)
                        .scaleEffect(0.9)
                    Eyebrow(text: phaseLabel, color: FoyerTheme.gold)
                }
                Text(phaseDescription)
                    .font(.system(size: 13))
                    .foregroundStyle(FoyerTheme.creamDim)
                    .lineSpacing(3)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
    }

    private func errorCard(_ message: String) -> some View {
        // The recording is preserved on the backend, so we can re-run the
        // pipeline against the saved audio without making the agent re-record.
        // Handy when (a) the failure was a transient LLM/decoder hiccup, or
        // (b) we shipped a backend fix and want to retry old failed sessions.
        VStack(spacing: 14) {
            GlassSurface(cornerRadius: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "Couldn't process session", color: FoyerTheme.terracotta)
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(FoyerTheme.cream)
                        .lineSpacing(3)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if store.session?.id != nil {
                Button { store.reanalyze(guestsExpected: nil) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Re-analyze recording")
                    }
                }
                .buttonStyle(FoyerPrimaryButton())
            }
        }
        .padding(.horizontal, 20)
    }

    private var visitorList: some View {
        let visitors = store.session?.result?.visitors ?? []
        return VStack(alignment: .leading, spacing: 0) {
            reportCTA
                .padding(.horizontal, 20)
                .padding(.bottom, 22)
            if let coverage = store.session?.result?.scriptCoverage {
                scriptCoverageSection(coverage)
                Spacer().frame(height: 20)
            }
            agentTranscriptSection
            if visitors.isEmpty {
                Text("No guests detected. The recording might have been too short or only contained your voice.")
                    .font(.system(size: 13))
                    .foregroundStyle(FoyerTheme.textDim)
                    .lineSpacing(3)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
            } else {
                Eyebrow(text: "Ranked · Hottest first")
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
                VStack(spacing: 12) {
                    ForEach(Array(visitors.enumerated()), id: \.element.id) { idx, v in
                        Button { router.push(.visitorDetail(v)) } label: {
                            visitorCard(v, hot: idx == 0)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            reanalyzeSection(detected: visitors.count)
        }
        .padding(.top, 6)
    }

    // The headline CTA after a session completes: generate (or open) the
    // homeowner-facing Open House Report. Once the session is "ready", this
    // is the agent's primary next action — every other surface is review.
    private var reportCTA: some View {
        Button {
            router.push(.report(sessionId: store.session?.id))
        } label: {
            GlassSurface(cornerRadius: 16, strong: true) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(FoyerTheme.gold)
                            .shadow(color: FoyerTheme.gold.opacity(0.5), radius: 12, y: 4)
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(FoyerTheme.inkOnGold)
                    }
                    .frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Open house report")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(FoyerTheme.cream)
                        Text("Generate · review · send to homeowner")
                            .font(.system(size: 12))
                            .foregroundStyle(FoyerTheme.creamDim)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(FoyerTheme.gold)
                }
                .padding(14)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(FoyerTheme.gold.opacity(0.40), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // Re-analyze affordance — for when diarization undercounts (e.g. one
    // person doing impressions, or two guests with very similar voices).
    // Lets the agent re-run the pipeline with a corrected speaker count
    // against the saved audio.
    @State private var reanalyzeCount: Int = 0   // 0 = unset
    @State private var reanalyzeExpanded: Bool = false

    private func reanalyzeSection(detected: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation { reanalyzeExpanded.toggle() }
                if reanalyzeCount == 0 { reanalyzeCount = max(2, detected + 1) }
            } label: {
                HStack {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 13, weight: .medium))
                    Text("Detected \(detected) guest\(detected == 1 ? "" : "s") · expected more?")
                        .font(.system(size: 13))
                    Spacer()
                    Image(systemName: reanalyzeExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(FoyerTheme.creamDim)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(FoyerTheme.bgElev, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(FoyerTheme.border, lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            if reanalyzeExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Text("How many distinct guests are in the recording (not counting you)? We'll tell the diarizer exactly that count and re-run.")
                        .font(.system(size: 12))
                        .foregroundStyle(FoyerTheme.textDim)
                        .lineSpacing(2)

                    HStack(spacing: 14) {
                        Button { if reanalyzeCount > 1 { reanalyzeCount -= 1 } } label: {
                            stepperButton(systemName: "minus")
                        }
                        .buttonStyle(.plain)

                        VStack(spacing: 2) {
                            Text("\(reanalyzeCount)")
                                .font(.system(size: 32, weight: .medium))
                                .foregroundStyle(FoyerTheme.gold)
                            Text("GUESTS (NOT YOU)")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .tracking(1.4)
                                .foregroundStyle(FoyerTheme.textMuted)
                        }
                        .frame(maxWidth: .infinity)

                        Button { if reanalyzeCount < 20 { reanalyzeCount += 1 } } label: {
                            stepperButton(systemName: "plus")
                        }
                        .buttonStyle(.plain)
                    }

                    Button { store.reanalyze(guestsExpected: reanalyzeCount) } label: {
                        Text("Re-analyze with \(reanalyzeCount) guest\(reanalyzeCount == 1 ? "" : "s")")
                    }
                    .buttonStyle(FoyerPrimaryButton())
                }
                .padding(14)
                .background(FoyerTheme.bgCard, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(FoyerTheme.border, lineWidth: 0.5))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private func stepperButton(systemName: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(FoyerTheme.bgElev)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(FoyerTheme.borderStrong, lineWidth: 0.5)
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(FoyerTheme.cream)
        }
        .frame(width: 44, height: 44)
    }

    private func visitorCard(_ v: VisitorResult, hot: Bool) -> some View {
        GlassSurface(cornerRadius: 16, strong: hot) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(v.visitor.name)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(FoyerTheme.cream)
                        Text("SPOKE \(v.analysis.wordsSpoken)W · SPEAKER \(v.visitor.speaker ?? "?")")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .tracking(1.4)
                            .foregroundStyle(FoyerTheme.textMuted)
                    }
                    Spacer()
                    if let kind = TagPill.Kind(v.analysis.tagToken) {
                        TagPill(kind: kind, text: "\(v.analysis.score)")
                    }
                }
                Text(v.analysis.summary)
                    .font(.system(size: 13))
                    .foregroundStyle(FoyerTheme.creamDim)
                    .lineSpacing(3)
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if hot {
                    Hairline().padding(.top, 14)
                    HStack {
                        Text(v.analysis.tag.uppercased() + " · " + v.analysis.tagReason)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .tracking(1.2)
                            .foregroundStyle(FoyerTheme.textMuted)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("Review →")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(FoyerTheme.gold)
                    }
                    .padding(.top, 10)
                }
            }
            .padding(16)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(hot ? FoyerTheme.gold.opacity(0.40) : Color.clear, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var footerButton: some View {
        switch store.phase {
        case .ready:
            // Two actions: Continue recording resumes capture into the same
            // backend session (so a "stop for now, resume later" workflow
            // works without creating a duplicate session); Done is the
            // existing bail-to-home affordance.
            VStack(spacing: 10) {
                if let err = continueError {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(FoyerTheme.terracotta)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                if store.session?.id != nil {
                    Button { continueRecordingTapped() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Continue recording")
                        }
                    }
                    .buttonStyle(FoyerGhostButton())
                }
                Button { router.popToRoot() } label: { Text("Done · back to sessions") }
                    .buttonStyle(FoyerPrimaryButton())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 36)

        case .failed:
            Button { router.popToRoot() } label: { Text("Back to home") }
                .buttonStyle(FoyerGhostButton())
                .padding(.horizontal, 20)
                .padding(.bottom, 36)

        case .idle, .uploading, .processing:
            // While processing, give the user a way to bail back to home
            // (the analysis keeps running in the SessionStore task and shows
            // up in the list when it's done).
            Button { router.popToRoot() } label: { Text("Continue in background") }
                .buttonStyle(FoyerGhostButton())
                .padding(.horizontal, 20)
                .padding(.bottom, 36)
        }
    }

    private func continueRecordingTapped() {
        guard let id = store.session?.id else { return }
        let address = store.session?.address
        let name = store.session?.name
        // Picks the script the session was originally graded on (if any)
        // so coverage re-grading after the resumed segment uses the same
        // rubric. Falls back to the agent's default the same way the
        // fresh-recording flow does.
        let scriptId = store.session?.result?.scriptCoverage?.scriptId
        Task { @MainActor in
            continueError = nil
            do {
                try await store.continueRecording(
                    sessionId: id, address: address, name: name, scriptId: scriptId
                )
                router.path = [.live]
            } catch {
                continueError = "Couldn't resume: \(error.localizedDescription)"
            }
        }
    }

    // MARK: – Header content per phase

    private var headerEyebrow: String {
        switch store.phase {
        case .idle, .uploading: return "Uploading recording"
        case .processing:        return "Reading the room"
        case .ready:             return "Session complete"
        case .failed:            return "Session error"
        }
    }
    private var headerTitle: String {
        switch store.phase {
        case .idle, .uploading: return "One moment."
        case .processing:        return "Transcribing + analyzing."
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
            return "Uploading the recording to the Open House Copilot API."
        case .processing:
            return "Transcribing with AssemblyAI Universal-2, identifying speakers, then drafting per-visitor summaries and follow-ups. Typically 30–90 seconds for a 1-hour open house."
        default:
            return "Just a moment."
        }
    }
}

// MARK: – Agent transcript (what you said, who you were talking to)

extension SummaryView {
    // Builds an agent-centric transcript: every turn the agent took, with
    // the visitor they were most likely addressing at that moment derived
    // from the surrounding diarized turns. Helps the agent skim their own
    // performance instead of squinting at a flat transcript.
    @ViewBuilder
    var agentTranscriptSection: some View {
        let result = store.session?.result
        let utterances = result?.utterances ?? []
        let agentSpeaker = result?.agentSpeaker ?? ""
        let speakerNameMap = Dictionary(
            uniqueKeysWithValues: (result?.visitors ?? []).compactMap { v -> (String, String)? in
                guard let s = v.visitor.speaker else { return nil }
                return (s, v.visitor.name)
            }
        )
        let agentTurns: [AgentTurn] = Self.buildAgentTurns(
            utterances: utterances,
            agentSpeaker: agentSpeaker,
            speakerNameMap: speakerNameMap
        )

        if !agentTurns.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Eyebrow(text: "What you said · who you were talking to", color: FoyerTheme.gold)
                    Spacer()
                    Text("\(agentTurns.count) TURNS")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(FoyerTheme.textMuted)
                }
                .padding(.horizontal, 20)

                VStack(spacing: 8) {
                    ForEach(agentTurns) { turn in
                        agentTurnCard(turn)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.top, 6)
            .padding(.bottom, 20)
        }
    }

    private func agentTurnCard(_ turn: AgentTurn) -> some View {
        GlassSurface(cornerRadius: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("YOU")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(FoyerTheme.inkOnGold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(FoyerTheme.gold, in: Capsule())
                    if let addressed = turn.addressing {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(FoyerTheme.textMuted)
                        Text(addressed.uppercased())
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .tracking(1.4)
                            .foregroundStyle(FoyerTheme.creamDim)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(turn.timestampLabel)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(FoyerTheme.textMuted)
                }
                Text(turn.text)
                    .font(.system(size: 14))
                    .foregroundStyle(FoyerTheme.cream)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
        }
    }

    // Walk the utterance list once, collapsing consecutive agent turns into
    // a single block and using the *next* non-agent speaker as the most
    // likely addressee (you typically address the visitor who is about to
    // respond; if there's no following visitor turn, use the previous one).
    static func buildAgentTurns(
        utterances: [Utterance],
        agentSpeaker: String,
        speakerNameMap: [String: String]
    ) -> [AgentTurn] {
        guard !utterances.isEmpty, !agentSpeaker.isEmpty else { return [] }

        var result: [AgentTurn] = []
        var i = 0
        var lastVisitorSpeaker: String? = nil

        while i < utterances.count {
            if utterances[i].speaker != agentSpeaker {
                lastVisitorSpeaker = utterances[i].speaker
                i += 1
                continue
            }
            let blockStart = i
            var combinedText: [String] = []
            while i < utterances.count, utterances[i].speaker == agentSpeaker {
                combinedText.append(utterances[i].text)
                i += 1
            }
            let nextVisitorSpeaker: String? = {
                var j = i
                while j < utterances.count {
                    if utterances[j].speaker != agentSpeaker { return utterances[j].speaker }
                    j += 1
                }
                return nil
            }()
            let addressed = nextVisitorSpeaker ?? lastVisitorSpeaker
            let addressedLabel = addressed.map { speakerNameMap[$0] ?? "Speaker \($0)" }
            let startMs = utterances[blockStart].startMs
            result.append(AgentTurn(
                index: result.count,
                text: combinedText.joined(separator: " "),
                addressing: addressedLabel,
                startMs: startMs
            ))
        }
        return result
    }
}

struct AgentTurn: Identifiable, Hashable {
    let index: Int
    let text: String
    let addressing: String?
    let startMs: Int

    var id: Int { index }

    var timestampLabel: String {
        let total = max(0, startMs / 1000)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: – Script coverage

extension SummaryView {
    @ViewBuilder
    func scriptCoverageSection(_ coverage: ScriptCoverage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: "Script coverage", color: FoyerTheme.gold)
                Spacer()
                if let score = coverage.score {
                    Text("\(score)")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(coverageScoreColor(score))
                    Text("/100")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(FoyerTheme.textMuted)
                }
            }
            .padding(.horizontal, 20)

            if let err = coverage.error {
                GlassSurface(cornerRadius: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(text: "Couldn't grade", color: FoyerTheme.terracotta)
                        Text(err)
                            .font(.system(size: 12))
                            .foregroundStyle(FoyerTheme.creamDim)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
            } else {
                Text(coverage.scriptName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(FoyerTheme.cream)
                    .padding(.horizontal, 20)
                if let s = coverage.overallSummary, !s.isEmpty {
                    Text(s)
                        .font(.system(size: 12))
                        .foregroundStyle(FoyerTheme.textDim)
                        .lineSpacing(3)
                        .padding(.horizontal, 20)
                }
                if let steps = coverage.steps {
                    coverageRows(steps)
                }
            }
        }
    }

    @ViewBuilder
    private func coverageRows(_ steps: [StepCoverage]) -> some View {
        VStack(spacing: 8) {
            ForEach(steps) { step in
                CoverageRow(step: step)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private func coverageScoreColor(_ score: Int) -> Color {
        switch score {
        case 75...:    return FoyerTheme.sage
        case 40..<75:  return FoyerTheme.gold
        default:       return FoyerTheme.terracotta
        }
    }
}

// One row in the coverage list — tap to expand the suggestion + evidence.
struct CoverageRow: View {
    let step: StepCoverage
    @State private var expanded = false

    var body: some View {
        Button { withAnimation { expanded.toggle() } } label: {
            GlassSurface(cornerRadius: 12) {
                VStack(alignment: .leading, spacing: expanded ? 10 : 0) {
                    HStack(spacing: 10) {
                        statusPill
                        Text(stepLabel)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(FoyerTheme.cream)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(FoyerTheme.textMuted)
                    }
                    if expanded {
                        if !step.evidence.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("YOU SAID")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .tracking(1.4)
                                    .foregroundStyle(FoyerTheme.textMuted)
                                Text("\"\(step.evidence)\"")
                                    .font(.system(size: 13))
                                    .foregroundStyle(FoyerTheme.cream)
                                    .lineSpacing(2)
                            }
                        }
                        if !step.suggestion.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("SUGGESTION")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .tracking(1.4)
                                    .foregroundStyle(FoyerTheme.gold)
                                Text(step.suggestion)
                                    .font(.system(size: 13))
                                    .foregroundStyle(FoyerTheme.creamDim)
                                    .lineSpacing(2)
                            }
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    // Pretty label from step id. For known Aleks-script ids we use human
    // labels; unknown ids fall back to the raw id (with underscores → spaces).
    private var stepLabel: String {
        ScriptStepLookup.label(for: step.stepId)
    }

    @ViewBuilder
    private var statusPill: some View {
        switch step.status.lowercased() {
        case "hit":     StatusPill(text: "Hit",     tone: .sage)
        case "partial": StatusPill(text: "Partial", tone: .gold)
        case "missed":  StatusPill(text: "Missed",  tone: .live)
        default:        StatusPill(text: step.status, tone: .glass)
        }
    }
}

// Lookup for known preset script step ids → human labels. Mirrors the
// labels in pipeline/scripts.py.
enum ScriptStepLookup {
    static let labels: [String: String] = [
        "opener":              "The Opener",
        "buyer_timeline":      "Step 1 — Timeline",
        "buyer_search_history":"Step 2 — Search History",
        "buyer_pain":          "Step 3 — Uncover Pain",
        "buyer_offer_check":   "Step 4 — Offer Check",
        "buyer_lender":        "Step 5 — Lender",
        "buyer_release":       "Step 6 — Release + Hook",
        "buyer_reengage":      "Step 7 — Re-Engage",
        "buyer_close_rebate":  "Step 8 — Close + Rebate",
        "seller_pricing":      "Seller — Pricing Pivot",
        "seller_curiosity":    "Seller — Curiosity Test",
        "seller_marketing":    "Seller — Marketing Pitch",
        "seller_comp":         "Seller — Comp Offer",
    ]

    static func label(for id: String) -> String {
        labels[id] ?? id.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

#Preview { NavigationStack { SummaryView() } }
