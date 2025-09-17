import Foundation

enum ToolExecutor {
    // Demo tool execution with no environment variables.
    // Callers should prefer executeEnforced(..) which applies allowlist, timeout and output caps.

    struct Config {
        // Enable or disable tool execution globally (disabled by default for safety)
        static var enabled: Bool = false
        // Optional allowlist. If nil and enabled==true, a safe default set is used.
        static var allowed: Set<String>? = nil
        // Policy knobs (test-friendly, not env-driven)
        static var timeoutMs: Int = 2000
        static var maxOutputBytes: Int = 8192
        // Test-only latency injection
        static var testDelayMs: Int = 0
        // Default safe tools
        static let defaultAllowed: Set<String> = ["echo", "upper"]
    }

    // Public convenience used by older paths/tests
    static func execute(name: String, input: String) -> String { executeWithStatus(name: name, input: input).output }

    // Central entry that applies allowlist, timeout and output size caps.
    static func executeEnforced(name: String, input: String) -> (output: String, ok: Bool) {
        guard isAllowed(name) else { return ("tool not allowed: \(name)", false) }
        let timeoutMs = Config.timeoutMs
        let maxBytes = Config.maxOutputBytes

        // Execute on a background queue and wait with timeout.
        let sem = DispatchSemaphore(value: 0)
        var result: (output: String, ok: Bool)? = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let res = executeWithStatus(name: name, input: input)
            result = res
            sem.signal()
        }
        let waitRes = sem.wait(timeout: .now() + .milliseconds(timeoutMs))
        guard waitRes == .success, let final = result else {
            return ("tool timed out: \(name)", false)
        }
        // Cap output bytes (UTF-8)
        let capped = capUtf8(final.output, maxBytes: maxBytes)
        return (capped, final.ok)
    }

    // Core implementation: returns output and ok without policy enforcement.
    static func executeWithStatus(name: String, input: String) -> (output: String, ok: Bool) {
        guard isAllowed(name) else { return ("tool not allowed: \(name)", false) }
        // Optional test hook to simulate tool latency (milliseconds)
        if Config.testDelayMs > 0 { usleep(useconds_t(Config.testDelayMs * 1000)) }
        switch name {
        case "echo":
            if input.trimmingCharacters(in: .whitespaces).hasPrefix("{") {
                guard let v = firstStringValue(inJson: input) else { return ("invalid arguments: expected JSON with a string field", false) }
                return (v, true)
            }
            return (input, true)
        case "upper":
            if input.trimmingCharacters(in: .whitespaces).hasPrefix("{") {
                guard let v = firstStringValue(inJson: input) else { return ("invalid arguments: expected JSON with a string field", false) }
                return (v.uppercased(), true)
            }
            return (input.uppercased(), true)
        default:
            return ("unsupported tool: \(name)", false)
        }
    }

    private static func isAllowed(_ name: String) -> Bool {
        guard Config.enabled else { return false }
        if let allowed = Config.allowed { return allowed.contains(name) }
        return Config.defaultAllowed.contains(name)
    }

    private static func firstStringValue(inJson s: String) -> String? {
        guard let data = s.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }
        if let dict = obj as? [String: Any] {
            for (_, v) in dict {
                if let str = v as? String { return str }
            }
        }
        return nil
    }

    private static func capUtf8(_ s: String, maxBytes: Int) -> String {
        if maxBytes <= 0 { return "" }
        let utf8View = s.utf8
        if utf8View.count <= maxBytes { return s }
        var count = 0
        var idx = utf8View.startIndex
        while idx != utf8View.endIndex && count < maxBytes {
            utf8View.formIndex(after: &idx)
            count += 1
        }
        let prefixBytes = Array(utf8View[..<idx])
        return String(decoding: prefixBytes, as: UTF8.self)
    }

    // No env-based config; values are provided via ToolExecutor.Config
}
