// swift-tools-version: 6.2
import PackageDescription

// A library-only test harness: no App entry point, live capture or UI launch.
let package = Package(
    name: "AirPointerOfflineValidation",
    platforms: [.macOS(.v26)],
    products: [.library(name: "AirPointer", targets: ["AirPointer"])],
    targets: [
        .target(
            name: "AirPointer",
            path: "AirPointer",
            exclude: ["AirPointerApp.swift", "ContentView.swift", "CameraView.swift",
                      "LaserPointerView.swift", "HandSkeletonOverlayView.swift",
                      "OverlayWindowController.swift", "CursorFeedbackWindowController.swift", "Assets.xcassets",
                      "AirPointerIcon.icon", "Info.plist"],
            swiftSettings: [.defaultIsolation(MainActor.self), .swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "AirPointerTests",
            dependencies: ["AirPointer"],
            path: "AirPointerTests",
            swiftSettings: [.defaultIsolation(MainActor.self), .swiftLanguageMode(.v5)]
        )
    ]
)
