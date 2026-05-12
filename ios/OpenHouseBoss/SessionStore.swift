import Foundation
import Observation

// Shared session store — drives both the live → upload → poll → results flow
// and the past-session browsing flow.
@MainActor
@Observable
final class SessionStore {
    enum Phase: Equatable {
        case idle
        case uploading        // POSTing the audio
        case processing       // backend is transcribing + analyzing
        case ready
        case failed(String)
    }

    static let shared = SessionStore()

    private init() {
        self.defaultScriptId = UserDefaults.standard.string(forKey: "defaultScriptId")
        if let data = UserDefaults.standard.data(forKey: "listings"),
           let decoded = try? JSONDecoder().decode([Listing].self, from: data) {
            self.listings = decoded
        }
    }

    private func persistListings() {
        if let data = try? JSONEncoder().encode(listings) {
            UserDefaults.standard.set(data, forKey: "listings")
        }
    }

    func addListing(_ listing: Listing) {
        listings.insert(listing, at: 0)
        persistListings()
    }

    func updateListing(_ listing: Listing) {
        if let idx = listings.firstIndex(where: { $0.id == listing.id }) {
            listings[idx] = listing
            persistListings()
        }
    }

    func deleteListing(id: String) {
        listings.removeAll { $0.id == id }
        persistListings()
    }

    var phase: Phase = .idle
    var session: Session?
    // Compact list shown on the home screen. Refreshed lazily.
    var pastSessions: [SessionSummary] = []
    var listLoading = false
    var listError: String?
    // Address typed in SetupView, used by uploadAndProcess.
    var pendingAddress: String?
    // Expected-guest-count hint typed in SetupView. Forwarded to AssemblyAI
    // as `speakers_expected` — significantly improves diarization when the
    // model would otherwise collapse similar voices into one speaker.
    var pendingSpeakersExpected: Int?
    // Guests checked in via the phone kiosk (KioskSignInView) before
    // recording. Bumps the default speakers_expected and is shown in the
    // Setup screen as a confirmation.
    var pendingKioskGuests: [VisitorInput] = []
    // Script the agent picked on the Setup screen — drives post-session
    // coverage grading. nil = no coverage analysis.
    var pendingScriptId: String?
    // Preset scripts pulled from /scripts. Refreshed lazily.
    var availableScripts: [ScriptSummary] = []
    // Default script applied to every session unless the agent overrides it.
    // Persisted in UserDefaults so it survives launches.
    var defaultScriptId: String? {
        didSet {
            UserDefaults.standard.set(defaultScriptId, forKey: "defaultScriptId")
        }
    }
    // Agent-curated open-house listings. Tapping one starts a new session
    // with that property's address pre-filled.
    var listings: [Listing] = []
    // Local m4a from the last recording — kept so SummaryView can offer
    // playback for QA-ing mic placement. Cleared on reset.
    var lastRecordedAudioURL: URL?

    private var pollTask: Task<Void, Never>?

    // Live-recording snapshot state. While the agent is recording, we kick
    // off periodic uploads so the lead list + script coverage stay roughly
    // current without the agent having to stop and restart between guests.
    // `liveSnapshotTask` runs the cadence loop until End Session; the
    // schedule below is the per-tick delay (seconds from start). After we
    // run out of schedule entries, fall back to every 30 minutes.
    private var liveSnapshotTask: Task<Void, Never>?
    var liveSnapshotInFlight: Bool = false
    var liveLastSnapshotAt: Date?
    var liveSnapshotError: String?
    private static let liveSnapshotSchedule: [TimeInterval] = [
        5 * 60, 10 * 60, 20 * 60, 30 * 60,
        50 * 60, 70 * 60, 90 * 60, 120 * 60,
    ]

    // Called from LiveView on End session. Uploads the m4a, then polls until
    // the backend either finishes processing or errors out.
    func uploadAndProcess(audioURL: URL) {
        cancel()
        phase = .uploading
        session = nil
        lastRecordedAudioURL = audioURL
        let address = pendingAddress
        let expected = pendingSpeakersExpected
        // Use the session-specific override if set, otherwise fall back to
        // the agent's persisted default. nil = no coverage analysis.
        let scriptId = pendingScriptId ?? defaultScriptId
        // Snapshot the kiosk sign-ins so the backend can match each
        // diarized speaker to the right person (name + email + phone).
        // Without this, diarization produces anonymous "Speaker A/B/C"
        // visitors and we lose the connection between the recorded voice
        // and the contact info the guest just typed in.
        let guests = pendingKioskGuests
        pendingAddress = nil
        pendingSpeakersExpected = nil
        pendingScriptId = nil
        pendingKioskGuests = []
        Log.net("uploadAndProcess → \(audioURL.lastPathComponent), address=\(address ?? "<none>"), speakers=\(expected.map(String.init) ?? "<auto>"), script=\(scriptId ?? "<none>"), guests=\(guests.count)")
        pollTask = Task { [weak self] in
            do {
                let initial: Session
                if guests.isEmpty {
                    initial = try await APIClient.shared.createSession(
                        audioURL: audioURL, address: address, speakersExpected: expected, scriptId: scriptId)
                } else {
                    initial = try await APIClient.shared.createSession(
                        audioURL: audioURL, address: address, visitors: guests, speakersExpected: expected, scriptId: scriptId)
                }
                Log.net("createSession ← id=\(initial.id) status=\(initial.status)")
                await MainActor.run {
                    self?.session = initial
                    self?.phase = .processing
                }
                let final = try await APIClient.shared.pollUntilDone(id: initial.id)
                Log.net("pollUntilDone ← \(final.status), visitors=\(final.result?.visitors.count ?? 0)")
                await MainActor.run {
                    self?.session = final
                    if final.status == "error" {
                        self?.phase = .failed(final.error ?? "Unknown error")
                    } else {
                        self?.phase = .ready
                    }
                }
                await self?.refreshSessions()
            } catch {
                Log.warn("uploadAndProcess failed: \(error.localizedDescription)")
                await MainActor.run {
                    self?.phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    // ============================================================
    // Live-recording snapshot flow
    // ============================================================
    //
    // While the agent is recording on the iPad we periodically:
    //   1. Tell AudioRecorder to rotate to a fresh chunk (finalizes the
    //      previous chunk's m4a so it's safe to read)
    //   2. Concatenate every finalized chunk into a single m4a
    //   3. POST it to either /sessions (first tick — creates the session)
    //      or /sessions/{id}/snapshot (subsequent ticks — replaces the
    //      session's audio + re-runs pipeline)
    //   4. Poll the session and update `self.session` so the iPad's live
    //      pane can show "Updated 5m ago" + the current coverage score
    //
    // First tick runs on a `light` pass — backend skips per-visitor Claude
    // analysis to keep cost down; agent still sees the lead list growing
    // and the coverage score updating. End Session does one final `full`
    // pass to fill in summaries / drafts.

    func startLiveSnapshotLoop() {
        liveSnapshotTask?.cancel()
        liveSnapshotError = nil
        liveLastSnapshotAt = nil
        let address = pendingAddress
        let expected = pendingSpeakersExpected
        let scriptId = pendingScriptId ?? defaultScriptId
        let guests = pendingKioskGuests
        pendingAddress = nil
        pendingSpeakersExpected = nil
        pendingScriptId = nil
        pendingKioskGuests = []
        let schedule = SessionStore.liveSnapshotSchedule
        liveSnapshotTask = Task { [weak self] in
            guard let self else { return }
            let started = Date()
            var index = 0
            while !Task.isCancelled {
                // Compute the next tick's wall-clock target. After the
                // schedule is exhausted, fall back to 30-minute intervals
                // anchored to the last scheduled tick.
                let target: TimeInterval
                if index < schedule.count {
                    target = schedule[index]
                } else {
                    let overflow = TimeInterval(index - schedule.count + 1) * (30 * 60)
                    target = schedule.last! + overflow
                }
                let now = Date().timeIntervalSince(started)
                let delay = max(target - now, 0)
                if delay > 0 {
                    try? await Task.sleep(for: .seconds(delay))
                }
                if Task.isCancelled { return }
                await self.snapshotTick(
                    address: address,
                    expected: expected,
                    scriptId: scriptId,
                    guests: guests,
                    depth: .light
                )
                index += 1
            }
        }
    }

    // Called when the agent taps End Session. Stops the chunked recorder,
    // pushes one final snapshot at depth=.full so per-visitor analysis +
    // drafts get filled in, then transitions the store into the same
    // .ready phase the iPhone summary expects.
    func endLiveSnapshotLoop() {
        liveSnapshotTask?.cancel()
        liveSnapshotTask = nil
        let address = pendingAddress
        let expected = pendingSpeakersExpected
        let scriptId = pendingScriptId ?? defaultScriptId
        let guests = pendingKioskGuests
        pendingAddress = nil
        pendingSpeakersExpected = nil
        pendingScriptId = nil
        pendingKioskGuests = []
        // Show the processing pane immediately so the agent knows the final
        // pass is in flight; the snapshot tick replaces `phase` with .ready
        // (or .failed) when it returns.
        phase = .processing
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            await self?.snapshotTick(
                address: address,
                expected: expected,
                scriptId: scriptId,
                guests: guests,
                depth: .full,
                isFinal: true
            )
        }
    }

    // One snapshot pass — rotate to a fresh chunk, concat everything so
    // far, upload. Idempotent against being called from the cadence loop
    // (light) or the End-Session hook (full).
    private func snapshotTick(
        address: String?,
        expected: Int?,
        scriptId: String?,
        guests: [VisitorInput],
        depth: APIClient.AnalysisDepth,
        isFinal: Bool = false
    ) async {
        await MainActor.run { self.liveSnapshotInFlight = true }
        defer { Task { @MainActor in self.liveSnapshotInFlight = false } }
        // Rotate to a new chunk so the previous one becomes a fully-formed
        // m4a (moov atom written). On End Session, also stop the recorder
        // entirely after the rotation.
        _ = await MainActor.run { AudioRecorder.shared.rotateChunk() }
        if isFinal {
            _ = await MainActor.run { AudioRecorder.shared.stopRecording() }
        }
        guard let concatURL = await AudioRecorder.shared.concatenatedURL() else {
            await MainActor.run {
                self.liveSnapshotError = "Couldn't assemble audio for snapshot."
                if isFinal { self.phase = .failed(self.liveSnapshotError!) }
            }
            return
        }
        defer { try? FileManager.default.removeItem(at: concatURL) }
        do {
            if let id = self.session?.id {
                // Subsequent tick — replace the in-flight audio + re-run
                // pipeline at the requested depth.
                try await APIClient.shared.uploadSnapshot(
                    sessionId: id, audioURL: concatURL, depth: depth, speakersExpected: expected
                )
                let final = try await APIClient.shared.pollUntilDone(id: id)
                await MainActor.run {
                    self.session = final
                    self.liveLastSnapshotAt = Date()
                    if isFinal {
                        self.phase = (final.status == "error")
                            ? .failed(final.error ?? "Unknown error")
                            : .ready
                    }
                }
            } else {
                // First tick — creates the session via the existing
                // /sessions endpoint (which always does full analysis on
                // the first pass). Subsequent ticks then run as light.
                let initial: Session
                if guests.isEmpty {
                    initial = try await APIClient.shared.createSession(
                        audioURL: concatURL, address: address,
                        speakersExpected: expected, scriptId: scriptId
                    )
                } else {
                    initial = try await APIClient.shared.createSession(
                        audioURL: concatURL, address: address, visitors: guests,
                        speakersExpected: expected, scriptId: scriptId
                    )
                }
                await MainActor.run { self.session = initial }
                let final = try await APIClient.shared.pollUntilDone(id: initial.id)
                await MainActor.run {
                    self.session = final
                    self.liveLastSnapshotAt = Date()
                    if isFinal {
                        self.phase = (final.status == "error")
                            ? .failed(final.error ?? "Unknown error")
                            : .ready
                    }
                }
            }
            await self.refreshSessions()
        } catch {
            Log.warn("snapshotTick failed: \(error.localizedDescription)")
            await MainActor.run {
                self.liveSnapshotError = error.localizedDescription
                if isFinal { self.phase = .failed(error.localizedDescription) }
            }
        }
    }

    // Browse a past session by id. Fetches the full session (with result) and
    // pushes the store into the same .ready / .processing / .failed states the
    // live flow uses, so SummaryView can render it uniformly.
    func openPastSession(id: String) {
        cancel()
        phase = .processing       // shows the loading card while we fetch
        session = nil
        pollTask = Task { [weak self] in
            do {
                let s = try await APIClient.shared.getSession(id: id)
                await MainActor.run {
                    self?.session = s
                    switch s.status {
                    case "ready":      self?.phase = .ready
                    case "error":      self?.phase = .failed(s.error ?? "Unknown error")
                    default:           self?.phase = .processing
                    }
                }
                // If it was still processing on the server, poll until done.
                if s.status == "processing" {
                    let final = try await APIClient.shared.pollUntilDone(id: id)
                    await MainActor.run {
                        self?.session = final
                        self?.phase = (final.status == "error")
                            ? .failed(final.error ?? "Unknown error")
                            : .ready
                    }
                }
            } catch {
                await MainActor.run {
                    self?.phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    // Refresh the home-screen list from GET /sessions.
    func refreshSessions() async {
        let start = Date()
        Log.net("refreshSessions → GET /sessions")
        await MainActor.run {
            self.listLoading = true
            self.listError = nil
        }
        do {
            let items = try await APIClient.shared.listSessions()
            await MainActor.run {
                self.pastSessions = items
                self.listLoading = false
            }
            Log.net("refreshSessions ← \(items.count) items in \(Int(Date().timeIntervalSince(start) * 1000))ms")
        } catch {
            await MainActor.run {
                self.listError = error.localizedDescription
                self.listLoading = false
            }
            Log.warn("refreshSessions failed: \(error.localizedDescription)")
        }
    }

    // Re-run analysis on the current session's saved audio with a different
    // speakers_expected hint. The Summary screen uses this when diarization
    // undercounts (e.g. one person doing impressions → AAI collapsed them).
    //
    // `guestsExpected` is what the agent thinks in (number of OTHER people
    // in the room). AssemblyAI's API counts the agent too, so we add 1 on
    // the way out — set guestsExpected=2 → speakers_expected=3 → AAI looks
    // for agent + 2 guests.
    func reanalyze(guestsExpected: Int) {
        guard let sessionId = session?.id else { return }
        cancel()
        phase = .processing
        let totalSpeakers = guestsExpected + 1
        Log.net("reanalyze → \(sessionId) guests=\(guestsExpected) (total speakers=\(totalSpeakers))")
        pollTask = Task { [weak self] in
            do {
                try await APIClient.shared.reprocessSession(id: sessionId, speakersExpected: totalSpeakers)
                let final = try await APIClient.shared.pollUntilDone(id: sessionId)
                await MainActor.run {
                    self?.session = final
                    self?.phase = (final.status == "error")
                        ? .failed(final.error ?? "Unknown error")
                        : .ready
                }
                await self?.refreshSessions()
            } catch {
                await MainActor.run {
                    self?.phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    func cancel() {
        pollTask?.cancel()
        pollTask = nil
    }

    func reset() {
        cancel()
        session = nil
        phase = .idle
        pendingAddress = nil
        pendingSpeakersExpected = nil
        pendingScriptId = nil
        lastRecordedAudioURL = nil
    }

    // Fetch the preset script list once per app launch (cheap, ~1 round-trip).
    func refreshScripts() async {
        do {
            let items = try await APIClient.shared.listScripts()
            await MainActor.run { self.availableScripts = items }
        } catch {
            Log.warn("refreshScripts failed: \(error.localizedDescription)")
        }
    }
}
