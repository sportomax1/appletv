# Apple TV Hub

Native SwiftUI app for **tvOS** with live sports scores, weather, and remote-controlled arcade games.

## Included

- **Sports** — NFL, NBA, NHL, and MLB scoreboards using ESPN's public scoreboard endpoints.
- **Weather** — current conditions, hourly forecast, and 7-day forecast using Open-Meteo. Includes Colorado location presets.
- **Arcade** — Pong, Snake, and Breakout built natively in SwiftUI for the Siri Remote.
- **tvOS-first UI** — focusable controls, large cards, readable 10-foot layout, and directional remote input.

## Run it

```bash
git clone https://github.com/sportomax1/appletv.git
cd appletv
open AppleTVHub.xcodeproj
```

Then in Xcode:

1. Select the **AppleTVHub** scheme.
2. Choose an Apple TV Simulator, or pair/select your physical Apple TV.
3. For a physical device, select your development team under **Signing & Capabilities**.
4. Press **Run** (`⌘R`).

No App Store submission is required to run your own development build on your Apple TV.

## Controls

| Area | Siri Remote |
|---|---|
| App navigation | Directional pad / swipe + Select |
| Pong | Left / Right moves paddle; Play/Pause pauses |
| Snake | D-pad changes direction; Play/Pause pauses |
| Breakout | Left / Right moves paddle; Play/Pause pauses |

## Data sources

The app does not require API keys.

- Sports: ESPN public site API scoreboard endpoints
- Weather: Open-Meteo

## Project layout

```text
AppleTVHub/
├── AppleTVHubApp.swift
├── ContentView.swift
├── Models/
├── Services/
├── Features/
│   ├── Sports/
│   ├── Weather/
│   └── Arcade/
└── UI/
```

## Notes

This project is intended for personal/development use. Public App Store distribution may require additional branding, privacy disclosures, testing, and review.
