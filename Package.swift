// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JournalismWorkflowHub",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "JournalismWorkflowHub",
            targets: ["JournalismWorkflowHub"]
        )
    ],
    targets: [
        .executableTarget(
            name: "JournalismWorkflowHub",
            path: "Sources/JournalismWorkflowHub",
            resources: [
                .copy("Resources/DemoWorkspace")
            ]
        ),
        .testTarget(
            name: "JournalismWorkflowHubTests",
            dependencies: ["JournalismWorkflowHub"],
            path: "Tests/JournalismWorkflowHubTests"
        )
    ]
)
