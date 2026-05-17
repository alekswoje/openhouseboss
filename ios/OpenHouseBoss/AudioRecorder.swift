import ActivityKit
import AVFoundation
import Foundation
import Observation
import UIKit
import UserNotifications

@MainActor
@Observable
final class AudioRecorder {
    // Shared instance used by the iPad surface so the recording survives
    // tab switches (and the agent can launch the kiosk in parallel without
    // losing the in-progress recording). The iPhone LiveView still creates
    // its own @State recorder so the two flows stay independent.
    static let shared = AudioRecorder()

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var startTime: Date?
    // Held so the OS doesn't suspend recording while the user is on another
    // screen / phone is locked. Released in stopRecording().
    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    // Live Activity handle — shown on the Lock Screen + Dynamic Island
    // while recording. The Stop button on the activity fires
    // StopRecordingIntent, which writes the bridge sentinel; the activity
    // itself is started in startRecording and ended in stopRecording.
    private var liveActivity: Activity<RecordingActivityAttributes>?

    // Chunked-recording bookkeeping. Each chunk is its own AVAudioRecorder
    // file inside a session-specific subdirectory; we rotate to a new chunk
    // every snapshot tick so the iPad can ship the finalized prefix audio
    // mid-session without waiting for the agent to End Session. On final
    // stop we keep every chunk on disk so the master recording is the
    // concat of them all.
    private(set) var chunkURLs: [URL] = []
    private var chunksDirectory: URL?
    private var chunkIndex: Int = 0
    private var settings: [String: Any] = [:]

    var isRecording = false
    var isPaused = false
    var recordingURL: URL?
    var elapsed: TimeInterval = 0
    // Total time spent paused — subtracted from the wall-clock elapsed so
    // the displayed timer matches actual recorded audio.
    private var pausedAccumulated: TimeInterval = 0
    private var pauseStart: Date?
    // Rolling window of normalized 0..1 amplitudes for the live waveform.
    var levels: [Float] = Array(repeating: 0, count: 52)

    // Set to true when AVAudioSession sends an interruption (incoming call,
    // Siri, another audio app like Spotify grabbing the mic) OR when the
    // bytes-written watchdog detects the active chunk has stopped growing
    // despite us thinking we're recording. Drives the orange "INTERRUPTED"
    // treatment in the Live Activity and the in-app banner. Cleared on
    // successful auto-resume (or on the next tick where bytes flow again).
    var isStalled: Bool = false
    // One-line reason for the stall, shown inline in the in-app banner so
    // the agent knows what to do (e.g. "Spotify took the mic — close Spotify
    // and tap Resume").
    var stallReason: String?

    // Bytes-written watchdog. Every tick we record the active chunk's size +
    // when we saw it; if `stallTimeout` elapses without growth (while not
    // explicitly paused), we flag the recording as stalled and fire a local
    // notification + Live Activity warning so the agent finds out before
    // the entire open house is over.
    private var lastObservedBytes: UInt64 = 0
    private var lastBytesChangedAt: Date?
    private let stallTimeout: TimeInterval = 60
    // Cached interruption observer so we can remove it cleanly on stop.
    private var interruptionObserver: NSObjectProtocol?

    // Documents/Recordings — persists across launches, visible in the Files
    // app + via Finder (with UIFileSharingEnabled). Lets us pull .m4a files
    // off the device to re-test the backend pipeline on the same audio.
    static var recordingsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    // Start a fresh recording. Pass `resumingFrom` to continue into an
    // existing chunks directory (used by crash recovery + Continue recording
    // on past sessions) — chunkIndex picks up past any chunk_NNN.m4a already
    // on disk so the new audio appends to the prior session's archive.
    func startRecording(address: String? = nil, resumingFrom existingDir: URL? = nil) throws {
        let session = AVAudioSession.sharedInstance()
        // .record (not .playAndRecord) keeps the mic active when the screen
        // locks; combined with `UIBackgroundModes: ["audio"]` in Info.plist
        // the recorder keeps running while the app is backgrounded.
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)

        // Each recording gets its own chunks directory so rotations don't
        // collide across sessions. The session-display URL points at the
        // first chunk to start with; concatenatedURL() builds the full file
        // on demand for upload.
        let dir: URL
        if let existingDir {
            try? FileManager.default.createDirectory(at: existingDir, withIntermediateDirectories: true)
            dir = existingDir
            chunkURLs = AudioRecorder.scanChunks(in: dir)
            // Next chunk index = max existing chunk's index + 1. -1 sentinel
            // for an empty dir gives a starting index of 0.
            chunkIndex = (chunkURLs.compactMap { Self.chunkNumber(from: $0) }.max() ?? -1) + 1
        } else {
            let sessionId = filenameForNow()  // doubles as a unique session prefix
            dir = AudioRecorder.recordingsDirectory
                .appendingPathComponent(sessionId, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            chunkURLs = []
            chunkIndex = 0
        }
        chunksDirectory = dir

        settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let firstURL = dir.appendingPathComponent(String(format: "chunk_%03d.m4a", chunkIndex))
        let r = try AVAudioRecorder(url: firstURL, settings: settings)
        r.isMeteringEnabled = true
        r.record()
        recorder = r
        recordingURL = firstURL
        isRecording = true
        startTime = Date()
        elapsed = 0
        levels = Array(repeating: 0, count: levels.count)
        isStalled = false
        stallReason = nil
        lastObservedBytes = 0
        lastBytesChangedAt = Date()

        // Begin a background task to defer suspension when the user
        // backgrounds the app — the audio entitlement does the heavy lifting
        // for staying alive while locked; this is belt-and-suspenders.
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "OpenHouseBoss.Recording") { [weak self] in
            // Expiration handler — best-effort flush; the audio mode keeps
            // the actual recorder running.
            guard let self else { return }
            UIApplication.shared.endBackgroundTask(self.bgTask)
            self.bgTask = .invalid
        }

        pausedAccumulated = 0
        pauseStart = nil
        isPaused = false

        // Listen for AVAudioSession interruptions (incoming call, Siri,
        // Spotify/another app grabbing the mic). Without this, AVAudioRecorder
        // gets paused by iOS on .began and never auto-resumes on .ended,
        // leaving us with a "recording" that captures no audio for hours.
        // This is the exact failure mode that lost a 3hr open house once.
        installInterruptionObserver()
        // Ask up-front so the stalled-recording notification can actually
        // break through if it fires later. No-op if already authorized.
        requestNotificationAuthorization()

        // Drive the elapsed counter + waveform meter + bytes watchdog from a
        // single 6 Hz tick. The watchdog only runs once per second internally
        // to avoid hammering the filesystem at 6 Hz.
        let t = Timer.scheduledTimer(withTimeInterval: 0.16, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.startTime else { return }
                // Subtract paused time so the displayed timer reflects
                // actual captured audio, not wall-clock seconds.
                let wall = Date().timeIntervalSince(start)
                self.elapsed = wall - self.pausedAccumulated
                    - (self.pauseStart.map { Date().timeIntervalSince($0) } ?? 0)
                self.sampleMeter()
                self.tickBytesWatchdog()
            }
        }
        // Allow the timer to fire while the app is in a tracking run-loop
        // mode (e.g. user is scrolling). Common runloop covers backgrounded
        // operation as long as the audio session keeps us alive.
        RunLoop.current.add(t, forMode: .common)
        timer = t

        // Clear any stale stop signal from a previous session before we
        // start polling for new presses. Without this, a leftover sentinel
        // file would immediately end the new recording.
        LiveActivityBridge.clearStopSignal()
        startLiveActivity(address: address ?? "")
    }

    // Start the Lock Screen / Dynamic Island Live Activity. Quietly does
    // nothing on iOS < 16.2 or if the user has Live Activities disabled
    // for the app — the in-app LiveSessionBar still works as a stop
    // surface in that case.
    private func startLiveActivity(address: String) {
        guard #available(iOS 16.2, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = RecordingActivityAttributes(address: address)
        let initialState = RecordingActivityAttributes.ContentState(
            startedAt: startTime ?? Date(),
            phase: .recording
        )
        let content = ActivityContent(state: initialState, staleDate: nil)
        do {
            liveActivity = try Activity<RecordingActivityAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            Log.warn("Live Activity start failed: \(error.localizedDescription)")
        }
    }

    private func endLiveActivity() {
        Task { [activity = liveActivity] in
            guard let activity else { return }
            if #available(iOS 16.2, *) {
                let finalState = RecordingActivityAttributes.ContentState(
                    startedAt: activity.content.state.startedAt,
                    phase: .processing
                )
                await activity.end(
                    ActivityContent(state: finalState, staleDate: nil),
                    dismissalPolicy: .after(Date().addingTimeInterval(2))
                )
            } else {
                await activity.end(dismissalPolicy: .immediate)
            }
        }
        liveActivity = nil
    }

    private func sampleMeter() {
        guard let r = recorder else { return }
        r.updateMeters()
        let db = r.peakPower(forChannel: 0)
        let clamped = max(-50, db)
        let norm = Float((clamped + 50) / 50)
        levels.removeFirst()
        levels.append(norm)
    }

    // Actually pause the AVAudioRecorder so resumed audio is contiguous in
    // the same .m4a — the iPhone + iPad UI both call this when the user
    // taps the Pause button. Pausing also stops the meter so the waveform
    // doesn't show false-positive bars while we're not capturing.
    func pause() {
        guard isRecording, !isPaused else { return }
        recorder?.pause()
        isPaused = true
        pauseStart = Date()
        updateLiveActivityMute(true)
    }

    func resume() {
        guard isRecording, isPaused else { return }
        // Reactivate the session in case it was interrupted while we were
        // paused (e.g. user muted, Spotify took over, user closed Spotify
        // and tapped Unmute). Without this, record() returns false because
        // the session isn't ours anymore.
        try? AVAudioSession.sharedInstance().setActive(true)
        recorder?.record()
        if let start = pauseStart {
            pausedAccumulated += Date().timeIntervalSince(start)
        }
        pauseStart = nil
        isPaused = false
        isStalled = false
        stallReason = nil
        lastObservedBytes = currentChunkBytes() ?? 0
        lastBytesChangedAt = Date()
        updateLiveActivityMute(false)
        cancelStalledNotification()
    }

    // Explicit "Resume mic" — called from the in-app stalled banner when
    // the recorder hasn't actually been muted by the user but iOS killed
    // mic capture out from under us (an interruption that didn't send
    // `.shouldResume`, or a watchdog-detected stall). Re-grabs the audio
    // session and pokes the recorder. Idempotent if we're already healthy.
    func attemptUnstall() {
        guard isRecording else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            stallReason = "Couldn't reclaim the mic. Close any other audio app, then try again."
            return
        }
        // If the user was muted, don't unmute on their behalf — they
        // chose mute deliberately.
        if isPaused {
            isStalled = false
            stallReason = nil
            pushLiveActivityState(isMuted: true, isStalled: false)
            cancelStalledNotification()
            return
        }
        _ = recorder?.record()
        isStalled = false
        stallReason = nil
        lastObservedBytes = currentChunkBytes() ?? 0
        lastBytesChangedAt = Date()
        pushLiveActivityState(isMuted: false, isStalled: false)
        cancelStalledNotification()
    }

    // Push the current mute state into the Live Activity so the widget's
    // Mute / Unmute button label tracks reality. Phase stays .recording —
    // muting doesn't end the session, just stops mic capture.
    private func updateLiveActivityMute(_ muted: Bool) {
        pushLiveActivityState(isMuted: muted, isStalled: isStalled)
    }

    // Generalized Live Activity state push — used by the mute toggle, the
    // interruption observer, and the bytes-written watchdog so the widget
    // always sees a coherent snapshot. The phase is preserved (only the
    // recording → processing transition uses endLiveActivity).
    private func pushLiveActivityState(isMuted: Bool, isStalled: Bool) {
        guard #available(iOS 16.2, *), let activity = liveActivity else { return }
        let newState = RecordingActivityAttributes.ContentState(
            startedAt: activity.content.state.startedAt,
            phase: activity.content.state.phase,
            isMuted: isMuted,
            isStalled: isStalled
        )
        Task {
            await activity.update(ActivityContent(state: newState, staleDate: nil))
        }
    }

    // ============================================================
    // Audio-session interruption handling
    // ============================================================
    //
    // iOS suspends mic capture whenever something else needs the audio
    // session: incoming call, Siri activation, another app starting
    // playback (Spotify, music app, AirPods auto-pause/swap, even briefly
    // pulling up Control Center on some configurations). The default
    // AVAudioRecorder behavior is "pause but don't resume" — without this
    // handler, the recorder dies the first time the user fires up Spotify
    // and never comes back, even after the interruption ends.
    //
    // On .began: mark the recording as stalled, push the warning state to
    // the Live Activity, fire a local notification so the agent finds out
    // before the open house is over.
    // On .ended with `.shouldResume`: re-activate the audio session and
    // call recorder.record() to pick up where we left off.

    private func installInterruptionObserver() {
        let center = NotificationCenter.default
        interruptionObserver = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in self?.handleInterruption(note) }
        }
    }

    private func removeInterruptionObserver() {
        if let obs = interruptionObserver {
            NotificationCenter.default.removeObserver(obs)
            interruptionObserver = nil
        }
    }

    private func handleInterruption(_ note: Notification) {
        guard
            let info = note.userInfo,
            let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeRaw)
        else { return }
        switch type {
        case .began:
            Log.warn("audio interrupted — another app/system took the session (Spotify, Siri, call, etc.)")
            isStalled = true
            stallReason = "Another app or call took the mic. Recording is paused."
            pushLiveActivityState(isMuted: isPaused, isStalled: true)
            scheduleStalledNotification(
                title: "Recording interrupted",
                body: "Another app took the mic (Spotify, a phone call, or Siri). Open the app to resume capture."
            )
        case .ended:
            let options: AVAudioSession.InterruptionOptions
            if let raw = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                options = AVAudioSession.InterruptionOptions(rawValue: raw)
            } else {
                options = []
            }
            let shouldResume = options.contains(.shouldResume)
            Log.net("audio interruption ended (shouldResume=\(shouldResume))")
            if shouldResume {
                attemptResumeAfterInterruption()
            } else {
                // The interrupter (e.g. Spotify) is still active — we'll
                // stay flagged as stalled until the user manually taps
                // Resume in the app, which clears the other app's hold.
                stallReason = "Recording is paused. Close the other audio app, then tap Resume."
            }
        @unknown default:
            break
        }
    }

    private func attemptResumeAfterInterruption() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            Log.warn("setActive after interruption failed: \(error.localizedDescription)")
            stallReason = "Couldn't reactivate the mic. Open the app and tap Resume."
            return
        }
        // If the user explicitly muted before the interruption, respect that
        // and don't auto-record over their choice — they have to tap Resume.
        if isPaused {
            isStalled = false
            stallReason = nil
            pushLiveActivityState(isMuted: true, isStalled: false)
            cancelStalledNotification()
            return
        }
        if recorder?.record() == true {
            isStalled = false
            stallReason = nil
            lastObservedBytes = currentChunkBytes() ?? 0
            lastBytesChangedAt = Date()
            pushLiveActivityState(isMuted: false, isStalled: false)
            cancelStalledNotification()
            Log.net("auto-resumed recording after interruption")
        } else {
            Log.warn("recorder.record() returned false after interruption")
            stallReason = "Couldn't auto-resume the mic. Open the app and tap Resume."
        }
    }

    // ============================================================
    // Bytes-written watchdog
    // ============================================================
    //
    // The interruption observer catches the common case (Spotify, calls,
    // Siri), but iOS doesn't always send a notification — e.g. a dropped
    // Bluetooth headset, an audio route change, or an interruption from
    // another app that doesn't actually deactivate our session. Belt-and-
    // suspenders: every second while not paused, check that the active
    // chunk's file size is still growing. If it hasn't grown in 60s, the
    // recorder is dead even though it doesn't know it.

    private func tickBytesWatchdog() {
        guard isRecording, !isPaused else {
            // Reset the baseline whenever we're explicitly paused — coming
            // back from pause shouldn't immediately trip the watchdog.
            if isPaused {
                lastObservedBytes = currentChunkBytes() ?? 0
                lastBytesChangedAt = Date()
            }
            return
        }
        // Cheap once-per-second rate limiter; the parent timer fires at 6Hz.
        if let last = lastBytesChangedAt, Date().timeIntervalSince(last) < 1 { return }
        let now = Date()
        guard let bytes = currentChunkBytes() else { return }
        if bytes != lastObservedBytes {
            lastObservedBytes = bytes
            lastBytesChangedAt = now
            // First growth after a stall confirms the resume actually
            // worked — clear the flag.
            if isStalled {
                isStalled = false
                stallReason = nil
                pushLiveActivityState(isMuted: isPaused, isStalled: false)
                cancelStalledNotification()
            }
            return
        }
        // No growth — has it been long enough to declare a stall?
        guard let lastChange = lastBytesChangedAt else {
            lastBytesChangedAt = now
            return
        }
        if isStalled { return } // already flagged
        if now.timeIntervalSince(lastChange) >= stallTimeout {
            Log.warn("bytes-written watchdog: chunk hasn't grown in \(Int(stallTimeout))s — recorder is silently stalled")
            isStalled = true
            stallReason = "Microphone stopped capturing audio. Open the app to check."
            pushLiveActivityState(isMuted: isPaused, isStalled: true)
            scheduleStalledNotification(
                title: "Recording stopped",
                body: "The mic stopped capturing audio. Open the app to check."
            )
        }
    }

    private func currentChunkBytes() -> UInt64? {
        guard let url = recorder?.url else { return nil }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.size] as? UInt64
    }

    // ============================================================
    // Local notifications for silent-failure visibility
    // ============================================================

    private static let stalledNotificationId = "openhousecopilot.recording.stalled"

    private func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func scheduleStalledNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let req = UNNotificationRequest(
            identifier: Self.stalledNotificationId, content: content, trigger: trigger
        )
        UNUserNotificationCenter.current().add(req) { err in
            if let err {
                Log.warn("stalled notification add failed: \(err.localizedDescription)")
            }
        }
    }

    private func cancelStalledNotification() {
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: [Self.stalledNotificationId]
        )
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [Self.stalledNotificationId]
        )
    }

    func stopRecording() -> URL? {
        recorder?.stop()
        // Add the just-finalized chunk to the list so concatenatedURL()
        // builds the full archive.
        if let url = recorder?.url, !chunkURLs.contains(url) {
            chunkURLs.append(url)
        }
        timer?.invalidate()
        timer = nil
        isRecording = false
        isStalled = false
        stallReason = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
        removeInterruptionObserver()
        cancelStalledNotification()
        endLiveActivity()
        LiveActivityBridge.clearStopSignal()
        return recordingURL
    }

    // Rotate to a fresh chunk file without breaking the recording. Stops
    // the current AVAudioRecorder (which finalizes the m4a — the moov atom
    // is written, so it becomes playable / transcribable), then immediately
    // starts a new one writing into the next chunk file. Returns the
    // finalized chunk URL so callers can upload + concat it.
    //
    // There IS a brief gap (~50-100ms) between stop and the new start where
    // audio isn't captured. Acceptable for the snapshot use case — open
    // houses don't pivot on a hundred-millisecond gap every 5-10 minutes.
    func rotateChunk() -> URL? {
        guard isRecording, let dir = chunksDirectory else { return nil }
        recorder?.stop()
        if let url = recorder?.url, !chunkURLs.contains(url) {
            chunkURLs.append(url)
        }
        let finalized = recorder?.url
        chunkIndex += 1
        let nextURL = dir.appendingPathComponent(String(format: "chunk_%03d.m4a", chunkIndex))
        do {
            let r = try AVAudioRecorder(url: nextURL, settings: settings)
            r.isMeteringEnabled = true
            r.record()
            recorder = r
            recordingURL = nextURL
        } catch {
            Log.warn("rotateChunk failed to start next chunk: \(error.localizedDescription)")
        }
        return finalized
    }

    // Concatenate every chunk recorded so far (plus the live one if we can
    // safely re-read it — we copy then move on) into a single m4a suitable
    // for upload. Uses AVMutableComposition / AVAssetExportSession so we
    // don't need to ship ffmpeg. The caller is responsible for deleting the
    // returned temp file.
    func concatenatedURL() async -> URL? {
        let chunks = chunkURLs
        guard !chunks.isEmpty else { return nil }
        // Single chunk shortcut — just copy the file. Spinning up an export
        // session for one input is wasted work.
        if chunks.count == 1 {
            let out = FileManager.default.temporaryDirectory
                .appendingPathComponent("snapshot_\(UUID().uuidString).m4a")
            do {
                try? FileManager.default.removeItem(at: out)
                try FileManager.default.copyItem(at: chunks[0], to: out)
                return out
            } catch {
                Log.warn("concatenatedURL copy failed: \(error.localizedDescription)")
                return nil
            }
        }

        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            Log.warn("concatenatedURL: addMutableTrack returned nil for \(chunks.count) chunks")
            return nil
        }
        var cursor = CMTime.zero
        var insertedCount = 0
        for url in chunks {
            let asset = AVURLAsset(url: url)
            let assetTrack: AVAssetTrack?
            do {
                assetTrack = try await asset.loadTracks(withMediaType: .audio).first
            } catch {
                Log.warn("concatenatedURL: loadTracks failed for \(url.lastPathComponent): \(error.localizedDescription)")
                continue
            }
            guard let assetTrack else {
                Log.warn("concatenatedURL: no audio track in \(url.lastPathComponent)")
                continue
            }
            let duration = (try? await asset.load(.duration)) ?? .zero
            guard duration.isValid, duration.value > 0 else {
                Log.warn("concatenatedURL: zero/invalid duration for \(url.lastPathComponent) — skipped")
                continue
            }
            let range = CMTimeRange(start: .zero, duration: duration)
            do {
                try track.insertTimeRange(range, of: assetTrack, at: cursor)
                cursor = CMTimeAdd(cursor, duration)
                insertedCount += 1
            } catch {
                Log.warn("concatenatedURL: insertTimeRange failed for \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        guard insertedCount > 0 else {
            Log.warn("concatenatedURL: no usable chunks out of \(chunks.count) — every chunk had no audio track or zero duration")
            return nil
        }

        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapshot_\(UUID().uuidString).m4a")
        try? FileManager.default.removeItem(at: out)
        guard let export = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            Log.warn("concatenatedURL: AVAssetExportSession init returned nil")
            return nil
        }
        export.outputURL = out
        export.outputFileType = .m4a
        // AVFoundation 18 (iOS 18+) added an async export API. We're targeting
        // iOS 17 minimums, so fall back to the deprecated completion handler
        // wrapped in a CheckedContinuation.
        return await withCheckedContinuation { cont in
            export.exportAsynchronously {
                if export.status == .completed {
                    cont.resume(returning: out)
                } else {
                    let nsErr = export.error as NSError?
                    Log.warn("concatenatedURL: export \(export.status.rawValue) — \(nsErr?.localizedDescription ?? "no error") (domain=\(nsErr?.domain ?? "?"), code=\(nsErr?.code ?? -1), chunks=\(insertedCount)/\(chunks.count))")
                    cont.resume(returning: nil)
                }
            }
        }
    }

    private func filenameForNow() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "OpenHouse_\(f.string(from: Date())).m4a"
    }

    // Last-path-component of the active chunks directory — used by the
    // SessionStore in-flight record so a relaunch can re-resolve the dir
    // under Documents/Recordings without trusting an absolute path (the
    // app container path changes between installs).
    var chunksDirectoryName: String? {
        chunksDirectory?.lastPathComponent
    }

    // Wire AudioRecorder up to an existing chunks dir without starting a
    // new recording. Used by crash recovery — caller wants the recorder's
    // chunkURLs populated so concatenatedURL() can build a single m4a
    // from what's on disk, then upload + finalize the session.
    func adoptExistingChunks(dir: URL, urls: [URL]) {
        chunksDirectory = dir
        chunkURLs = urls
        chunkIndex = (urls.compactMap { Self.chunkNumber(from: $0) }.max() ?? -1) + 1
    }

    // Scan a chunks directory for finalized chunk_NNN.m4a files, sorted by
    // numeric index. Used on resume (continue recording / crash recovery) to
    // pick up where rotation left off and rebuild the upload archive.
    static func scanChunks(in dir: URL) -> [URL] {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let chunks = urls.filter {
            $0.pathExtension.lowercased() == "m4a"
                && $0.lastPathComponent.hasPrefix("chunk_")
        }
        return chunks.sorted { lhs, rhs in
            (chunkNumber(from: lhs) ?? -1) < (chunkNumber(from: rhs) ?? -1)
        }
    }

    static func chunkNumber(from url: URL) -> Int? {
        let stem = url.deletingPathExtension().lastPathComponent  // "chunk_007"
        let parts = stem.split(separator: "_")
        guard parts.count == 2 else { return nil }
        return Int(parts[1])
    }
}
