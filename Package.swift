// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SystemOneFoundationModels",
    platforms: [
        .iOS("27.0"),
        .macOS("27.0"),
        .visionOS("27.0")
    ],
    products: [
        .library(
            name: "SystemOneCore",
            targets: ["SystemOneCore"]
        ),
        .library(
            name: "SystemOneFoundationModels",
            targets: ["SystemOneFoundationModels"]
        ),
        .library(
            name: "LayaFoundationModels",
            targets: ["LayaFoundationModels"]
        ),
        .library(
            name: "LayaOnDevice",
            targets: ["LayaOnDevice"]
        ),
        .library(
            name: "JevFoundationModels",
            targets: ["JevFoundationModels"]
        ),
        .library(
            name: "ClefFoundationModels",
            targets: ["ClefFoundationModels"]
        ),
        .library(
            name: "OpenAIFoundationModels",
            targets: ["OpenAIFoundationModels"]
        ),
        .library(
            name: "GeminiFoundationModels",
            targets: ["GeminiFoundationModels"]
        ),
        .executable(
            name: "system-one-cli",
            targets: ["SystemOneCLI"]
        ),
        .executable(
            name: "vision-scanner-app",
            targets: ["VisionScannerApp"]
        ),
        .executable(
            name: "jev-quickstart",
            targets: ["JevQuickstart"]
        ),
        .executable(
            name: "laya-quickstart",
            targets: ["LayaServeQuickstart"]
        ),
        .executable(
            name: "laya-ondevice-quickstart",
            targets: ["LayaOnDeviceQuickstart"]
        ),
        .executable(
            name: "clef-quickstart",
            targets: ["ClefQuickstart"]
        ),
        .executable(
            name: "openai-quickstart",
            targets: ["OpenAIQuickstart"]
        ),
        .executable(
            name: "gemini-quickstart",
            targets: ["GeminiQuickstart"]
        )
    ],
    traits: [
        .trait(
            name: "Jev",
            description: "Enables TypeSafe Jev hosted API client"
        ),
        .trait(
            name: "Laya",
            description: "Enables on-device Laya decision models via Core ML and Apple Neural Engine"
        ),
        .trait(
            name: "LayaServe",
            description: "Enables HTTP transport for self-hosted laya-serve instances"
        ),
        .trait(
            name: "Clef",
            description: "Enables Cloudflare Clef and Clef-Flash hosted and local decision models"
        ),
        .trait(
            name: "OpenAI",
            description: "Enables OpenAI Decisions API hosted client"
        ),
        .trait(
            name: "Gemini",
            description: "Enables Google Gemini Decisions API hosted client"
        ),
        .trait(
            name: "OnDevice",
            description: "Enables on-device decision model capabilities",
            enabledTraits: ["Laya"]
        ),
        .trait(
            name: "Remote",
            description: "Enables remote hosted and self-hosted decision model clients",
            enabledTraits: ["Jev", "LayaServe", "Clef", "OpenAI", "Gemini"]
        ),
        .trait(
            name: "All",
            description: "Enables all System One model backends and transports",
            enabledTraits: ["Jev", "Laya", "LayaServe", "Clef", "OpenAI", "Gemini"]
        ),
        .default(enabledTraits: ["All"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SystemOneCore",
            exclude: ["README.md"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "SystemOneFoundationModels",
            dependencies: [
                "SystemOneCore",
                .target(name: "JevFoundationModels", condition: .when(traits: ["Jev"])),
                .target(name: "LayaFoundationModels", condition: .when(traits: ["LayaServe"])),
                .target(name: "LayaOnDevice", condition: .when(traits: ["Laya"])),
                .target(name: "ClefFoundationModels", condition: .when(traits: ["Clef"])),
                .target(name: "OpenAIFoundationModels", condition: .when(traits: ["OpenAI"])),
                .target(name: "GeminiFoundationModels", condition: .when(traits: ["Gemini"]))
            ],
            exclude: ["README.md"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "LayaFoundationModels",
            dependencies: ["SystemOneCore"],
            exclude: ["README.md"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "LayaOnDevice",
            dependencies: ["SystemOneCore"],
            exclude: ["README.md"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "JevFoundationModels",
            dependencies: ["SystemOneCore"],
            exclude: ["README.md"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "ClefFoundationModels",
            dependencies: ["SystemOneCore"],
            exclude: ["README.md"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "OpenAIFoundationModels",
            dependencies: ["SystemOneCore"],
            exclude: ["README.md"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "GeminiFoundationModels",
            dependencies: ["SystemOneCore"],
            exclude: ["README.md"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "SystemOneCLI",
            dependencies: [
                "SystemOneFoundationModels",
                "SystemOneCore",
                "JevFoundationModels",
                "LayaFoundationModels",
                "LayaOnDevice",
                "ClefFoundationModels",
                "OpenAIFoundationModels",
                "GeminiFoundationModels"
            ],
            path: "Examples/CLI",
            exclude: ["README.md"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "VisionScannerApp",
            dependencies: [
                "SystemOneCore",
                "ClefFoundationModels",
                "OpenAIFoundationModels",
                "GeminiFoundationModels"
            ],
            path: "Examples/Apps/VisionScannerApp",
            exclude: ["README.md", "VisionScannerApp.xcodeproj"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "JevQuickstart",
            dependencies: ["JevFoundationModels"],
            path: "Examples/Quickstarts/JevQuickstart",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "LayaServeQuickstart",
            dependencies: ["LayaFoundationModels"],
            path: "Examples/Quickstarts/LayaServeQuickstart",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "LayaOnDeviceQuickstart",
            dependencies: ["LayaOnDevice"],
            path: "Examples/Quickstarts/LayaOnDeviceQuickstart",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "ClefQuickstart",
            dependencies: ["ClefFoundationModels"],
            path: "Examples/Quickstarts/ClefQuickstart",
            exclude: ["sample.jpg"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "OpenAIQuickstart",
            dependencies: ["OpenAIFoundationModels"],
            path: "Examples/Quickstarts/OpenAIQuickstart",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "GeminiQuickstart",
            dependencies: ["GeminiFoundationModels"],
            path: "Examples/Quickstarts/GeminiQuickstart",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "SystemOneCoreTests",
            dependencies: [
                "SystemOneCore"
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "JevFoundationModelsTests",
            dependencies: [
                "JevFoundationModels",
                "SystemOneCore"
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "LayaFoundationModelsTests",
            dependencies: [
                "LayaFoundationModels",
                "SystemOneCore"
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "LayaOnDeviceTests",
            dependencies: [
                "LayaOnDevice",
                "SystemOneCore"
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "ClefFoundationModelsTests",
            dependencies: [
                "ClefFoundationModels",
                "SystemOneCore"
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "OpenAIFoundationModelsTests",
            dependencies: [
                "OpenAIFoundationModels",
                "SystemOneCore"
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "GeminiFoundationModelsTests",
            dependencies: [
                "GeminiFoundationModels",
                "SystemOneCore"
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
