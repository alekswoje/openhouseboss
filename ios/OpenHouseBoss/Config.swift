import Foundation

// Where the iOS app sends recorded audio and polls for session results.
//
// DEBUG builds → your Mac's LAN IP. Same Wi-Fi network required. The Mac
// runs `uvicorn backend.server:app --host 0.0.0.0 --port 8000`. If the
// simulator can't reach it, double-check macOS firewall (System Settings
// → Network → Firewall → allow incoming connections, or just turn off
// while testing). If your Wi-Fi router gives the Mac a new IP after a
// reboot, run `ipconfig getifaddr en0` and update the line below.
//
// RELEASE builds → deployed Render URL. Set this once you've finished
// deploying and have the real URL.
enum Config {
#if DEBUG
    static let backendURL = URL(string: "http://192.168.88.3:8000")!
#else
    static let backendURL = URL(string: "https://openhouseboss-api.onrender.com")!
#endif
}
