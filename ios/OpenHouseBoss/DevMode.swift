import Foundation
import Observation
import SwiftUI

// ============================================================
// Dev-mode tooling
// ============================================================
//
// Pre-launch testing knobs that should NEVER ship to end users. The whole
// file is wrapped in #if DEBUG so the release build doesn't include any of
// it — when we're ready to launch, delete this file + the call sites
// flagged with `#if DEBUG` and the app behaves like a stock release build.
//
// Current knobs:
//   - fasterSnapshots: forces the live-recording loop to fire snapshots
//     every 60 seconds instead of the production 5/10/20/30/… cadence,
//     so a 5-minute test recording at a gathering gives 4–5 snapshot
//     passes instead of just one. Burns provider credits faster — that's
//     the point, we want to exercise the loop.
//
// The settings live in UserDefaults under foyer.dev.* keys so flipping
// them across launches sticks without rebuilding.

#if DEBUG

@MainActor
@Observable
final class DevSettings {
    static let shared = DevSettings()

    private init() {
        self.fasterSnapshots = UserDefaults.standard.bool(forKey: Self.kFasterSnapshots)
    }

    private static let kFasterSnapshots = "foyer.dev.fasterSnapshots"

    var fasterSnapshots: Bool {
        didSet { UserDefaults.standard.set(fasterSnapshots, forKey: Self.kFasterSnapshots) }
    }

    // Whether ANY dev-mode flag is currently on. Drives the "DEV" pill on
    // the recording header so the agent doesn't accidentally run dev mode
    // during a real open house.
    var anyEnabled: Bool { fasterSnapshots }

    // Snapshot cadence override. Returns nil when dev mode is off so the
    // production schedule runs as-is.
    var snapshotScheduleOverride: [TimeInterval]? {
        guard fasterSnapshots else { return nil }
        // 1-minute ticks for the first 20 minutes — plenty to exercise the
        // loop at a friends-and-family test session.
        return Array(repeating: 60, count: 20)
    }
}

#endif
