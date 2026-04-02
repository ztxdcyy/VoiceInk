// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Voiceink",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Voiceink",
            path: "Sources/Voiceink",
            exclude: [
                "Resources/Info.plist"
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
