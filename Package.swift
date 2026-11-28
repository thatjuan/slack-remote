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
            .linkedFramework("Security"),
        ]),
        .executableTarget(name: "slack-remote", dependencies: [
            "SlackRemoteCore",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]),
        .target(name: "SlackRemoteWeb", dependencies: ["SlackRemoteCore"], linkerSettings: [
            .linkedFramework("WebKit"),
            .linkedFramework("AppKit"),
        ]),
        .executableTarget(name: "SlackRemoteHelper", dependencies: ["SlackRemoteCore", "SlackRemoteWeb"], linkerSettings: [
            .linkedFramework("AppKit"),
            .linkedFramework("ServiceManagement"),
        ]),
        .testTarget(name: "SlackRemoteCoreTests", dependencies: ["SlackRemoteCore"]),
        .testTarget(name: "SlackRemoteWebTests", dependencies: ["SlackRemoteWeb"]),
    ],
    swiftLanguageModes: [.v5]
)
