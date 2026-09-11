// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JoyConVibeRemote",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "JoyConVibeCore", targets: ["JoyConVibeCore"]),
        .executable(name: "JoyConVibeRemote", targets: ["JoyConVibeRemote"])
    ],
    targets: [
        .target(name: "JoyConVibeCore"),
        .executableTarget(
            name: "JoyConVibeRemote",
            dependencies: ["JoyConVibeCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "JoyConVibeCoreTests",
            dependencies: ["JoyConVibeCore"]
        ),
        .testTarget(
            name: "JoyConVibeRemoteTests",
            dependencies: ["JoyConVibeRemote"]
        )
    ],
    swiftLanguageModes: [.v5]
)
