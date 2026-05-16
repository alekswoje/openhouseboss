import AppIntents
import Foundation

// Tapped from the Live Activity (lock screen or Dynamic Island) to mute /
// unmute the in-progress recording without ending it. Same pattern as
// StopRecordingIntent: LiveActivityIntent runs in the host app's process so
// the NotificationCenter post below reaches the app's observers directly.
@available(iOS 17.0, *)
struct ToggleMuteIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Toggle mute"
    static var description = IntentDescription("Mute or unmute the in-progress open-house recording.")

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .openhousebossToggleMute,
                object: nil
            )
        }
        return .result()
    }
}

extension Notification.Name {
    // Posted by ToggleMuteIntent (in the app's process) and observed by the
    // app to flip AudioRecorder.shared between paused and recording.
    static let openhousebossToggleMute = Notification.Name("openhouseboss.toggleMute")
}
