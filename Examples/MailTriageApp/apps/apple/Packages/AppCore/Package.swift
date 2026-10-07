// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppCore",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "AppCore", targets: ["AppCore"]),
        .executable(name: "BenchmarkCLI", targets: ["BenchmarkCLI"]),
    ],
    dependencies: [
        .package(name: "SystemOneFoundationModels", path: "../../../../../.."),
        .package(url: "https://github.com/hmlongco/Factory", from: "3.3.2")
    ],
    targets: [
        .target(
            name: "AppCore",
            dependencies: [
                .product(name: "SystemOneCore", package: "SystemOneFoundationModels"),
                .product(name: "LayaFoundationModels", package: "SystemOneFoundationModels"),
                .product(name: "JevFoundationModels", package: "SystemOneFoundationModels"),
                .product(name: "ClefFoundationModels", package: "SystemOneFoundationModels"),
                .product(name: "LayaOnDevice", package: "SystemOneFoundationModels"),
                .product(name: "FactoryKit", package: "Factory")
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "BenchmarkCLI",
            dependencies: [
                "AppCore",
                .product(name: "FactoryKit", package: "Factory")
            ],
            path: "Sources/BenchmarkCLI"
        ),
        .testTarget(
            name: "AppCoreTests",
            dependencies: ["AppCore"]
        ),
    ]
)
