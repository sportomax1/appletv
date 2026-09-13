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
- Concurrent refreshes across all four leagues
- Manual refresh button and last-updated time

Sports data is loaded from ESPN's public site scoreboard endpoints. No API key is required.

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

Weather is loaded from Open-Meteo. No API key is required.

### Arcade

Three native tvOS games are included:

| Game | Siri Remote controls |
|---|---|
| Pong | Left / Right moves the paddle; Play/Pause pauses |
| Snake | D-pad changes direction; Play/Pause pauses |
| Breakout | Left / Right moves the paddle; Play/Pause pauses; Select restarts after game over/win |

The arcade games run locally and do not require internet access.

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

## Run in the Apple TV Simulator

1. Open `AppleTVHub.xcodeproj`.
2. Select the **AppleTVHub** target/scheme.
3. Choose an Apple TV Simulator from Xcode's device menu.
4. Press **⌘R**.

No signing setup is normally required for the simulator.

## Run on a physical Apple TV

### 1. Pair the Apple TV with Xcode

On the Apple TV:

1. Make sure the Apple TV and Mac are on the same network.
2. Open **Settings → Remotes and Devices → Remote App and Devices**.
3. Leave that screen open.

On the Mac:

1. Open Xcode.
2. Open **Window → Devices and Simulators**.
3. Select the Apple TV when it appears.
4. Enter the pairing code shown on the television if requested.

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

## Command-line build check

From the repository root:

```bash
xcodebuild \
  -project AppleTVHub.xcodeproj \
  -target AppleTVHub \
  -sdk appletvsimulator \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

A GitHub Actions workflow is also included at:

```text
.github/workflows/tvos-build.yml
```

It performs the same type of simulator build on a macOS runner after pushes and pull requests when GitHub Actions is enabled for the repository.

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
└── README.md
```

## Architecture

The app is intentionally simple and modular:

- `ContentView` owns the three top-level tabs.
- `SportsViewModel` loads the four ESPN scoreboards concurrently.
- `WeatherViewModel` manages the selected location and Open-Meteo forecast.
- Each arcade game is isolated in its own SwiftUI view and owns its game loop/state.
- Networking uses native `URLSession` and `async/await`.
- There are no third-party Swift packages and no stored API secrets.

## Adding another sport

Add a case to `SportsLeague` in `Models.swift`, then provide its ESPN endpoint path and SF Symbol. The existing sports service and UI will pick it up automatically through `SportsLeague.allCases`.

Example shape:

```swift
case collegeFootball = "NCAAF"
```

Then map it to an endpoint such as `football/college-football` in `endpointPath`.

## Adding another weather location

Add another `WeatherLocation` to `WeatherLocation.presets` in `Models.swift` with a name, latitude, and longitude. It will automatically appear in the location selector.

## Adding another arcade game

1. Create a new SwiftUI game view under `AppleTVHub/Features/Arcade/`.
2. Add the file to the Xcode project's Sources build phase if it is not already included.
3. Add another `gameCard(...)` entry in `ArcadeView.swift`.
4. Prefer `.onMoveCommand` for D-pad/swipe navigation and `.onPlayPauseCommand` for pausing.

## Troubleshooting

### Apple TV does not appear in Xcode

- Confirm the Mac and Apple TV are on the same network.
- Reopen **Settings → Remotes and Devices → Remote App and Devices** on Apple TV.
- Reopen Xcode's **Devices and Simulators** window.
- USB is not normally required for modern Apple TV pairing.

### Signing error

Open **Signing & Capabilities**, select your Team, and make sure the bundle identifier is unique for that team.

### Sports or weather is blank

The live sections require internet access. Use the Refresh button and confirm the Apple TV or simulator can reach the internet. Arcade games are independent of network access.

### Simulator build from Terminal

Run the command under **Command-line build check** above. It bypasses code signing and is useful for finding normal Swift compiler/project errors.

## Distribution

This repo is designed first for personal/development installation through Xcode. If you later want public distribution, the same native tvOS project can be prepared for App Store Connect, TestFlight, screenshots, privacy metadata, and App Review.
