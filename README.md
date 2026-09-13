# Apple TV Hub

A native **SwiftUI tvOS app** built specifically for Apple TV. It combines live sports scores, Colorado weather, and remote-controlled arcade games in one TV-first interface.

## What is included

### Sports

- NFL
- NBA
- NHL
- MLB
- Live / scheduled / final game status
- Team names, logos, records, and scores
- One concurrent four-league load when Sports first opens
- Adaptive near-real-time refresh after the initial load
- Only the league currently being viewed is auto-refreshed
- Manual refresh with duplicate-request protection
- Last-updated time and visible refresh cadence
- Previous successful scoreboard remains visible if a refresh fails
- Selected league persists between launches

Sports data is loaded from ESPN's public site scoreboard endpoints. No API key is required.

### Efficient sports refresh strategy

The app deliberately avoids polling all four leagues every few seconds.

| State of selected league | Approximate automatic refresh |
|---|---:|
| Game live | 20 seconds |
| Game starts within 15 minutes | 1 minute |
| Game starts within 3 hours | 2 minutes |
| Scheduled within 24 hours | 5 minutes |
| Idle / all games final | 15 minutes |

Additional safeguards:

- Automatic polling stops when the app is not active.
- Only the visible league is polled after the initial four-league load.
- Overlapping requests for the same league are blocked.
- Manual refreshes have a short cooldown so repeated remote clicks cannot hammer the API.
- Transient failures retry once with a short delay.
- Failed refreshes do not erase the last successful data.

This keeps live scores close to real time while keeping request volume small.

### Weather

- Current temperature
- Feels-like temperature
- Humidity
- Wind speed
- Weather-condition icon and description
- Next 12 hours
- Precipitation probability
- 7-day high/low forecast
- Parker, Denver, Colorado Springs, and Fort Collins presets
- Selected location persists between launches
- Forecast times are interpreted in the **selected forecast location's timezone**, not the Apple TV's local timezone
- Array-length safety prevents malformed API responses from causing index errors
- Automatic refresh approximately every 15 minutes while the app is active
- Previous successful forecast remains visible if a refresh fails

Weather is loaded from Open-Meteo. No API key is required.

### Arcade

Three native tvOS games are included:

| Game | Siri Remote controls |
|---|---|
| Pong | Left / Right moves the paddle; Play/Pause pauses |
| Snake | D-pad changes direction; Play/Pause pauses |
| Breakout | Left / Right moves the paddle; Play/Pause pauses |

Arcade improvements include:

- Persistent best scores with `AppStorage`
- Frame-time-aware Pong and Breakout movement so short frame stalls do not change game speed
- Speed caps to reduce collision tunneling
- Improved Breakout side-vs-top brick collision response
- Correct Snake tail-vacating collision logic
- Proper Snake and Breakout game-over / win screens with focused restart buttons
- Arcade games run completely offline

### tvOS branding

The project includes native tvOS brand assets:

- Layered Home Screen app icon
- Layered App Store icon stack
- Standard Top Shelf artwork
- Wide Top Shelf artwork

The asset catalog is included in the Xcode target's Resources phase and configured as the primary app icon source.

## Requirements

- A Mac capable of running Xcode
- Xcode with the tvOS SDK installed
- An Apple ID signed into Xcode
- Apple TV hardware **or** the Apple TV Simulator

You do **not** need to publish this app to the App Store to run it on your own Apple TV. Xcode can install a development build directly on a paired device.

## Clone and open

```bash
git clone https://github.com/sportomax1/appletv.git
cd appletv
open AppleTVHub.xcodeproj
```

If you already cloned it:

```bash
cd ~/Documents/GitHub/appletv
git pull origin main
open AppleTVHub.xcodeproj
```

## Run in the Apple TV Simulator

1. Open `AppleTVHub.xcodeproj`.
2. Select the **AppleTVHub** target/scheme.
3. Choose an Apple TV Simulator from Xcode's run-destination menu.
4. Press **⌘R**.

No signing setup is normally required for the simulator.

## Run on a physical Apple TV

### 1. Pair the Apple TV with Xcode

On the Apple TV:

1. Make sure the Apple TV and Mac are on the same network.
2. Open **Settings → Remotes and Devices → Remote App and Devices**.
3. Leave that screen open while pairing.

On the Mac in current Xcode versions:

1. Open Xcode.
2. Open **Device Hub** using **Xcode → Open Developer Tool → Device Hub**, or choose **Manage Devices…** from the run-destination menu.
3. Click **+ → Pair Nearby Device…** if the Apple TV is not already shown.
4. Select Apple TV and follow the pairing prompts.
5. Enter the PIN displayed on the television when requested.

Older Xcode releases may expose equivalent controls under **Window → Devices and Simulators**.

**tvOS does not require the separate Developer Mode toggle used by iPhone/iPad.** Pair the Apple TV through Xcode/Device Hub; developer settings become available as needed.

For wireless pairing, Apple currently recommends that the Mac and Apple TV be on the same network and that the network support IPv6.

### 2. Configure signing

In Xcode:

1. Select the **AppleTVHub** project.
2. Select the **AppleTVHub** target.
3. Open **Signing & Capabilities**.
4. Leave **Automatically manage signing** enabled.
5. Select your Apple development team.

The default bundle identifier is:

```text
com.sportomax.AppleTVHub
```

Change it if your developer account requires a different unique identifier.

### 3. Install

1. Choose the paired Apple TV as the run destination.
2. Press **⌘R**.
3. Xcode builds, signs, installs, and launches the app directly on the Apple TV.

This development workflow does not require App Store submission or App Review.

## Command-line build checks

Debug:

```bash
xcodebuild \
  -project AppleTVHub.xcodeproj \
  -target AppleTVHub \
  -sdk appletvsimulator \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Release:

```bash
xcodebuild \
  -project AppleTVHub.xcodeproj \
  -target AppleTVHub \
  -sdk appletvsimulator \
  -configuration Release \
  CODE_SIGNING_ALLOWED=NO \
  build
```

GitHub Actions runs both simulator builds on pushes and pull requests:

```text
.github/workflows/tvos-build.yml
```

The CI build also forces Xcode to compile the asset catalog, so malformed tvOS icon / Top Shelf assets fail the build instead of going unnoticed.

## Project structure

```text
appletv/
├── .github/
│   └── workflows/
│       └── tvos-build.yml
├── AppleTVHub.xcodeproj/
│   └── project.pbxproj
├── AppleTVHub/
│   ├── AppleTVHubApp.swift
│   ├── ContentView.swift
│   ├── Assets.xcassets/
│   │   └── App Icon.brandassets/
│   ├── Models/
│   │   └── Models.swift
│   ├── Services/
│   │   └── Services.swift
│   └── Features/
│       ├── Sports/
│       │   └── SportsView.swift
│       ├── Weather/
│       │   └── WeatherView.swift
│       └── Arcade/
│           ├── ArcadeView.swift
│           ├── PongGameView.swift
│           ├── SnakeGameView.swift
│           └── BreakoutGameView.swift
├── .gitignore
└── README.md
```

## Architecture

- `ContentView` owns the three top-level tabs.
- `SportsViewModel` performs the initial four-league load and adaptive selected-league polling.
- `WeatherViewModel` manages persisted location selection and Open-Meteo refreshes.
- Networking uses native `URLSession` and `async/await`.
- Transient network failures receive one controlled retry instead of unbounded retry loops.
- Siri Remote game movement uses SwiftUI's native `onMoveCommand`, with `onPlayPauseCommand` for pause/resume.
- High scores and lightweight user choices use `AppStorage` / `UserDefaults`.
- There are no third-party Swift packages and no stored API secrets.

## Adding another sport

Add a case to `SportsLeague` in `Models.swift`, then provide its ESPN endpoint path and SF Symbol. The existing initial-load, selected-league refresh, and UI logic will pick it up automatically through `SportsLeague.allCases`.

Example:

```swift
case collegeFootball = "NCAAF"
```

Then map it to an endpoint such as `football/college-football` in `endpointPath`.

## Adding another weather location

Add another `WeatherLocation` to `WeatherLocation.presets` in `Models.swift` with a name, latitude, and longitude. It automatically appears in the location selector and can be persisted as the selected location.

## Adding another arcade game

1. Create a SwiftUI game view under `AppleTVHub/Features/Arcade/`.
2. Add the file to the Xcode project's Sources build phase.
3. Add another `gameCard(...)` entry in `ArcadeView.swift`.
4. Prefer `.onMoveCommand` for D-pad/Siri Remote navigation and `.onPlayPauseCommand` for pausing.
5. Use `AppStorage` for scores/settings that should survive relaunches.

## Troubleshooting

### Apple TV does not appear in Xcode

- Confirm the Mac and Apple TV are on the same network.
- Confirm IPv6 is available on the local network for wireless tvOS pairing.
- Reopen **Settings → Remotes and Devices → Remote App and Devices** on Apple TV.
- Reopen **Device Hub** and try **Pair Nearby Device…**.
- Restart the Apple TV if pairing discovery remains stuck.

### Signing error

Open **Signing & Capabilities**, select your Team, and make sure the bundle identifier is unique for that team.

### Sports or weather is blank

The live sections require internet access. Use Refresh and confirm the Apple TV or simulator can reach the internet. If a later refresh fails, the last successful data remains on screen with a stale-data warning. Arcade games are independent of network access.

### Simulator build from Terminal

Run the Debug or Release command above. Both bypass code signing and are useful for finding Swift, project, and asset-catalog errors.

## Data-provider note

Open-Meteo is used for weather. Sports currently uses ESPN's public site scoreboard endpoints, which are convenient and key-free but are not a formally versioned public developer API. The app keeps the sports networking isolated in `SportsService` so the provider can be replaced without rewriting the UI.

## Distribution

This repo is designed first for personal/development installation through Xcode. If you later want public distribution, the same native tvOS project can be prepared for App Store Connect, TestFlight, screenshots, privacy metadata, and App Review.
