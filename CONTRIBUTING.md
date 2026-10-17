# Working on RidePulse

## One-time setup

1. Install Xcode (iOS 17+ / watchOS 10+ SDKs) and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
   (`brew install xcodegen`, or download a release binary).
2. Generate the Xcode project — **`RidePulse.xcodeproj` is generated from `project.yml`**:
   ```
   xcodegen generate
   ```
   Re-run it whenever you add/remove source files or edit `project.yml`.
   Never hand-edit the `.xcodeproj`; changes are overwritten.
3. Open `RidePulse.xcodeproj`. For **both** the `RidePulse`, `RidePulseWidgets`
   and `RidePulseWatch` targets choose your **Team** under *Signing & Capabilities*
   (a free Apple ID works). If the bundle ID is taken, change it in `project.yml`
   (keep the watch app as `<iPhone ID>.watchkitapp` and the widget as `<iPhone ID>.widgets`).

## Running on devices

- **iPhone:** enable Developer Mode (Settings › Privacy & Security), plug in, pick the
  phone as destination, ⌘R. Trust your developer profile on first launch
  (Settings › General › VPN & Device Management).
- **Apple Watch:** Xcode must see the watch once to register it. Turn Developer Mode on
  for the watch, keep the iPhone unlocked and plugged in, and pick the watch as the
  destination of the `RidePulseWatch` scheme. A VPN (e.g. Tailscale) on the Mac or
  phone can stop the watch being discovered — disconnect it for this step.
- Free Apple IDs expire after **7 days**; re-run to refresh.

## Layout

| Path | What |
|---|---|
| `ios/` | iPhone app |
| `watchos/` | Apple Watch app |
| `widgets/` | Live Activity / Dynamic Island extension |
| `shared/` | Code compiled into both the app and the widget extension |
| `design/` | App icon generator (`make-icon.swift`) and logo |
| `project.yml` | XcodeGen spec — source of truth for targets, plist keys, entitlements |

## Conventions

- No third-party dependencies; Apple frameworks only.
- Swift 5 language mode. Match the surrounding style; keep comments for the *why*.
- Secrets (Strava client secret, Azure Speech key) are entered in the app's Settings and
  stored on the device. **Never commit keys, tokens, or your Apple Team ID.**
- Before pushing, make sure the project builds:
  ```
  xcodegen generate
  xcodebuild -project RidePulse.xcodeproj -scheme RidePulse \
    -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
  ```
  CI (`.github/workflows/build.yml`) runs this on every push and pull request.
