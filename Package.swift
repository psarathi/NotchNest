// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchNest",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "NotchNestCore",
            targets: ["NotchNestCore"]
        ),
        .executable(
            name: "NotchNest",
            targets: ["NotchNest"]
        )
    ],
    targets: [
        .target(
            name: "NotchNestCore",
            path: "Sources/NotchNestCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("EventKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("MapKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Speech"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("Vision")
            ]
        ),
        .executableTarget(
            name: "NotchNest",
            dependencies: ["NotchNestCore"],
            path: "Sources/NotchNest",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Quartz"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UserNotifications")
            ]
        ),
        .testTarget(
            name: "NotchNestTests",
            dependencies: ["NotchNestCore"],
            path: "Tests/NotchNestTests"
        )
    ]
)
