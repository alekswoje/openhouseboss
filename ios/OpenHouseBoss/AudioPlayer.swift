import AVFoundation
import Combine
import Foundation
import Observation

// AVPlayer-backed wrapper so SummaryView can play both the just-recorded
// local m4a AND a session's audio fetched from the backend on another
// device (record on phone → listen on iPad). AVAudioPlayer can't stream
// remote URLs, AVPlayer can.
@MainActor
@Observable
final class AudioPlayer {
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var item: AVPlayerItem?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObserver: NSKeyValueObservation?
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    var isPlaying = false
    var duration: TimeInterval = 0
    var currentTime: TimeInterval = 0
    var loadedURL: URL?

    func load(url: URL) {
        guard loadedURL != url else { return }
        teardown()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            Log.warn("AVAudioSession setup failed: \(error.localizedDescription)")
        }

        let newItem = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: newItem)
        newPlayer.automaticallyWaitsToMinimizeStalling = true
        item = newItem
        player = newPlayer
        loadedURL = url

        // Duration arrives async — observe the item's status and pull
        // duration once it's ready.
        statusObserver = newItem.observe(\.status, options: [.new, .initial]) { [weak self] obs, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if obs.status == .readyToPlay {
                    let secs = CMTimeGetSeconds(obs.duration)
                    if secs.isFinite, secs > 0 { self.duration = secs }
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: newItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isPlaying = false
                self?.player?.seek(to: .zero)
                self?.currentTime = 0
            }
        }

        timeObserver = newPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] t in
            Task { @MainActor [weak self] in
                self?.currentTime = CMTimeGetSeconds(t)
            }
        }
        Log.ui("AudioPlayer loaded \(url.lastPathComponent)")
    }

    func playPause() {
        guard player != nil else { return }
        if isPlaying { pause() } else { play() }
    }

    func play() {
        player?.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func stop() {
        player?.pause()
        player?.seek(to: .zero)
        isPlaying = false
        currentTime = 0
    }

    func seek(to t: TimeInterval) {
        let clamped = max(0, min(t, duration > 0 ? duration : t))
        player?.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        currentTime = clamped
    }

    private func teardown() {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        statusObserver?.invalidate()
        statusObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player?.pause()
        player = nil
        item = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        loadedURL = nil
    }

}
