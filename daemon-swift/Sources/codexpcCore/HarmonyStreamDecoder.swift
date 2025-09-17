import Foundation
import OpenAIHarmony
import os

final class HarmonyStreamDecoder {
    private var enc: UnsafeMutablePointer<HarmonyEncodingHandle>?
    private var parser: UnsafeMutablePointer<HarmonyStreamableParserHandle>?
    private var actionStopTokens: Set<UInt32> = []
    private var toolRecipient: String? = nil
    private var toolBuffer: String = ""

    init() throws {
        var e: UnsafeMutablePointer<HarmonyEncodingHandle>?
        var err: UnsafeMutablePointer<CChar>?
        let st = harmony_encoding_new("harmony_gpt_oss", &e, &err)
        if st != HARMONY_STATUS_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            if let e = err { harmony_string_free(e) }
            log.error("Harmony encoding init failed: \(msg, privacy: .public)")
            throw NSError(domain: "codexpc", code: Int(st.rawValue), userInfo: [NSLocalizedDescriptionKey: "harmony init failed: \(msg)"])
        }
        self.enc = e
        var p: UnsafeMutablePointer<HarmonyStreamableParserHandle>?
        let stp = harmony_streamable_parser_new(self.enc, "assistant", &p, &err)
        if stp != HARMONY_STATUS_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            if let e = err { harmony_string_free(e) }
            log.error("Harmony parser init failed: \(msg, privacy: .public)")
            throw NSError(domain: "codexpc", code: Int(stp.rawValue), userInfo: [NSLocalizedDescriptionKey: "harmony parser init failed: \(msg)"])
        }
        self.parser = p
        log.info("HarmonyStreamDecoder initialized")

        // Load assistant action stop tokens (e.g., <|call|>, <|return|>)
        var toks = HarmonyOwnedU32Array(data: nil, len: 0)
        let stt = harmony_encoding_stop_tokens_for_assistant_actions(self.enc, &toks, &err)
        if stt == HARMONY_STATUS_OK, let data = toks.data {
            let count = Int(toks.len)
            let buf = UnsafeBufferPointer(start: data, count: count)
            self.actionStopTokens = Set(buf)
        }
        harmony_owned_u32_array_free(toks)
    }

    deinit {
        if let p = parser { harmony_streamable_parser_free(p) }
        if let e = enc { harmony_encoding_free(e) }
    }

    // Result of processing a token
    struct Result {
        let delta: String?
        let toolEvent: (name: String, input: String)?
    }

    // Process a single token and return delta and/or a tool event
    func process(token: UInt32) -> Result {
        guard let p = parser else { return Result(delta: nil, toolEvent: nil) }
        var err: UnsafeMutablePointer<CChar>?
        let st = harmony_streamable_parser_process(p, token, &err)
        if st != HARMONY_STATUS_OK {
            if let e = err { harmony_string_free(e) }
            return Result(delta: nil, toolEvent: nil)
        }
        var deltaStr: String? = nil
        // Determine channel and recipient
        var chPtr: UnsafeMutablePointer<CChar>?
        _ = harmony_streamable_parser_current_channel(p, &chPtr, &err)
        let channel = chPtr.map { String(cString: $0) }
        if let c = chPtr { harmony_string_free(c) }

        var rcptPtr: UnsafeMutablePointer<CChar>?
        _ = harmony_streamable_parser_current_recipient(p, &rcptPtr, &err)
        let recipient = rcptPtr.map { String(cString: $0) }
        if let r = rcptPtr { harmony_string_free(r) }

        // Accumulate delta
        var cstr: UnsafeMutablePointer<CChar>?
        let dl = harmony_streamable_parser_last_content_delta(p, &cstr, &err)
        if dl == HARMONY_STATUS_OK, let s = cstr {
            let str = String(cString: s)
            if !str.isEmpty {
                // Only emit user-facing delta if channel is 'final'
                let emitCommentary = (ProcessInfo.processInfo.environment["CODEXPC_DEBUG_EMIT_COMMENTARY"] == "1")
                if channel == "final" || emitCommentary {
                    deltaStr = str
                }
            }
        }
        if let s = cstr { harmony_string_free(s) }

        var toolEvent: (String, String)? = nil
        // Tool call detection: if recipient is present in 'commentary', capture args until action stop token
        if let rec = recipient, channel == "commentary" {
            if toolRecipient != rec { toolRecipient = rec; toolBuffer = "" }
            // Append all delta (even if not final) to tool buffer
            if let dl = deltaStr { toolBuffer += dl }
        }
        if actionStopTokens.contains(token), let rec = toolRecipient, !rec.isEmpty {
            toolEvent = (rec, toolBuffer)
            toolRecipient = nil
            toolBuffer = ""
        }

        return Result(delta: deltaStr, toolEvent: toolEvent)
    }
}
