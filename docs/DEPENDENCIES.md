# Dependencies and artwork

## Code and platform dependencies

The Xcode project and SwiftPM test harness declare no third-party package dependencies. No vendored libraries, downloaded model weights, external fonts, certificates or provisioning profiles are included.

The source imports Apple platform/toolchain modules: AppKit, ApplicationServices, AVFoundation, Combine, CoreGraphics, Foundation, OSLog, SwiftUI and Vision. Tests use Testing and XCTest; Package.swift uses PackageDescription. These are provided by macOS/Xcode and are not bundled source dependencies in this repository. System symbol references are rendered through Apple APIs.

The source retains its existing author headers. AirPointer is Copyright © 2025–2026 Bruno Schreiber and is distributed under the [MIT License](../LICENSE).

## App artwork

The app uses `AirPointer/AirPointerIcon.icon`, which references `Assets/ChatGPT Image Jul 29, 2025, 12_15_52 AM.png`.

Bruno Schreiber confirmed that he created the original app icon and authorized its inclusion with the project under the MIT License. The artwork and its existing provenance metadata are preserved.

SHA-256 of the PNG: `4391a8c7bd6df84529e28dc92c426587a8df074e1abf8c1bb80212caa00ce361`.

## License

The [MIT License](../LICENSE) covers the project source, documentation and original app artwork. Apple platform components remain subject to their own terms.
