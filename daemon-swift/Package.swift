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
            dependencies: ["codexpcEngine", "HarmonyFFI"],
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
            name: "HarmonyFFI",
            path: "Sources/HarmonyFFI",
            publicHeadersPath: "include",
            cSettings: {
                var cs: [CSetting] = []
                if let inc = ProcessInfo.processInfo.environment["HARMONY_FFI_INCLUDE_DIR"], !inc.isEmpty {
                    cs.append(.unsafeFlags(["-I\(inc)"]))
                }
                return cs
            }(),
            linkerSettings: {
                var ls: [LinkerSetting] = []
                if let lib = ProcessInfo.processInfo.environment["HARMONY_FFI_LIB_DIR"], !lib.isEmpty {
                    ls.append(.unsafeFlags(["-L\(lib)"]))
                }
                ls.append(.unsafeFlags(["-lharmony_ffi"]))
                return ls
            }()
        ),
    ]
)
