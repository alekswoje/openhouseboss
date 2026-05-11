import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class AudioRecorder {
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var startTime: Date?

    var isRecording = false
    var recordingURL: URL?
    var elapsed: TimeInterval = 0
    // Rolling window of normalized 0..1 amplitudes for the live waveform.
    var levels: [Float] = Array(repeating: 0, count: 52)

    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func startRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).m4a")

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

        // Drive the elapsed counter + waveform meter from a single 6 Hz tick.
        // 10 Hz was producing noticeable @Observable churn during recording on
        // older devices; 6 Hz is still visually smooth for the bar animation.
        let t = Timer.scheduledTimer(withTimeInterval: 0.16, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.startTime else { return }
                self.elapsed = Date().timeIntervalSince(start)
                self.sampleMeter()
            }
        }
        timer = t
    }

    // Pull the current input level (dBFS), normalize to 0..1, and slide it
    // into the rolling window so the UI can render a live waveform.
    private func sampleMeter() {
        guard let r = recorder else { return }
        r.updateMeters()
        // peakPower returns dBFS where 0 is max and -160 is silence.
        let db = r.peakPower(forChannel: 0)
        let clamped = max(-50, db)               // floor at -50dB
        let norm = Float((clamped + 50) / 50)    // → 0..1
        levels.removeFirst()
        levels.append(norm)
    }

    func stopRecording() -> URL? {
        recorder?.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)
        return recordingURL
    }
}
