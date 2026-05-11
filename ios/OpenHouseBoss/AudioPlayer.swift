import AVFoundation
import Foundation
import Observation

// Minimal AVAudioPlayer wrapper so SummaryView can let the user play back the
// just-recorded m4a — useful for checking mic placement / quality differences.
@MainActor
@Observable
final class AudioPlayer: NSObject {
    private var player: AVAudioPlayer?
    private var timer: Timer?

    var isPlaying = false
    var duration: TimeInterval = 0
    var currentTime: TimeInterval = 0

    func load(url: URL) {
        stop()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()
            player = p
            duration = p.duration
            currentTime = 0
            Log.ui("AudioPlayer loaded \(url.lastPathComponent) duration=\(Int(p.duration))s")
        } catch {
            Log.warn("AudioPlayer load failed: \(error.localizedDescription)")
            player = nil
            duration = 0
        }
    }

    func playPause() {
        guard let p = player else { return }
        if p.isPlaying { pause() } else { play() }
    }

    func play() {
        guard let p = player else { return }
        p.play()
        isPlaying = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let p = self.player else { return }
                self.currentTime = p.currentTime
            }
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        timer?.invalidate()
        timer = nil
        currentTime = 0
        duration = 0
    }

    func seek(to t: TimeInterval) {
        player?.currentTime = max(0, min(t, duration))
        currentTime = player?.currentTime ?? 0
    }
}

extension AudioPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = 0
            self.timer?.invalidate()
            self.timer = nil
        }
    }
}
