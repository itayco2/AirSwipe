// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AirSwipe",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "airswipe", targets: ["airswipe"]),
    ],
    targets: [
        // Pure gesture logic: no camera, no Vision, no AppKit. Fully unit-testable.
        .target(name: "AirSwipeCore"),

        // Camera + Vision + CGEvent + menu-bar glue.
        .executableTarget(
            name: "airswipe",
            dependencies: ["AirSwipeCore"],
            linkerSettings: [
                // Embed an Info.plist so macOS can show the camera usage string
                // even though this is a bare command-line binary, not an .app.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Resources/Info.plist",
                ]),
            ]
        ),

        .testTarget(
            name: "AirSwipeCoreTests",
            dependencies: ["AirSwipeCore"]
        ),
    ]
)
