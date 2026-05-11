import AVFoundation
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class AudioRecorder {
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var startTime: Date?
    // Held so the OS doesn't suspend recording while the user is on another
    // screen / phone is locked. Released in stopRecording().
    private var bgTask: UIBackgroundTaskIdentifier = .invalid

    var isRecording = false
    var recordingURL: URL?
    var elapsed: TimeInterval = 0
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

    func startRecording() throws {
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

        // Drive the elapsed counter + waveform meter from a single 6 Hz tick.
        let t = Timer.scheduledTimer(withTimeInterval: 0.16, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.startTime else { return }
                self.elapsed = Date().timeIntervalSince(start)
                self.sampleMeter()
            }
        }
        // Allow the timer to fire while the app is in a tracking run-loop
        // mode (e.g. user is scrolling). Common runloop covers backgrounded
        // operation as long as the audio session keeps us alive.
        RunLoop.current.add(t, forMode: .common)
        timer = t
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
        return recordingURL
    }

    private func filenameForNow() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "OpenHouse_\(f.string(from: Date())).m4a"
    }
}
