import AppIntents
import Foundation

// Tapped from the Live Activity (lock screen or Dynamic Island) when the
// agent wants to end a recording without unlocking the iPad.
//
// LiveActivityIntent (iOS 17+) is the key piece here — it makes iOS run
// `perform()` inside the host app's process, not the widget extension's.
// That means the NotificationCenter post below reaches the app's
// in-memory listeners directly; no file-system bridge needed. The app
// observes `Notification.Name.openhousebossStopRecording` and calls
// AudioRecorder.shared.stopRecording() + uploadAndProcess.
//
// The type lives in the widget target's source tree but is added to the
// main app target via project.yml so both can reference the same intent.
@available(iOS 17.0, *)
struct StopRecordingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop recording"
    static var description = IntentDescription("End the in-progress open-house recording.")

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .openhousebossStopRecording,
                object: nil
            )
        }
        return .result()
    }
}

extension Notification.Name {
    // Posted by StopRecordingIntent (in the app's process, since it
    // conforms to LiveActivityIntent) and observed by the iPad app to
    // end the in-progress recording.
    static let openhousebossStopRecording = Notification.Name("openhouseboss.stopRecording")
}
