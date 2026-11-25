// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "slack-remote",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "slack-remote", targets: ["slack-remote"]),
        .executable(name: "SlackRemoteHelper", targets: ["SlackRemoteHelper"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "SlackRemoteCore", linkerSettings: [
            .linkedFramework("ApplicationServices"),
            .linkedFramework("AppKit"),
            .linkedFramework("CoreGraphics"),
            .linkedFramework("Security"),
        ]),
        .executableTarget(name: "slack-remote", dependencies: [
            "SlackRemoteCore",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]),
        .executableTarget(name: "SlackRemoteHelper", dependencies: ["SlackRemoteCore"], linkerSettings: [
            .linkedFramework("AppKit"),
            .linkedFramework("ServiceManagement"),
        ]),
        .testTarget(name: "SlackRemoteCoreTests", dependencies: ["SlackRemoteCore"]),
    ],
    swiftLanguageModes: [.v5]
)
