import Foundation

// Where the iOS app sends recorded audio and polls for session results.
//
// Points at the branded api.openhousecopilot.com (CNAME → the Render
// service). Using the branded domain also makes the iOS
// ASWebAuthenticationSession dialog say "Wants to Use
// 'openhousecopilot.com' to Sign In" instead of leaking the Render
// hostname to users.
//
// To go back to local dev, flip the #if DEBUG branch to a localhost or
// LAN-IP URL temporarily.
enum Config {
    static let backendURL = URL(string: "https://api.openhousecopilot.com")!
}
