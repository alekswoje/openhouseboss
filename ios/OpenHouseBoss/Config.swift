import Foundation

// Where the iOS app sends recorded audio and polls for session results.
//
// Points at the Render deployment by default so the phone works from
// anywhere (cellular, different Wi-Fi, with the Mac off). The free tier
// sleeps after 15 min of inactivity, so the first request after idle
// takes ~30–50s to spin back up. After that it's fast.
//
// To go back to local dev, flip the #if DEBUG branch to a localhost or
// LAN-IP URL temporarily.
enum Config {
    static let backendURL = URL(string: "https://openhouseboss-api.onrender.com")!
}
