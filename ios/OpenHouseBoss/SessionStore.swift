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

    var phase: Phase = .idle
    var session: Session?
    // Compact list shown on the home screen. Refreshed lazily.
    var pastSessions: [SessionSummary] = []
    var listLoading = false
    var listError: String?
    // Address typed in SetupView, used by uploadAndProcess.
    var pendingAddress: String?
    // Local m4a from the last recording — kept so SummaryView can offer
    // playback for QA-ing mic placement. Cleared on reset.
    var lastRecordedAudioURL: URL?

    private var pollTask: Task<Void, Never>?

    // Called from LiveView on End session. Uploads the m4a, then polls until
    // the backend either finishes processing or errors out.
    func uploadAndProcess(audioURL: URL) {
        cancel()
        phase = .uploading
        session = nil
        lastRecordedAudioURL = audioURL
        let address = pendingAddress
        pendingAddress = nil
        Log.net("uploadAndProcess → \(audioURL.lastPathComponent), address=\(address ?? "<none>")")
        pollTask = Task { [weak self] in
            do {
                let initial = try await APIClient.shared.createSession(
                    audioURL: audioURL, address: address)
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

    func cancel() {
        pollTask?.cancel()
        pollTask = nil
    }

    func reset() {
        cancel()
        session = nil
        phase = .idle
        pendingAddress = nil
        lastRecordedAudioURL = nil
    }
}
