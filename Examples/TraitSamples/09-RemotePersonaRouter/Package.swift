// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "RemotePersonaRouter",
    platforms: [
        .macOS("27.0"),
        .iOS("27.0")
    ],
    dependencies: [
        .package(name: "SystemOneFoundationModels", path: "../../..", traits: ["Remote"])
    ],
    targets: [
        .executableTarget(
            name: "RemotePersonaRouter",
            dependencies: [
                .product(name: "SystemOneFoundationModels", package: "SystemOneFoundationModels")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
