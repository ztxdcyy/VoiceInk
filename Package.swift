// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Speakin",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Speakin",
            path: "Sources/Speakin",
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
