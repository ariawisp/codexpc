// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "codexpc-cli",
    platforms: [ .macOS(.v13) ],
    products: [ .executable(name: "codexpc-cli", targets: ["codexpc-cli"]) ],
    targets: [
        .executableTarget(name: "codexpc-cli", path: "Sources", linkerSettings: [ .linkedFramework("Foundation") ])
    ]
)
