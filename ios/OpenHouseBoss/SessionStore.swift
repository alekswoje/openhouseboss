import Foundation
import Observation

// Shared session store — drives the live → upload → poll → results flow.
// LiveView writes the recording URL when the user taps End session.
// SummaryView reads the latest Session and polls until ready / error.
@MainActor
@Observable
final class SessionStore {
    enum Phase: Equatable {
        case idle
        case uploading       // POSTing the audio
        case processing      // backend is transcribing + analyzing
        case ready
        case failed(String)
    }

    static let shared = SessionStore()

    var phase: Phase = .idle
    var session: Session?
    private var pollTask: Task<Void, Never>?

    // Called from LiveView on End session. Uploads the m4a, then polls until
    // the backend either finishes processing or errors out.
    func uploadAndProcess(audioURL: URL) {
        cancel()
        phase = .uploading
        session = nil
        pollTask = Task { [weak self] in
            do {
                let initial = try await APIClient.shared.createSession(audioURL: audioURL)
                await MainActor.run {
                    self?.session = initial
                    self?.phase = .processing
                }
                let final = try await APIClient.shared.pollUntilDone(id: initial.id)
                await MainActor.run {
                    self?.session = final
                    if final.status == "error" {
                        self?.phase = .failed(final.error ?? "Unknown error")
                    } else {
                        self?.phase = .ready
                    }
                }
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
    }
}
