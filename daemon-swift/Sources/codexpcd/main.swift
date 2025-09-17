import Foundation
import codexpcCore

@main
struct Main {
    static func main() {
        // Defaults are now baked into the engine; no runtime env vars required.
        var serviceName = "com.yourorg.codexpc"
        // Simple arg parsing for --service override and optional --foreground flag (no-op)
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let k = it.next() {
            switch k {
            case "--service": serviceName = it.next() ?? serviceName
            case "--foreground": _ = true // accepted for compatibility
            default: break
            }
        }
        // Test-friendly toggles (no-op in production): enable tools and tune timeouts/delays via envs
        let env = ProcessInfo.processInfo.environment
        if env["CODEXPC_ALLOW_TOOLS"] == "1" { ToolExecutor.Config.enabled = true }
        if let s = env["CODEXPC_TOOL_TIMEOUT_MS"], let v = Int(s) { ToolExecutor.Config.timeoutMs = v }
        if let s = env["CODEXPC_TEST_TOOL_DELAY_MS"], let v = Int(s) { ToolExecutor.Config.testDelayMs = v }
        let server = XpcServer(serviceName: serviceName)
        // Optional warmup: compile kernels once at startup for faster first token.
        Warmup.runIfConfigured()
        server.run()
    }
}
