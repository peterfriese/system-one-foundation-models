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
            targets: ["SystemOneCore", "LayaFoundationModels", "LayaOnDevice", "JevFoundationModels", "ClefFoundationModels"]
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
        .executable(
            name: "ticket-triage-demo",
            targets: ["TicketTriageDemo"]
        ),
        .executable(
            name: "duplicate-article-demo",
            targets: ["DuplicateArticleDemo"]
        ),
        .executable(
            name: "file-organizer-demo",
            targets: ["FileOrganizerDemo"]
        ),
        .executable(
            name: "laya-demo",
            targets: ["LayaDemo"]
        ),
        .executable(
            name: "clef-demo",
            targets: ["ClefDemo"]
        ),
        .executable(
            name: "clef-camera-scanner",
            targets: ["ClefCameraScanner"]
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
            name: "OnDevice",
            description: "Enables on-device decision model capabilities",
            enabledTraits: ["Laya"]
        ),
        .trait(
            name: "Remote",
            description: "Enables remote hosted and self-hosted decision model clients",
            enabledTraits: ["Jev", "LayaServe", "Clef"]
        ),
        .trait(
            name: "All",
            description: "Enables all System One model backends and transports",
            enabledTraits: ["Jev", "Laya", "LayaServe", "Clef"]
        ),
        .default(enabledTraits: ["Jev"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SystemOneCore",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "LayaFoundationModels",
            dependencies: ["SystemOneCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "LayaOnDevice",
            dependencies: ["SystemOneCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "JevFoundationModels",
            dependencies: ["SystemOneCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "ClefFoundationModels",
            dependencies: ["SystemOneCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "TicketTriageDemo",
            dependencies: ["JevFoundationModels"],
            path: "Examples/TicketTriageDemo",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "DuplicateArticleDemo",
            dependencies: ["JevFoundationModels"],
            path: "Examples/DuplicateArticleDemo",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "FileOrganizerDemo",
            dependencies: ["JevFoundationModels"],
            path: "Examples/FileOrganizerDemo",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "LayaDemo",
            dependencies: ["LayaFoundationModels"],
            path: "Examples/LayaDemo",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "ClefDemo",
            dependencies: ["ClefFoundationModels"],
            path: "Examples/ClefDemo",
            exclude: ["README.md"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "ClefCameraScanner",
            dependencies: ["ClefFoundationModels"],
            path: "Examples/ClefCameraScanner",
            exclude: ["README.md"],
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
                "SystemOneCore",
                "LayaFoundationModels",
                "LayaOnDevice"
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
        )
    ]
)
