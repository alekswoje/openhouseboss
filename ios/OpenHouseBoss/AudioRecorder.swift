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

    func startRecording(address: String? = nil) throws {
        let session = AVAudioSession.sharedInstance()
        // .record (not .playAndRecord) keeps the mic active when the screen
        // locks; combined with `UIBackgroundModes: ["audio"]` in Info.plist
        // the recorder keeps running while the app is backgrounded.
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)

        let filename = filenameForNow()
        let url = AudioRecorder.recordingsDirectory.appendingPathComponent(filename)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let r = try AVAudioRecorder(url: url, settings: settings)
        r.isMeteringEnabled = true
        r.record()
        recorder = r
        recordingURL = url
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
    }

    func resume() {
        guard isRecording, isPaused else { return }
        recorder?.record()
        if let start = pauseStart {
            pausedAccumulated += Date().timeIntervalSince(start)
        }
        pauseStart = nil
        isPaused = false
    }

    func stopRecording() -> URL? {
        recorder?.stop()
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

    private func filenameForNow() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "OpenHouse_\(f.string(from: Date())).m4a"
    }
}
