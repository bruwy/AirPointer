<p align="center">
  <img src="AirPointer/AirPointerIcon.icon/Assets/ChatGPT%20Image%20Jul%2029%2C%202025%2C%2012_15_52%20AM.png" alt="AirPointer app icon" width="128" height="128">
</p>

# AirPointer

Control your Mac with camera-based hand gestures. AirPointer uses Apple's Vision framework to track hands locally, then translates gestures into pointer movement, clicks and shortcuts.

This local development variant adds cursor feedback and held mouse buttons to **V4 Trackpad (0.4)**. Gesture accuracy depends on lighting, framing and hand visibility. Synthetic tests cover the command pipeline; they do not establish real-world tracking accuracy.

Licensed under the [MIT License](LICENSE). Copyright © 2025–2026 Bruno Schreiber. The original app icon is included under the same license; see [dependencies and artwork](docs/DEPENDENCIES.md).

## Requirements

- macOS 26 or later.
- Full Xcode 26 or later with Swift 6.2 or later (Command Line Tools alone are insufficient for the app and its `.icon` resource). This snapshot was validated with Xcode 27.
- A camera for live gesture tracking; Camera and Accessibility permissions for the corresponding features.
- No external packages, API keys, cloud account or paid Apple Developer membership are required for the local ad hoc build.

## Build

Open `AirPointer.xcodeproj` and select the **AirPointer** scheme, or run:

```bash
./script/build_and_run.sh --build-only
```

The script uses one build job and ad hoc signing. The app is written to `DerivedData/Build/Products/Debug/AirPointer.app`. Override that location with `AIRPOINTER_DERIVED_DATA`. If Xcode is installed under a different name or location, set `DEVELOPER_DIR` to its `Contents/Developer` directory.

To build and launch:

```bash
./script/build_and_run.sh
```

The launch modes quit any existing AirPointer process first. `--build-only` neither quits nor opens the app. Optional launch modes: `--debug`, `--logs`, `--telemetry`, `--verify` (process-presence check only). These are development builds, not notarized releases. For distribution, configure your own signing identity and notarization; no developer team or signing credentials are included.

## First use and gestures

1. Open the app and grant Camera access when you want to start tracking. Grant Accessibility access to allow pointer and keyboard actions.
2. Start with **Diagnostic only — no commands** in the gesture menu. It displays recognition states and click counters without sending mouse, keyboard or scroll events.
3. Keep your hands visible and verify that the displayed left/right sides match your physical hands. Disable diagnostic mode when ready to try commands in a safe area of the desktop.

| Left-hand gesture | Action |
| --- | --- |
| Close/relax fingers, then move the wrist | Relative pointer movement |
| Open all four fingers | Release any button, pause and reposition |
| Touch thumb to ring, with index/middle/little extended | Hold left mouse button |
| Touch thumb to middle, with index/ring/little extended | Hold middle mouse button |
| Curl four fingers and extend the thumb | Hold right mouse button |

A stable button pose presses once; holding it keeps the button down. Move the same wrist to drag and release the pose to let go. Finger changes keep the wrist/palm anchor, so movement continues while forming a button. A direct button change releases the old button before confirming the new one. Tracking loss, stop, settings/permission changes and the capture watchdog release the owned button and require neutral rearming.

In Deepwork, **thumb + index pinch remains scroll**: shift the wrist vertically for scroll or horizontally for scrub, then hold the offset to continue. Return to the pinch origin or release to stop. Scroll releases any owned mouse button before posting its first event; it never becomes a left click. Sensitivity ranges from 0.5× to 3×; the default is 1.2× and applies to the current session.

In Presentation mode, right-hand double pinch advances, and an open-hand-to-held-fist sequence goes back. The right pinky gesture invokes the configured mute shortcut. In Deepwork, right pointing drives the existing red laser and the right fist controls Play/Pause. The right hand never moves or presses the actual mouse. Shortcut behavior depends on the selected profile and foreground application; see `IntentDispatcher.swift` for mappings.

The **Gestures** switch stays visible above the camera, outside menus and scroll views. Turning it off releases any held button, cancels pending commands and hides the halo/laser without closing the app or camera preview. Its preference persists. After turning it back on, each hand must show a stable neutral pose before that hand can emit commands: relax/close or fully open the left fingers, and open the right hand. A missing or held command pose cannot rearm it. The visible gesture guide lists mouse holds, scroll and each profile’s real right-hand actions.

**Button status** stays visible beside the Gestures switch. It shows whether the left hand is tracked, whether neutral rearming is needed, which button pose is recognized, and which button was posted to macOS. Diagnostic-only mode shows recognition without sending events. Fully open, then close the left hand to rearm if a held pose is not accepted.

**Cursor readiness halo** in gesture settings enables a small, hollow ring around the actual macOS cursor. It enters briefly, then stays static while the left mouse is ready. An accepted press or discrete shortcut gives one short pulse; a thicker static ring means a button remains held. Pause, tracking expiry and stop fade it out. The right laser suppresses the ordinary ready ring, while a held button retains its thicker ring. The preference persists; Reduce Motion replaces scaling with a brief contrast change. The ring passes all clicks through and cannot take keyboard focus.

## Tests without camera or UI

`Package.swift` is a library-only test harness. It excludes the app entry point and UI and uses synthetic hand fixtures and injected action/permission doubles:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --jobs 1 --disable-index-store
```

The tests cover relative pointer movement, gesture transitions, clicks, profiles, permissions, recording serialization and command dispatch. They do not open the camera or post real input events. The previous replay test tied to a private recording is not part of this snapshot.

Xcode UI tests launch the app and may show permission prompts; they are separate from the offline command above. Live camera and physical gesture verification remain manual.

## Privacy

Camera frames are processed locally with Vision. No network service or analytics SDK is configured in this source snapshot.

**Record frames** is a separate, opt-in diagnostic feature: it saves hand joint coordinates, handedness, timing, a creation date and a profile label as `.airframes.json`, not camera images. Files are stored under `AirPointer/Recordings` inside the app's Application Support directory (inside its container for sandboxed builds). Treat these recordings as personal data and do not attach them to public issues. Diagnostic-only mode disables recording and discards an active recording when enabled.

The repository excludes recordings, local IDE state, signing material, build products and private diagnostic evidence. See [contributing](CONTRIBUTING.md) before sharing a bug report.

## Source layout

- `AirPointer/`: SwiftUI app, camera tracking, gesture engines and command dispatch.
- `AirPointer/ProductionSupport/`: permission handling.
- `AirPointerTests/`: synthetic tests used by SwiftPM and Xcode.
- `AirPointerUITests/`: Xcode UI tests.
- `script/build_and_run.sh`: local build and launch entry point.
