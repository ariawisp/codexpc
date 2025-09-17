// swift-tools-version: 5.9
import PackageDescription
import Foundation

let package = Package(
    name: "codexpcd",
    platforms: [ .macOS(.v13) ],
    products: [
        .executable(name: "codexpcd", targets: ["codexpcd"]),
        .library(name: "codexpcCore", targets: ["codexpcCore"]),
        .executable(name: "gptoss-smoke", targets: ["gptoss-smoke"]),
    ],
    targets: [
        .executableTarget(
            name: "codexpcd",
            dependencies: ["codexpcCore"],
            path: "Sources/codexpcd",
            linkerSettings: {
                var ls: [LinkerSetting] = []
                // Propagate GPT-OSS metal kernel force-load to the final binary so __METAL section is present
                if ProcessInfo.processInfo.environment["CODEXPC_STUB_ENGINE"].map({ !$0.isEmpty }) != true,
                   let lib = ProcessInfo.processInfo.environment["GPTOSS_LIB_DIR"], !lib.isEmpty {
                    ls.append(.unsafeFlags(["-L\(lib)"]))
                    // Embed default.metallib into the main binary so gpt-oss can find __METAL,__shaders
                    ls.append(contentsOf: [
                        .unsafeFlags(["-Xlinker", "-sectcreate"]),
                        .unsafeFlags(["-Xlinker", "__METAL"]),
                        .unsafeFlags(["-Xlinker", "__shaders"]),
                        .unsafeFlags(["-Xlinker", "\(lib)/default.metallib"]),
                        .unsafeFlags(["-Xlinker", "-force_load"]),
                        .unsafeFlags(["-Xlinker", "\(lib)/libmetal-kernels.a"]),
                        .unsafeFlags(["-lgptoss"]),
                    ])
                }
                // Set rpath so Harmony dylib can be found next to the binary (../lib)
                ls.append(contentsOf: [
                    .unsafeFlags(["-Xlinker", "-rpath"]),
                    .unsafeFlags(["-Xlinker", "@executable_path/../lib"]),
                ])
                ls.append(.linkedFramework("Metal"))
                ls.append(.linkedFramework("IOKit"))
                return ls
            }()
        ),
        .executableTarget(
            name: "gptoss-smoke",
            dependencies: ["codexpcEngine"],
            path: "Sources/gptoss-smoke"
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
                if ProcessInfo.processInfo.environment["CODEXPC_STUB_ENGINE"].map({ !$0.isEmpty }) != true {
                    // Link gptoss if not stubbed
                    ls.append(.unsafeFlags(["-lgptoss"]))
                    // Ensure metal-kernels section is force-loaded so the embedded metallib is visible to getsectiondata
                    if let lib = ProcessInfo.processInfo.environment["GPTOSS_LIB_DIR"], !lib.isEmpty {
                        ls.append(contentsOf: [
                            .unsafeFlags(["-Xlinker", "-force_load"]),
                            .unsafeFlags(["-Xlinker", "\(lib)/libmetal-kernels.a"]),
                        ])
                    } else {
                        ls.append(.unsafeFlags(["-Xlinker", "-all_load"]))
                        ls.append(.unsafeFlags(["-lmetal-kernels"]))
                    }
                }
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
                if let stub = ProcessInfo.processInfo.environment["HARMONY_FFI_STUB"], !stub.isEmpty {
                    cs.append(.define("HARMONY_FFI_STUB", to: "1"))
                }
                return cs
            }(),
            linkerSettings: {
                var ls: [LinkerSetting] = []
                if let stub = ProcessInfo.processInfo.environment["HARMONY_FFI_STUB"], !stub.isEmpty {
                    // no-op: stubbed header and no dynamic library link
                } else {
                    if let lib = ProcessInfo.processInfo.environment["HARMONY_LIB_DIR"], !lib.isEmpty {
                        ls.append(.unsafeFlags(["-L\(lib)"]))
                    }
                    ls.append(.unsafeFlags(["-lopenai_harmony"]))
                }
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
