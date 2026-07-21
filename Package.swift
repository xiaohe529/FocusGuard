// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FocusGuard",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "FocusGuardHelperShared",
            path: "Sources/FocusGuardHelperShared"
        ),
        .executableTarget(
            name: "FocusGuardHelper",
            dependencies: ["FocusGuardHelperShared"],
            path: "Sources/FocusGuardHelper"
        ),
        .executableTarget(
            name: "FocusGuard",
            dependencies: ["FocusGuardHelperShared"],
            path: "Sources/FocusGuard",
            exclude: ["Info.plist"]
        )
    ]
)
