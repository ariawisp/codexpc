import Foundation

enum ToolExecutor {
    // Very limited demo tool execution; gated by CODEXPC_ALLOW_TOOLS=1
    static func execute(name: String, input: String) -> String {
        return executeWithStatus(name: name, input: input).output
    }

    static func executeWithStatus(name: String, input: String) -> (output: String, ok: Bool) {
        if let allow = ProcessInfo.processInfo.environment["CODEXPC_ALLOWED_TOOLS"], !allow.isEmpty {
            let allowed = Set(allow.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            if !allowed.contains(Substring(name)) {
                return ("tool not allowed: \(name)", false)
            }
        }
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
}
