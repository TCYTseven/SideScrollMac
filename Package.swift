// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SideScroll",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "SideScroll", targets: ["SideScroll"]),
    ],
    targets: [
        // Pure model + layout logic. No AppKit, so it is unit-testable.
        .target(name: "SideScrollCore", path: "Sources/SideScrollCore"),
        // Thin C bridge to the private MultitouchSupport framework (trackpad swipes).
        .target(name: "CMultitouch", path: "Sources/CMultitouch"),
        .executableTarget(
            name: "SideScroll",
            dependencies: ["SideScrollCore", "CMultitouch"],
            path: "Sources/SideScroll",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI"),
            ]
        ),
        .testTarget(
            name: "SideScrollCoreTests",
            dependencies: ["SideScrollCore"],
            path: "Tests/SideScrollCoreTests"
        ),
    ]
)
