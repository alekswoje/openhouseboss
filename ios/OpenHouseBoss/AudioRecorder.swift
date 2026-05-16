import ActivityKit
import AVFoundation
import Foundation
import Observation
import UIKit

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

        // Drive the elapsed counter + waveform meter from a single 6 Hz tick.
        let t = Timer.scheduledTimer(withTimeInterval: 0.16, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.startTime else { return }
                // Subtract paused time so the displayed timer reflects
                // actual captured audio, not wall-clock seconds.
                let wall = Date().timeIntervalSince(start)
                self.elapsed = wall - self.pausedAccumulated
                    - (self.pauseStart.map { Date().timeIntervalSince($0) } ?? 0)
                self.sampleMeter()
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
        recorder?.record()
        if let start = pauseStart {
            pausedAccumulated += Date().timeIntervalSince(start)
        }
        pauseStart = nil
        isPaused = false
        updateLiveActivityMute(false)
    }

    // Push the current mute state into the Live Activity so the widget's
    // Mute / Unmute button label tracks reality. Phase stays .recording —
    // muting doesn't end the session, just stops mic capture.
    private func updateLiveActivityMute(_ muted: Bool) {
        guard #available(iOS 16.2, *), let activity = liveActivity else { return }
        let newState = RecordingActivityAttributes.ContentState(
            startedAt: activity.content.state.startedAt,
            phase: activity.content.state.phase,
            isMuted: muted
        )
        Task {
            await activity.update(ActivityContent(state: newState, staleDate: nil))
        }
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
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
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
        ) else { return nil }
        var cursor = CMTime.zero
        for url in chunks {
            let asset = AVURLAsset(url: url)
            guard let assetTrack = try? await asset.loadTracks(withMediaType: .audio).first
            else { continue }
            let duration = (try? await asset.load(.duration)) ?? .zero
            let range = CMTimeRange(start: .zero, duration: duration)
            do {
                try track.insertTimeRange(range, of: assetTrack, at: cursor)
                cursor = CMTimeAdd(cursor, duration)
            } catch {
                Log.warn("concatenatedURL insert failed: \(error.localizedDescription)")
            }
        }

        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapshot_\(UUID().uuidString).m4a")
        try? FileManager.default.removeItem(at: out)
        guard let export = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else { return nil }
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
                    Log.warn("concatenatedURL export failed: \(export.error?.localizedDescription ?? "unknown")")
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
