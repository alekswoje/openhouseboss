# iOS app setup

The Xcode project is already generated at `ios/OpenHouseCopilot.xcodeproj`. Mic permission, ATS, and bundle ID are pre-configured. You just need to finish Xcode's first-run setup, then press ⌘R.

## One-time: finish Xcode first-launch

Xcode hasn't installed its simulator runtime yet. Either approach works:

**Option A (GUI):** Open `Xcode.app` from Applications. A dialog will say "Install additional components" → click Install → enter your Mac password → wait a few minutes.

**Option B (terminal):** `sudo xcodebuild -runFirstLaunch` (will prompt for your password).

## Run on the simulator

1. Start the backend in one terminal:
   ```
   cd ~/OpenHouseCopilot
   source .venv/bin/activate
   uvicorn backend.server:app --reload --host 0.0.0.0
   ```
2. Open the project:
   ```
   open ~/OpenHouseCopilot/ios/OpenHouseCopilot.xcodeproj
   ```
3. At the top of Xcode, pick a simulator (any iPhone 17.x), press ⌘R.
4. Tap Start Recording → speak → Stop → enter visitor names → Process. Result page appears in 30–90s.

## Run on a real iPhone

1. In Xcode → Settings → Accounts → add your Apple ID
2. Project navigator → OpenHouseCopilot target → Signing & Capabilities → set Team to your personal team
3. Edit `Config.swift` — change `127.0.0.1` to your Mac's LAN IP (System Settings → Wi-Fi → Details → IP Address). Phone + Mac must be on the same Wi-Fi.
4. Plug phone in → select it as run target → ⌘R
5. First launch: on the phone, Settings → General → VPN & Device Management → trust your developer cert

## Regenerating the project

If you edit `project.yml` (e.g. add a new dependency), run:
```
cd ~/OpenHouseCopilot/ios
xcodegen generate
```
