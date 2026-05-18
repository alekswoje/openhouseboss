import Foundation
import Observation

// Recording-state record persisted to UserDefaults during an in-flight
// session. Drives:
//   1. **Crash recovery** — if the app dies mid-recording, on next launch
//      we see this record (cleanlyEnded=false) and offer "Recover unfinished
//      recording" on the Home banner.
//   2. **Continue recording** — even on a clean End Session we keep the
//      record around (cleanlyEnded=true, backendSessionId populated) so
//      SummaryView / IPadSessionDetail can resume capture into the same
//      chunks dir + backend session.
//
// Stored in UserDefaults under `inFlightRecording.v1`. There's at most one
// record at a time; a new recording overwrites the prior one.
struct InFlightRecording: Codable {
    var localChunksDirName: String      // bare dir name under Documents/Recordings/
    var backendSessionId: String?       // nil until first snapshot tick lands
    var name: String?
    var address: String?
    var scriptId: String?
    var expectedSpeakers: Int?
    var startedAt: Date
    var cleanlyEnded: Bool
    var lastSnapshotAt: Date?
}

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

    private static let pastSessionsCacheKey = "pastSessionsCache.v1"
    fileprivate static let inFlightRecordingKey = "inFlightRecording.v1"

    private init() {
        self.defaultScriptId = UserDefaults.standard.string(forKey: "defaultScriptId")
        if let data = UserDefaults.standard.data(forKey: "listings"),
           let decoded = try? JSONDecoder().decode([Listing].self, from: data) {
            self.listings = decoded
        }
        // Stale-while-revalidate: paint the cached sessions list immediately
        // on launch so the Home tab isn't empty during the GET /sessions
        // round-trip. refreshSessions runs in the background and rewrites
        // the cache when fresh data arrives.
        if let data = UserDefaults.standard.data(forKey: Self.pastSessionsCacheKey),
           let decoded = try? JSONDecoder().decode([SessionSummary].self, from: data) {
            self.pastSessions = decoded
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
    // Agent-set nickname for the in-flight session. Wired to the name field
    // on the recording surface. Optional — if left blank, the backend
    // auto-coins a label from the transcript at end of session.
    var pendingName: String?
    // Unfinished recording detected at app launch — drives the Home-tab
    // "Recover unfinished recording" banner. nil = no leftover record or
    // it's already been cleared/recovered.
    var unfinishedRecording: InFlightRecording?
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

    // Live-companion check-in poller. Started by snapshotTick once the
    // session id exists; watches session.pendingCheckInId and kicks a
    // snapshot tagged with that id when the companion device requests one.
    private var liveCheckInPollTask: Task<Void, Never>?
    private var lastHandledCheckInId: String?
    // Snapshot of the setup args captured when the loop starts — the periodic
    // tick consumes them once, but the dev "Analyze now" button needs them
    // again for the first manual tick if the agent fires it before the 5-min
    // periodic tick has run. Stays put for the whole recording session.
    private var liveSnapshotAddress: String?
    private var liveSnapshotName: String?
    private var liveSnapshotExpected: Int?
    private var liveSnapshotScriptId: String?
    private var liveSnapshotGuests: [VisitorInput] = []
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
                // Backend session now exists — stamp the InFlightRecording
                // (written by LiveView at recording start) with the id so the
                // Recover banner can route to /snapshot if it ever resurfaces
                // before pollUntilDone returns.
                await MainActor.run { self?.updateInFlightBackendId(initial.id) }
                let final = try await APIClient.shared.pollUntilDone(id: initial.id)
                Log.net("pollUntilDone ← \(final.status), visitors=\(final.result?.visitors.count ?? 0)")
                await MainActor.run {
                    self?.session = final
                    if final.status == "error" {
                        self?.phase = .failed(final.error ?? "Unknown error")
                    } else {
                        self?.phase = .ready
                        // Successful end-to-end → drop the InFlightRecording
                        // so the Home banner doesn't keep surfacing it. The
                        // chunks dir stays on disk (the "Local recordings"
                        // picker on Home is the last-resort escape hatch).
                        self?.markInFlightCleanlyEnded()
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
        liveSnapshotAddress = pendingAddress
        liveSnapshotName = pendingName
        liveSnapshotExpected = pendingSpeakersExpected
        liveSnapshotScriptId = pendingScriptId ?? defaultScriptId
        liveSnapshotGuests = pendingKioskGuests
        let address = liveSnapshotAddress
        let nickname = liveSnapshotName
        let expected = liveSnapshotExpected
        let scriptId = liveSnapshotScriptId
        let guests = liveSnapshotGuests
        // Stamp the persistent in-flight record so a crash mid-session is
        // recoverable from Home. AudioRecorder.shared.chunksDirectory was
        // just set by startRecording() — its last path component is the
        // session-prefix string we keep in the record.
        writeInFlightRecord(
            address: address, name: nickname, scriptId: scriptId, expected: expected
        )
        pendingAddress = nil
        pendingName = nil
        pendingSpeakersExpected = nil
        pendingScriptId = nil
        pendingKioskGuests = []
        // Dev-mode override (Debug only) lets the user run faster snapshot
        // ticks at a friends-and-family test gathering — see DevMode.swift.
        // Falls back to the production schedule on release builds and when
        // the toggle is off.
        var schedule = SessionStore.liveSnapshotSchedule
        #if DEBUG
        if let dev = DevSettings.shared.snapshotScheduleOverride {
            schedule = dev
        }
        #endif
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
                    name: nickname,
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
        stopLiveCheckInPolling()
        // Prefer the stashed setup args (set by startLiveSnapshotLoop) so the
        // final tick has the same context the periodic ticks ran with. Fall
        // back to pending* on the off chance End fires without the loop ever
        // having started.
        let address = liveSnapshotAddress ?? pendingAddress
        let nickname = liveSnapshotName ?? pendingName
        let expected = liveSnapshotExpected ?? pendingSpeakersExpected
        let scriptId = liveSnapshotScriptId ?? pendingScriptId ?? defaultScriptId
        let guests = liveSnapshotGuests.isEmpty ? pendingKioskGuests : liveSnapshotGuests
        pendingAddress = nil
        pendingName = nil
        pendingSpeakersExpected = nil
        pendingScriptId = nil
        pendingKioskGuests = []
        liveSnapshotAddress = nil
        liveSnapshotName = nil
        liveSnapshotExpected = nil
        liveSnapshotScriptId = nil
        liveSnapshotGuests = []
        // Show the processing pane immediately so the agent knows the final
        // pass is in flight; the snapshot tick replaces `phase` with .ready
        // (or .failed) when it returns.
        phase = .processing
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            await self?.snapshotTick(
                address: address,
                name: nickname,
                expected: expected,
                scriptId: scriptId,
                guests: guests,
                depth: .full,
                isFinal: true
            )
        }
    }

    // ============================================================
    // Live companion — second-device coaching view
    // ============================================================


    // Polls GET /sessions/{id} every 3s. When session.pendingCheckInId is
    // non-nil and differs from the last id we acted on, kick a snapshot
    // tagged with that id — the backend will stamp it onto last_check_in_id
    // when the pipeline finishes, which the companion's polling loop uses
    // to unblock its "Listening…" spinner.
    private func startLiveCheckInPolling(sessionId: String) {
        liveCheckInPollTask?.cancel()
        // Seed lastHandled with whatever the session already has so a
        // re-mint mid-session doesn't re-fire an old request.
        lastHandledCheckInId = session?.lastCheckInId ?? session?.pendingCheckInId
        liveCheckInPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                if Task.isCancelled { return }
                guard let self else { return }
                // Skip while a snapshot is already running — the cadence
                // loop or End-Session may be mid-tick, and we don't want
                // to pile on. We'll see the same pendingCheckInId on the
                // next poll and act then.
                if await MainActor.run(body: { self.liveSnapshotInFlight }) {
                    continue
                }
                let fresh: Session?
                do {
                    fresh = try await APIClient.shared.getSession(id: sessionId)
                } catch {
                    // Transient — try again next tick.
                    continue
                }
                guard let s = fresh,
                      let pending = s.pendingCheckInId,
                      !pending.isEmpty,
                      pending != self.lastHandledCheckInId
                else { continue }
                let address = await MainActor.run { self.liveSnapshotAddress ?? self.pendingAddress }
                let nickname = await MainActor.run { self.liveSnapshotName ?? self.pendingName }
                let expected = await MainActor.run { self.liveSnapshotExpected ?? self.pendingSpeakersExpected }
                let scriptId = await MainActor.run {
                    self.liveSnapshotScriptId ?? self.pendingScriptId ?? self.defaultScriptId
                }
                let guests = await MainActor.run {
                    self.liveSnapshotGuests.isEmpty ? self.pendingKioskGuests : self.liveSnapshotGuests
                }
                await MainActor.run { self.lastHandledCheckInId = pending }
                await self.snapshotTick(
                    address: address,
                    name: nickname,
                    expected: expected,
                    scriptId: scriptId,
                    guests: guests,
                    depth: .light,
                    isFinal: false,
                    checkInId: pending
                )
            }
        }
    }

    private func stopLiveCheckInPolling() {
        liveCheckInPollTask?.cancel()
        liveCheckInPollTask = nil
        lastHandledCheckInId = nil
    }

    // Dev/test hook — fires one snapshot tick at full depth without ending
    // the session, so the agent can see what the analysis would look like
    // mid-recording. Returns immediately if a tick is already in flight
    // (the cadence loop or a previous manual trigger); the recording itself
    // keeps capturing audio throughout via rotateChunk().
    func triggerSnapshotNow() {
        guard !liveSnapshotInFlight else { return }
        let address = liveSnapshotAddress ?? pendingAddress
        let nickname = liveSnapshotName ?? pendingName
        let expected = liveSnapshotExpected ?? pendingSpeakersExpected
        let scriptId = liveSnapshotScriptId ?? pendingScriptId ?? defaultScriptId
        let guests = liveSnapshotGuests.isEmpty ? pendingKioskGuests : liveSnapshotGuests
        Task { [weak self] in
            await self?.snapshotTick(
                address: address,
                name: nickname,
                expected: expected,
                scriptId: scriptId,
                guests: guests,
                depth: .full,
                isFinal: false
            )
        }
    }

    // One snapshot pass — rotate to a fresh chunk, concat everything so
    // far, upload. Idempotent against being called from the cadence loop
    // (light) or the End-Session hook (full).
    //
    // `checkInId` is set when this tick is fulfilling a companion check-in
    // request — the backend stamps it onto session.last_check_in_id when
    // _process finishes so the companion's polling loop unblocks.
    private func snapshotTick(
        address: String?,
        name: String?,
        expected: Int?,
        scriptId: String?,
        guests: [VisitorInput],
        depth: APIClient.AnalysisDepth,
        isFinal: Bool = false,
        checkInId: String? = nil
    ) async {
        // Skip the periodic cadence tick while the user has muted the
        // mic — the audio hasn't changed, so re-running the pipeline
        // would just burn AssemblyAI + Claude calls on the same content.
        // Companion check-ins (checkInId != nil) and the final End-Session
        // tick (isFinal=true) still go through: both are explicit user
        // requests and should produce a fresh result either way.
        if !isFinal, checkInId == nil,
           await MainActor.run(body: { AudioRecorder.shared.isPaused }) {
            return
        }
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
                    sessionId: id, audioURL: concatURL, depth: depth,
                    speakersExpected: expected, checkInId: checkInId
                )
                let final = try await APIClient.shared.pollUntilDone(id: id)
                await MainActor.run {
                    self.session = final
                    self.liveLastSnapshotAt = Date()
                    self.touchInFlightSnapshotAt()
                    if isFinal {
                        self.phase = (final.status == "error")
                            ? .failed(final.error ?? "Unknown error")
                            : .ready
                        if final.status != "error" { self.markInFlightCleanlyEnded() }
                    }
                }
            } else {
                // First tick — creates the session via the existing
                // /sessions endpoint (which always does full analysis on
                // the first pass). Subsequent ticks then run as light.
                let initial: Session
                if guests.isEmpty {
                    initial = try await APIClient.shared.createSession(
                        audioURL: concatURL, address: address, name: name,
                        speakersExpected: expected, scriptId: scriptId
                    )
                } else {
                    initial = try await APIClient.shared.createSession(
                        audioURL: concatURL, address: address, name: name, visitors: guests,
                        speakersExpected: expected, scriptId: scriptId
                    )
                }
                await MainActor.run {
                    self.session = initial
                    self.updateInFlightBackendId(initial.id)
                }
                let final = try await APIClient.shared.pollUntilDone(id: initial.id)
                await MainActor.run {
                    self.session = final
                    self.liveLastSnapshotAt = Date()
                    self.touchInFlightSnapshotAt()
                    if isFinal {
                        self.phase = (final.status == "error")
                            ? .failed(final.error ?? "Unknown error")
                            : .ready
                        if final.status != "error" { self.markInFlightCleanlyEnded() }
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
            if let data = try? JSONEncoder().encode(items) {
                UserDefaults.standard.set(data, forKey: Self.pastSessionsCacheKey)
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

    // Re-run analysis on the current session's saved audio. Two callers:
    // - Summary's "Re-analyze with N guests" control passes a count to fix
    //   diarization undercounts.
    // - Error-state "Re-analyze" passes nil to retry without a hint (lets
    //   the backend's auto-correct logic re-do its thing — usually enough
    //   to clear a transient LLM-shaped failure).
    //
    // `guestsExpected` is what the agent thinks in (number of OTHER people
    // in the room). AssemblyAI's API counts the agent too, so we add 1 on
    // the way out — set guestsExpected=2 → speakers_expected=3 → AAI looks
    // for agent + 2 guests.
    func reanalyze(guestsExpected: Int?) {
        guard let sessionId = session?.id else { return }
        cancel()
        phase = .processing
        let totalSpeakers = guestsExpected.map { $0 + 1 }
        if let g = guestsExpected, let total = totalSpeakers {
            Log.net("reanalyze → \(sessionId) guests=\(g) (total speakers=\(total))")
        } else {
            Log.net("reanalyze → \(sessionId) (no speaker hint)")
        }
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
        stopLiveCheckInPolling()
        session = nil
        phase = .idle
        pendingAddress = nil
        pendingName = nil
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

    // Update the session's agent-set nickname. Optimistic: applies locally
    // first (so SummaryView re-renders immediately), then PATCHes the
    // backend in the background. Rolls back on failure.
    func renameSession(id: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored: String? = trimmed.isEmpty ? nil : trimmed
        let priorOnSession = session?.name
        let priorOnList = pastSessions.first(where: { $0.id == id })?.name
        if session?.id == id { session?.name = stored }
        if let idx = pastSessions.firstIndex(where: { $0.id == id }) {
            pastSessions[idx].name = stored
        }
        Task { [weak self] in
            do {
                try await APIClient.shared.renameSession(id: id, name: trimmed)
            } catch {
                Log.warn("renameSession failed: \(error.localizedDescription)")
                await MainActor.run {
                    if self?.session?.id == id { self?.session?.name = priorOnSession }
                    if let idx = self?.pastSessions.firstIndex(where: { $0.id == id }) {
                        self?.pastSessions[idx].name = priorOnList
                    }
                }
            }
        }
    }

    // ============================================================
    // In-flight recording persistence + recovery + continue-recording
    // ============================================================

    // Public entry point used by the iPhone LiveView the moment recording
    // starts, so the Home-tab "Unfinished recording" banner can catch a
    // crash or upload timeout. The iPad's startLiveSnapshotLoop writes its
    // own InFlightRecording — this is the equivalent for the iPhone path
    // (which uses uploadAndProcess at End Session instead of the snapshot
    // loop).
    func noteRecordingStartedForRecovery() {
        writeInFlightRecord(
            address: pendingAddress,
            name: pendingName,
            scriptId: pendingScriptId ?? defaultScriptId,
            expected: pendingSpeakersExpected
        )
    }

    private func writeInFlightRecord(
        address: String?, name: String?, scriptId: String?, expected: Int?
    ) {
        guard let dir = AudioRecorder.shared.chunksDirectoryName else { return }
        let record = InFlightRecording(
            localChunksDirName: dir,
            backendSessionId: nil,
            name: name,
            address: address,
            scriptId: scriptId,
            expectedSpeakers: expected,
            startedAt: Date(),
            cleanlyEnded: false,
            lastSnapshotAt: nil
        )
        Self.saveInFlight(record)
    }

    fileprivate func updateInFlightBackendId(_ id: String) {
        guard var record = Self.loadInFlight(), record.backendSessionId == nil else { return }
        record.backendSessionId = id
        Self.saveInFlight(record)
    }

    fileprivate func touchInFlightSnapshotAt() {
        guard var record = Self.loadInFlight() else { return }
        record.lastSnapshotAt = Date()
        Self.saveInFlight(record)
    }

    fileprivate func markInFlightCleanlyEnded() {
        guard var record = Self.loadInFlight() else { return }
        record.cleanlyEnded = true
        Self.saveInFlight(record)
    }

    // Called on app launch to surface a crashed recording in the Home-tab
    // banner. We treat any record where cleanlyEnded=false as recoverable;
    // the iPhone uploadAndProcess path that doesn't use the snapshot loop
    // never writes a record, so we won't false-positive there.
    func scanForUnfinishedRecording() {
        guard let record = Self.loadInFlight() else { return }
        guard !record.cleanlyEnded else { return }
        let dir = AudioRecorder.recordingsDirectory
            .appendingPathComponent(record.localChunksDirName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: dir.path) else {
            Self.clearInFlight()
            return
        }
        let chunks = AudioRecorder.scanChunks(in: dir)
        guard !chunks.isEmpty else {
            // Crash before the very first chunk finalized — nothing usable
            // on disk, drop the record so we don't haunt the user forever.
            Self.clearInFlight()
            return
        }
        unfinishedRecording = record
    }

    // Tapping "Recover" on the banner: rebuild AudioRecorder's chunk list
    // from disk, fire one final full-depth snapshot, transition into the
    // Summary view so the agent can review whatever audio made it through
    // the last rotation. Doesn't resume capture.
    func recoverUnfinishedRecording() {
        guard let record = unfinishedRecording else { return }
        unfinishedRecording = nil
        let dir = AudioRecorder.recordingsDirectory
            .appendingPathComponent(record.localChunksDirName, isDirectory: true)
        let chunks = AudioRecorder.scanChunks(in: dir)
        guard !chunks.isEmpty else { Self.clearInFlight(); return }

        AudioRecorder.shared.adoptExistingChunks(dir: dir, urls: chunks)

        if let id = record.backendSessionId {
            session = Session(
                id: id, status: "processing", address: record.address, name: record.name,
                createdAt: nil, completedAt: nil, error: nil, result: nil,
                isLive: nil, lastSnapshotAt: nil,
                pendingCheckInId: nil, lastCheckInId: nil,
                homeownerEmail: nil, homeownerName: nil, report: nil, reportMeta: nil,
                latitude: nil, longitude: nil, weather: nil
            )
        } else {
            session = nil
        }
        phase = .processing
        pollTask?.cancel()
        let address = record.address
        let nickname = record.name
        let expected = record.expectedSpeakers
        let scriptId = record.scriptId
        pollTask = Task { [weak self] in
            await self?.snapshotTick(
                address: address, name: nickname, expected: expected,
                scriptId: scriptId, guests: [], depth: .full, isFinal: true
            )
        }
    }

    // Dismiss the banner without uploading. The local chunks stay on disk
    // (the agent can still pull them via Files.app), but the record is
    // cleared so the banner doesn't reappear.
    func dismissUnfinishedRecording() {
        unfinishedRecording = nil
        Self.clearInFlight()
    }

    // ============================================================
    // Recover-from-on-device-chunks (failed-session affordance)
    // ============================================================
    //
    // Used by the session-detail screen when the live snapshot loop
    // permanently errored out — typically because concatenatedURL() failed
    // mid-session and the final tick never produced a usable upload. We let
    // the agent pick the on-disk recording folder that corresponds to the
    // failing session and re-run one full-depth snapshot from it. Mirrors
    // recoverUnfinishedRecording but doesn't require an InFlightRecording —
    // the agent points us at the folder directly.

    struct LocalRecordingInfo: Identifiable, Hashable {
        let id: String      // directory name — unique
        let url: URL
        let chunkCount: Int
        let totalBytes: Int64
        let modifiedAt: Date?
    }

    // Scan Documents/Recordings/ and return every folder that contains at
    // least one chunk_NNN.m4a. Sorted newest-first by directory mtime so the
    // most-recent (likely matching) recording surfaces at the top of the
    // picker. Cheap enough to call on sheet presentation.
    func listLocalRecordings() -> [LocalRecordingInfo] {
        let fm = FileManager.default
        let root = AudioRecorder.recordingsDirectory
        let entries = (try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey]
        )) ?? []
        var out: [LocalRecordingInfo] = []
        for url in entries {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let chunks = AudioRecorder.scanChunks(in: url)
            guard !chunks.isEmpty else { continue }
            let totalBytes: Int64 = chunks.reduce(0) { acc, u in
                let size = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return acc + Int64(size)
            }
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                .flatMap { $0 }
            out.append(LocalRecordingInfo(
                id: url.lastPathComponent, url: url,
                chunkCount: chunks.count, totalBytes: totalBytes, modifiedAt: mtime
            ))
        }
        return out.sorted { (a, b) in
            (a.modifiedAt ?? .distantPast) > (b.modifiedAt ?? .distantPast)
        }
    }

    // Re-attach a local chunks directory and upload it as a brand-new
    // session. Used by the Home "Local recordings" picker — surfaces every
    // recording on disk regardless of whether an InFlightRecording or a
    // backend session ever existed for it. The agent picks one, we adopt
    // the chunks, route through snapshotTick (which POSTs /sessions when
    // session is nil), and transition into the standard processing flow.
    func uploadLocalRecording(at dirURL: URL, address: String?, name: String?) {
        guard !liveSnapshotInFlight else { return }
        let chunks = AudioRecorder.scanChunks(in: dirURL)
        guard !chunks.isEmpty else {
            liveSnapshotError = "No chunk files found in \(dirURL.lastPathComponent)."
            return
        }
        AudioRecorder.shared.adoptExistingChunks(dir: dirURL, urls: chunks)

        session = nil
        phase = .processing
        liveSnapshotError = nil
        pollTask?.cancel()
        let addr = address
        let nick = name
        let script = defaultScriptId
        pollTask = Task { [weak self] in
            await self?.snapshotTick(
                address: addr, name: nick, expected: nil,
                scriptId: script, guests: [], depth: .full, isFinal: true
            )
        }
    }

    // Re-attach `dirURL`'s chunks to AudioRecorder, then fire one full-depth
    // final snapshot tick against the existing backend session. After the
    // tick returns the session re-renders with the real audio + analysis.
    // Idempotent against being called twice — guarded by liveSnapshotInFlight.
    func recoverFromLocalChunks(sessionId: String, dirURL: URL) {
        guard !liveSnapshotInFlight else { return }
        let chunks = AudioRecorder.scanChunks(in: dirURL)
        guard !chunks.isEmpty else {
            liveSnapshotError = "No chunk files found in \(dirURL.lastPathComponent)."
            return
        }
        AudioRecorder.shared.adoptExistingChunks(dir: dirURL, urls: chunks)

        // Stub the session so snapshotTick routes to /snapshot (replace)
        // rather than POST /sessions (create new). Filled in properly when
        // the tick returns.
        session = Session(
            id: sessionId, status: "processing", address: nil, name: nil,
            createdAt: nil, completedAt: nil, error: nil, result: nil,
            isLive: nil, lastSnapshotAt: nil,
            pendingCheckInId: nil, lastCheckInId: nil,
            homeownerEmail: nil, homeownerName: nil, report: nil, reportMeta: nil,
            latitude: nil, longitude: nil, weather: nil
        )
        phase = .processing
        liveSnapshotError = nil
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            await self?.snapshotTick(
                address: nil, name: nil, expected: nil,
                scriptId: nil, guests: [], depth: .full, isFinal: true
            )
        }
    }

    // Tapping "Continue recording" on a past session. Resumes capture into
    // the same chunks dir + same backend session, so the next snapshot tick
    // uploads the full concatenated audio (old + new) and the backend
    // re-runs diarization across everything — visitors stay deduped.
    //
    // If the local chunks dir is gone (different device, manual cleanup),
    // we seed a single chunk_000.m4a from `/sessions/{id}/audio` before
    // starting recording, so the upload archive still contains the prior
    // session's audio.
    func continueRecording(sessionId: String, address: String?, name: String?, scriptId: String?) async throws {
        cancel()
        liveSnapshotTask?.cancel()
        liveSnapshotTask = nil

        let record = Self.loadInFlight()
        let dir: URL
        if let r = record, r.backendSessionId == sessionId,
           FileManager.default.fileExists(atPath: AudioRecorder.recordingsDirectory
            .appendingPathComponent(r.localChunksDirName, isDirectory: true).path) {
            dir = AudioRecorder.recordingsDirectory
                .appendingPathComponent(r.localChunksDirName, isDirectory: true)
        } else {
            // No usable local chunks — fetch the backend's audio and seed
            // chunk_000.m4a so concat-and-upload still includes prior audio.
            dir = AudioRecorder.recordingsDirectory
                .appendingPathComponent("Resumed_\(sessionId)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if AudioRecorder.scanChunks(in: dir).isEmpty {
                let audioReq = APIClient.shared.audioFetchRequest(sessionId: sessionId)
                let (data, _) = try await URLSession.shared.data(for: audioReq)
                let seed = dir.appendingPathComponent("chunk_000.m4a")
                try data.write(to: seed)
            }
        }

        pendingAddress = address
        pendingName = name
        pendingScriptId = scriptId
        pendingSpeakersExpected = nil
        pendingKioskGuests = []
        // Stub a Session so snapshotTick routes to /snapshot rather than
        // POST /sessions. Filled in properly when the first tick returns.
        session = Session(
            id: sessionId, status: "processing", address: address, name: name,
            createdAt: nil, completedAt: nil, error: nil, result: nil,
            isLive: nil, lastSnapshotAt: nil,
            pendingCheckInId: nil, lastCheckInId: nil,
            homeownerEmail: nil, homeownerName: nil, report: nil, reportMeta: nil,
            latitude: nil, longitude: nil, weather: nil
        )
        phase = .idle

        try AudioRecorder.shared.startRecording(address: address, resumingFrom: dir)
        startLiveSnapshotLoop()
    }

    // MARK: – InFlightRecording UserDefaults helpers

    fileprivate static func saveInFlight(_ record: InFlightRecording) {
        if let data = try? JSONEncoder().encode(record) {
            UserDefaults.standard.set(data, forKey: inFlightRecordingKey)
        }
    }

    fileprivate static func loadInFlight() -> InFlightRecording? {
        guard let data = UserDefaults.standard.data(forKey: inFlightRecordingKey) else { return nil }
        return try? JSONDecoder().decode(InFlightRecording.self, from: data)
    }

    fileprivate static func clearInFlight() {
        UserDefaults.standard.removeObject(forKey: inFlightRecordingKey)
    }
}
