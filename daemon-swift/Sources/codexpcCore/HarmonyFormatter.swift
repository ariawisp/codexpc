import Foundation
import OpenAIHarmony
import codexpcEngine

final class HarmonyFormatter {
    private var enc: OpaquePointer?

    init() throws {
        var handle: OpaquePointer?
        var err: UnsafeMutablePointer<CChar>?
        let status = harmony_encoding_new("HarmonyGptOss", &handle, &err)
        if status != HARMONY_STATUS_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            if let e = err { harmony_string_free(e) }
            throw NSError(domain: "codexpc", code: Int(status.rawValue), userInfo: [NSLocalizedDescriptionKey: "harmony init failed: \(msg)"])
        }
        self.enc = handle
    }

    deinit { if let e = enc { harmony_encoding_free(e) } }

    // Returns number of tokens appended for a system-only conversation
    func appendSystem(to engine: codexpc_engine_t, instructions: String) throws -> Int {
        return try appendSystemAndUser(to: engine, instructions: instructions, userParts: [])
    }

    // Renders a conversation from system + user parts and appends tokens.
    func appendSystemAndUser(to engine: codexpc_engine_t, instructions: String?, userParts: [String]) throws -> Int {
        guard let enc = self.enc else { return 0 }
        let convo = Self.buildConversationJSON(system: instructions, users: userParts)
        var out = HarmonyOwnedU32Array(data: nil, len: 0)
        var err: UnsafeMutablePointer<CChar>?
        let status = convo.withCString { cjson in
            harmony_encoding_render_conversation_for_completion(enc, cjson, "assistant", nil, &out, &err)
        }
        if status != HARMONY_STATUS_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            if let e = err { harmony_string_free(e) }
            throw NSError(domain: "codexpc", code: Int(status.rawValue), userInfo: [NSLocalizedDescriptionKey: "harmony render failed: \(msg)"])
        }
        defer { harmony_owned_u32_array_free(out) }
        let count = Int(out.len)
        if count > 0, let ptr = out.data {
            _ = codexpc_engine_append_tokens(engine, ptr, out.len)
        }
        return count
    }

    // Appends a prebuilt Harmony conversation JSON directly.
    func appendConversationJSON(to engine: codexpc_engine_t, conversationJson: String, nextRole: String = "assistant") throws -> Int {
        guard let enc = self.enc else { return 0 }
        var out = HarmonyOwnedU32Array(data: nil, len: 0)
        var err: UnsafeMutablePointer<CChar>?
        let status = conversationJson.withCString { cjson in
            nextRole.withCString { nrole in
                harmony_encoding_render_conversation_for_completion(enc, cjson, nrole, nil, &out, &err)
            }
        }
        if status != HARMONY_STATUS_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            if let e = err { harmony_string_free(e) }
            throw NSError(domain: "codexpc", code: Int(status.rawValue), userInfo: [NSLocalizedDescriptionKey: "harmony render failed: \(msg)"])
        }
        defer { harmony_owned_u32_array_free(out) }
        let count = Int(out.len)
        if count > 0, let ptr = out.data {
            _ = codexpc_engine_append_tokens(engine, ptr, out.len)
        }
        return count
    }

    private static func jsonEscape(_ s: String) -> String {
        var res = ""
        for c in s {
            switch c {
            case "\\": res += "\\\\"
            case "\"": res += "\\\""
            case "\n": res += "\\n"
            case "\r": res += "\\r"
            case "\t": res += "\\t"
            default: res.append(c)
            }
        }
        return res
    }

    private static func buildConversationJSON(system: String?, users: [String]) -> String {
        var parts: [String] = []
        if let s = system, !s.isEmpty {
            let esc = jsonEscape(s)
            parts.append("{\"role\":\"system\",\"content\":[{\"type\":\"text\",\"text\":\"\(esc)\"}]}")
        } else {
            // Provide a minimal system scaffold to steer the model to emit final-channel text
            let sys = "# Valid channels: analysis, commentary, final.\nAlways write user-facing responses in the final channel; use analysis only for internal reasoning."
            let esc = jsonEscape(sys)
            parts.append("{\"role\":\"system\",\"content\":[{\"type\":\"text\",\"text\":\"\(esc)\"}]}")
        }
        for u in users where !u.isEmpty {
            let esc = jsonEscape(u)
            parts.append("{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"\(esc)\"}]}")
        }
        let msgs = parts.joined(separator: ",")
        return "{\"messages\":[\(msgs)]}"
    }
}
