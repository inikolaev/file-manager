// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Commander",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Commander", targets: ["Commander"])],
    targets: [
        .target(name: "CFileCopy"),
        .target(name: "FileManagerCore", dependencies: ["CFileCopy"]),
        .target(name: "CommanderUI", dependencies: ["FileManagerCore"]),
        .executableTarget(name: "Commander", dependencies: ["CommanderUI"]),
        .testTarget(name: "FileManagerCoreTests", dependencies: ["FileManagerCore"]),
        .testTarget(name: "CommanderUITests", dependencies: ["CommanderUI"]),
    ]
)
