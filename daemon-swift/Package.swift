// swift-tools-version: 5.9
import PackageDescription
import Foundation

let package = Package(
    name: "codexpcd",
    platforms: [ .macOS(.v13) ],
    products: [
        .executable(name: "codexpcd", targets: ["codexpcd"]),
        .library(name: "codexpcCore", targets: ["codexpcCore"]),
    ],
    targets: [
        .executableTarget(
            name: "codexpcd",
            dependencies: ["codexpcCore"],
            path: "Sources/codexpcd"
        ),
        .target(
            name: "codexpcCore",
            dependencies: ["codexpcEngine", "OpenAIHarmony"],
            path: "Sources/codexpcCore",
            linkerSettings: [ .linkedFramework("Foundation") ]
        ),
        .target(
            name: "codexpcEngine",
            path: "Sources/codexpcEngine",
            publicHeadersPath: "include",
            cxxSettings: {
                var flags: [CXXSetting] = [ .headerSearchPath("include") ]
                if let inc = ProcessInfo.processInfo.environment["GPTOSS_INCLUDE_DIR"], !inc.isEmpty {
                    flags.append(.unsafeFlags(["-I\(inc)"]))
                }
                if let stub = ProcessInfo.processInfo.environment["CODEXPC_STUB_ENGINE"], !stub.isEmpty {
                    flags.append(.unsafeFlags(["-DCODEXPC_STUB_ENGINE=1"]))
                }
                return flags
            }(),
            linkerSettings: {
                var ls: [LinkerSetting] = [ .linkedLibrary("c++") ]
                if let lib = ProcessInfo.processInfo.environment["GPTOSS_LIB_DIR"], !lib.isEmpty {
                    ls.append(.unsafeFlags(["-L\(lib)"]))
                }
                // Link gptoss if present in LIB_DIR
                ls.append(.unsafeFlags(["-lgptoss"]))
                // Also link its static dependency and required frameworks
                ls.append(.unsafeFlags(["-lmetal-kernels"]))
                ls.append(.linkedFramework("Metal"))
                ls.append(.linkedFramework("IOKit"))
                return ls
            }()
        ),
        .target(
            name: "OpenAIHarmony",
            path: "Sources/OpenAIHarmony",
            publicHeadersPath: "include",
            cSettings: {
                var cs: [CSetting] = []
                if let inc = ProcessInfo.processInfo.environment["HARMONY_INCLUDE_DIR"], !inc.isEmpty {
                    cs.append(.unsafeFlags(["-I\(inc)"]))
                }
                return cs
            }(),
            linkerSettings: {
                var ls: [LinkerSetting] = []
                if let lib = ProcessInfo.processInfo.environment["HARMONY_LIB_DIR"], !lib.isEmpty {
                    ls.append(.unsafeFlags(["-L\(lib)"]))
                }
                ls.append(.unsafeFlags(["-lopenai_harmony"]))
                return ls
            }()
        ),
        .testTarget(
            name: "codexpcCoreTests",
            dependencies: ["codexpcCore"],
            path: "Tests/codexpcCoreTests"
        ),
    ]
)
