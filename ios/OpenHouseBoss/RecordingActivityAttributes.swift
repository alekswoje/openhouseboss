import ActivityKit
import Foundation

// ActivityAttributes shared by the main app and the OpenHouseBossWidgets
// extension. `address` is the static context (address of the open house),
// `ContentState` carries the live timer string + a phase flag the widget
// uses to swap between "recording" and "processing" appearance.
//
// The widget target picks this file up via project.yml's explicit source
// path — keeping the type in one place means a rename in the app stays
// in sync with the widget code that decodes it.
struct RecordingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var startedAt: Date
        var phase: Phase
        // Mic capture is paused but the session is still active. Drives the
        // widget's Mute/Unmute button label; the in-app surfaces read the
        // same flag via AudioRecorder.isPaused so the two stay in sync.
        var isMuted: Bool = false
        // Recorder is supposed to be capturing but isn't — either iOS sent
        // an AVAudioSession interruption (incoming call, Siri, another app
        // grabbing the mic like Spotify) or the bytes-written watchdog saw
        // the active chunk stop growing despite not being muted. Drives the
        // widget's orange "INTERRUPTED" treatment so the agent notices
        // without unlocking the phone.
        var isStalled: Bool = false

        enum Phase: String, Codable {
            case recording
            case processing
        }
    }

    var address: String
}

// Bridge file that the Live Activity's Stop intent writes to and that the
// main app polls. App Intents can't reach into the host app's process to
// directly call AudioRecorder.stop, so we use a sentinel file as the
// rendezvous. Both targets reference this same URL.
//
// In production this should live in an App Group's shared container (so
// the intent's sandbox can read/write the same path the app sees). Until
// that entitlement is provisioned, we fall through to the system tmp
// directory — that's enough to test the wiring locally, and works fine
// for the in-app Stop button on the LiveSessionBar.
enum LiveActivityBridge {
    static var stopSignalURL: URL {
        if let group = sharedContainerURL {
            return group.appendingPathComponent("stop_recording.signal")
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("openhouseboss_stop_recording.signal")
    }

    private static var sharedContainerURL: URL? {
        // Replace with the real App Group identifier once provisioned.
        // Returning nil from this method is intentionally OK — the tmp
        // fallback above keeps the wiring functional during development.
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.openhouseboss.app")
    }

    static func clearStopSignal() {
        try? FileManager.default.removeItem(at: stopSignalURL)
    }

    static var stopSignalPresent: Bool {
        FileManager.default.fileExists(atPath: stopSignalURL.path)
    }
}
