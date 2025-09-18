import Foundation
import OpenAIHarmony
import codexpcEngine
import os

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
    func appendSystem(to engine: codexpc_engine_t, instructions: String, toolsJson: String? = nil) throws -> Int {
        return try appendSystemAndUser(to: engine, instructions: instructions, userParts: [], toolsJson: toolsJson)
    }

    // Renders a conversation from system + user parts and appends tokens.
    func appendSystemAndUser(to engine: codexpc_engine_t, instructions: String?, userParts: [String], toolsJson: String? = nil) throws -> Int {
        guard let enc = self.enc else { return 0 }
        var out = HarmonyOwnedU32Array(data: nil, len: 0)
        var err: UnsafeMutablePointer<CChar>?
        var cfg = HarmonyRenderConversationConfig(auto_drop_analysis: true)
        var opts = HarmonyCompletionOptions(final_only_deltas: true, guarded_stop: true, force_next_channel_final: true, tools_json: nil)

        // Build HarmonyMessage array: optional system + one user message per part
        var messages: [HarmonyMessage] = []
        var toFree: [UnsafeMutablePointer<CChar>?] = []
        func dup(_ s: String) -> UnsafeMutablePointer<CChar>? { let p = strdup(s); toFree.append(p); return p }
        if let sys = instructions, !sys.isEmpty {
            var contents = [dup(sys)]
            var cArr = HarmonyStringArray(data: nil, len: 0)
            contents.withUnsafeMutableBufferPointer { bp in
                cArr = HarmonyStringArray(data: bp.baseAddress, len: bp.count)
            }
            let msg = HarmonyMessage(role: dup("system"), name: nil, recipient: nil, channel: nil, content_type: nil, contents: cArr)
            messages.append(msg)
        }
        for part in userParts where !part.isEmpty {
            var contents = [dup(part)]
            var cArr = HarmonyStringArray(data: nil, len: 0)
            contents.withUnsafeMutableBufferPointer { bp in
                cArr = HarmonyStringArray(data: bp.baseAddress, len: bp.count)
            }
            let msg = HarmonyMessage(role: dup("user"), name: nil, recipient: nil, channel: nil, content_type: nil, contents: cArr)
            messages.append(msg)
        }
        let status: HarmonyStatus = messages.withUnsafeMutableBufferPointer { bp in
            var mArray = HarmonyMessageArray(data: bp.baseAddress, len: bp.count)
            return "assistant".withCString { nrole in
                if let tj = toolsJson, !tj.isEmpty {
                    return tj.withCString { ctj in
                        var o = opts; o.tools_json = ctj
                        return harmony_encoding_render_conversation_from_messages_ex(enc, &mArray, nrole, &cfg, &o, &out, &err)
                    }
                } else {
                    return harmony_encoding_render_conversation_from_messages_ex(enc, &mArray, nrole, &cfg, &opts, &out, &err)
                }
            }
        }
        // Free all strdup'd strings
        toFree.forEach { if let p = $0 { free(p) } }
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
    func appendConversationJSON(to engine: codexpc_engine_t, conversationJson: String, nextRole: String = "assistant", toolsJson: String? = nil) throws -> Int {
        guard let enc = self.enc else { return 0 }
        var out = HarmonyOwnedU32Array(data: nil, len: 0)
        var err: UnsafeMutablePointer<CChar>?
        var opts = HarmonyCompletionOptions(final_only_deltas: true, guarded_stop: true, force_next_channel_final: true, tools_json: nil)
        var cfg = HarmonyRenderConversationConfig(auto_drop_analysis: true)
        var status = conversationJson.withCString { cjson in
            nextRole.withCString { nrole in
                if let toolsJson = toolsJson {
                    return toolsJson.withCString { ctj in
                        var o = opts
                        o.tools_json = ctj
                        return harmony_encoding_render_conversation_for_completion_ex(enc, cjson, nrole, &cfg, &o, &out, &err)
                    }
                } else {
                    return harmony_encoding_render_conversation_for_completion_ex(enc, cjson, nrole, &cfg, &opts, &out, &err)
                }
            }
        }
        if status != HARMONY_STATUS_OK, toolsJson != nil {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            if let e = err { harmony_string_free(e) }
            log.debug("Harmony render (json) with tools_json failed; retrying without tools. err=\(msg, privacy: .public)")
            err = nil
            status = conversationJson.withCString { cjson in
                harmony_encoding_render_conversation_for_completion_ex(enc, cjson, nextRole, &cfg, &opts, &out, &err)
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

    // JSON helpers removed; Harmony C API handles conversation construction now.

    // Appends a single tool message using Harmony C API helper.
    func appendToolMessage(to engine: codexpc_engine_t, toolName: String, output: String) throws -> Int {
        guard let enc = self.enc else { return 0 }
        var out = HarmonyOwnedU32Array(data: nil, len: 0)
        var err: UnsafeMutablePointer<CChar>?
        let status = toolName.withCString { cname in
            output.withCString { cout in
                harmony_encoding_render_tool_message(enc, cname, cout, &out, &err)
            }
        }
        if status != HARMONY_STATUS_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            if let e = err { harmony_string_free(e) }
            throw NSError(domain: "codexpc", code: Int(status.rawValue), userInfo: [NSLocalizedDescriptionKey: "harmony render (tool) failed: \(msg)"])
        }
        defer { harmony_owned_u32_array_free(out) }
        let count = Int(out.len)
        if count > 0, let ptr = out.data {
            _ = codexpc_engine_append_tokens(engine, ptr, out.len)
        }
        return count
    }
}
