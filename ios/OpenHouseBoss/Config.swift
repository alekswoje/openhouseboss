import Foundation

// Where the iOS app sends recorded audio and polls for session results.
//
//  • DEBUG builds (running from Xcode) → localhost. The Mac runs the FastAPI
//    server with `uvicorn backend.server:app --reload`. Simulator hits it
//    via 127.0.0.1; for a real iPhone on the same Wi-Fi, swap to your Mac's
//    LAN IP (System Settings → Network → Wi-Fi → Details → IP Address).
//
//  • RELEASE builds (TestFlight, App Store) → deployed Render URL. Replace
//    the placeholder below once `render.yaml` has been deployed and you
//    have the real URL (it'll look like https://<service>.onrender.com).
enum Config {
#if DEBUG
    static let backendURL = URL(string: "http://127.0.0.1:8000")!
#else
    static let backendURL = URL(string: "https://openhouseboss-api.onrender.com")!
#endif
}
