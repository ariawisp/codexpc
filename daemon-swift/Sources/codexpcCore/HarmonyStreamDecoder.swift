import Foundation
import OpenAIHarmony
import os

final class HarmonyStreamDecoder {
    private var enc: OpaquePointer?
    private var parser: OpaquePointer?
    private var toolRecipient: String? = nil
    private var toolBuffer: String = ""
    private var didStop: Bool = false
    private var finalSoFar: String = ""
    private var duplicateFinalCount: Int = 0
    private var suppressedFormattingDeltas: Int = 0
    private static let debugHarmony: Bool = true

    init() throws {
        var e: OpaquePointer?
        var err: UnsafeMutablePointer<CChar>?
        let st = harmony_encoding_new("HarmonyGptOss", &e, &err)
        if st != HARMONY_STATUS_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            if let e = err { harmony_string_free(e) }
            log.error("Harmony encoding init failed: \(msg, privacy: .public)")
            throw NSError(domain: "codexpc", code: Int(st.rawValue), userInfo: [NSLocalizedDescriptionKey: "harmony init failed: \(msg)"])
        }
        self.enc = e
        var p: OpaquePointer?
        let stp = harmony_streamable_parser_new(self.enc, "assistant", &p, &err)
        if stp != HARMONY_STATUS_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            if let e = err { harmony_string_free(e) }
            log.error("Harmony parser init failed: \(msg, privacy: .public)")
            throw NSError(domain: "codexpc", code: Int(stp.rawValue), userInfo: [NSLocalizedDescriptionKey: "harmony parser init failed: \(msg)"])
        }
        self.parser = p
        if Self.debugHarmony { log.info("harmony debug enabled (env/file)") }

        // No raw-decode fallback; rely on event-driven decoding (STOP/TOOL_ARGS_DONE)
    }

    // Expose raw parser handle for render+prime APIs
    var rawParser: OpaquePointer? { return parser }

    // Encode text with optional allowed special list; returns token IDs
    func encode(text: String, allowedSpecial: [String]? = nil) -> [UInt32] {
        guard let e = enc else { return [] }
        var err: UnsafeMutablePointer<CChar>?
        var ids: [UInt32] = []
        let result: HarmonyStatus = text.withCString { ctext in
            if let allowed = allowedSpecial, !allowed.isEmpty {
                // Build C array of C strings for allowed_special
                let dup = allowed.map { strdup($0) }
                defer { dup.forEach { if let p = $0 { free(p) } } }
                return dup.withUnsafeBufferPointer { bp -> HarmonyStatus in
                    if let base = bp.baseAddress {
                        return base.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: bp.count) { rebased in
                            var out = HarmonyOwnedU32Array(data: nil, len: 0)
                            let st = harmony_encoding_encode(e, ctext, rebased, bp.count, &out, &err)
                            if st == HARMONY_STATUS_OK, out.len > 0, let data = out.data {
                                ids = Array(UnsafeBufferPointer(start: data, count: Int(out.len)))
                            }
                            harmony_owned_u32_array_free(out)
                            return st
                        }
                    } else {
                        var out = HarmonyOwnedU32Array(data: nil, len: 0)
                        let st = harmony_encoding_encode(e, ctext, nil, 0, &out, &err)
                        if st == HARMONY_STATUS_OK, out.len > 0, let data = out.data {
                            ids = Array(UnsafeBufferPointer(start: data, count: Int(out.len)))
                        }
                        harmony_owned_u32_array_free(out)
                        return st
                    }
                }
            } else {
                var out = HarmonyOwnedU32Array(data: nil, len: 0)
                let st = harmony_encoding_encode(e, ctext, nil, 0, &out, &err)
                if st == HARMONY_STATUS_OK, out.len > 0, let data = out.data {
                    ids = Array(UnsafeBufferPointer(start: data, count: Int(out.len)))
                }
                harmony_owned_u32_array_free(out)
                return st
            }
        }
        if result != HARMONY_STATUS_OK { if let e = err { harmony_string_free(e) } }
        return ids
    }

    deinit {
        if let p = parser { harmony_streamable_parser_free(p) }
        if let e = enc { harmony_encoding_free(e) }
    }

    // Result of processing a token
    struct Result {
        let delta: String?
        let toolEvent: (name: String, input: String, callId: String)?
        let isStop: Bool
    }

    // Process a single token and return delta and/or a tool event
    func process(token: UInt32) -> Result {
        guard let p = parser else { return Result(delta: nil, toolEvent: nil, isStop: false) }
        var err: UnsafeMutablePointer<CChar>?
        let st = harmony_streamable_parser_process(p, token, &err)
        if st != HARMONY_STATUS_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            if let e = err { harmony_string_free(e) }
            log.error("harmony parser process error: \(msg, privacy: .public)")
            return Result(delta: nil, toolEvent: nil, isStop: false)
        }
        if Self.debugHarmony { self.logParserState(prefix: "after_token_dbg") }
        // Also surface a brief info-state for the first few tokens
        self.logInfoState(prefix: "after_token")

        var outDelta: String? = nil
        // Drain at most one meaningful event per token to avoid duplicate deltas
        while true {
            var ev = HarmonyStreamEvent(kind: 0, channel: nil, recipient: nil, name: nil, call_id: nil, text: nil, json: nil)
            let est = harmony_streamable_parser_next_event(p, &ev, &err)
            if est != HARMONY_STATUS_OK {
                if let e = err { harmony_string_free(e) }
                break
            }
            if ev.kind == 0 { // NONE
                break
            }
            // Map events
            switch ev.kind {
            case 1: // CONTENT_DELTA (incremental)
                if let t = ev.text {
                    let s = String(cString: t)
                    let ch = ev.channel.map { String(cString: $0) }
                    // Suppress formatting markers sampled as text
                    if Self.isFormattingMarkerText(s) {
                        self.suppressedFormattingDeltas += 1
                    } else if ch == "final" {
                        // Parser emits incremental deltas already; forward as-is and accumulate
                        outDelta = s
                        if !s.isEmpty {
                            finalSoFar += s
                            duplicateFinalCount = 0
                            let preview = s.prefix(80).replacingOccurrences(of: "\n", with: " ")
                            log.info("harmony final inc len=\(s.count, privacy: .public) text=\(preview, privacy: .public)")
                        }
                        harmony_stream_event_free(&ev)
                        break
                    }
                }
            case 2: // TOOL_CALL_BEGIN
                if let rc = ev.recipient { toolRecipient = String(cString: rc); toolBuffer = "" }
                if let name = ev.recipient {
                    let s = String(cString: name)
                    log.info("harmony event: TOOL_CALL_BEGIN recipient=\(s, privacy: .public)")
                }
            case 3: // TOOL_ARGS_DELTA
                if let rc = ev.recipient { let recStr = String(cString: rc); if toolRecipient != recStr { toolRecipient = recStr; toolBuffer = "" } }
                if let j = ev.json { toolBuffer += String(cString: j) }
                if let j = ev.json {
                    let txt = String(cString: j)
                    let preview = txt.prefix(160).replacingOccurrences(of: "\n", with: " ")
                    log.info("harmony event: TOOL_ARGS_DELTA len=\(txt.count, privacy: .public) json=\(preview, privacy: .public)")
                }
            case 4: // TOOL_ARGS_DONE
                // Finalize current tool call buffer into an event
                if let rec = toolRecipient {
                    let name = rec
                    let args = toolBuffer
                    // Clear buffer so we emit at most once
                    toolRecipient = nil
                    toolBuffer = ""
                    log.info("harmony event: TOOL_ARGS_DONE recipient=\(name, privacy: .public) bytes=\(args.utf8.count, privacy: .public)")
                    var callId = ""
                    if let cid = ev.call_id { callId = String(cString: cid) }
                    harmony_stream_event_free(&ev)
                    return Result(delta: outDelta, toolEvent: (name: name, input: args, callId: callId), isStop: didStop)
                }
            case 5: // STOP
                didStop = true
                log.info("harmony event: STOP")
                harmony_stream_event_free(&ev)
                return Result(delta: outDelta, toolEvent: nil, isStop: didStop)
            default:
                break
            }
            harmony_stream_event_free(&ev)
        }

        // If STOP arrives without TOOL_ARGS_DONE (edge-case), finalize any pending tool buffer
        var toolEvent: (String, String, String)? = nil
        if didStop, let rec = toolRecipient, !rec.isEmpty {
            toolEvent = (rec, toolBuffer)
            toolRecipient = nil
            toolBuffer = ""
        }
        return Result(delta: outDelta, toolEvent: toolEvent, isStop: didStop)
    }

    // Signal end-of-sequence to the parser and drain any pending events (e.g., STOP)
    func processEOS() -> Result {
        guard let p = parser else { return Result(delta: nil, toolEvent: nil, isStop: false) }
        var err: UnsafeMutablePointer<CChar>?
        let st = harmony_streamable_parser_process_eos(p, &err)
        if st != HARMONY_STATUS_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            if let e = err { harmony_string_free(e) }
            log.error("harmony parser eos error: \(msg, privacy: .public)")
            return Result(delta: nil, toolEvent: nil, isStop: false)
        }
        if Self.debugHarmony { self.logParserState(prefix: "after_eos") }
        // Drain once to surface any STOP/tool events
        var outDelta: String? = nil
        var toolEvent: (String, String)? = nil
        while true {
            var ev = HarmonyStreamEvent(kind: 0, channel: nil, recipient: nil, name: nil, call_id: nil, text: nil, json: nil)
            let est = harmony_streamable_parser_next_event(p, &ev, &err)
            if est != HARMONY_STATUS_OK { if let e = err { harmony_string_free(e) }; break }
            if ev.kind == 0 { break }
            switch ev.kind {
            case 1:
                if let t = ev.text { outDelta = String(cString: t) }
            case 4:
                if let rc = ev.recipient {
                    var cid = ""
                    if let c = ev.call_id { cid = String(cString: c) }
                    toolEvent = (String(cString: rc), toolBuffer, cid)
                }
            case 5:
                didStop = true
            default:
                break
            }
            harmony_stream_event_free(&ev)
        }
        if let te = toolEvent {
            return Result(delta: outDelta, toolEvent: (name: te.0, input: te.1, callId: te.2), isStop: didStop)
        }
        return Result(delta: outDelta, toolEvent: nil, isStop: didStop)
    }

    // Info-level dump of current parser state (not behind debug flags).
    func logInfoState(prefix: String) {
        guard let p = parser else { return }
        var err: UnsafeMutablePointer<CChar>?
        var rPtr: UnsafeMutablePointer<CChar>? = nil
        var chPtr: UnsafeMutablePointer<CChar>? = nil
        var ctPtr: UnsafeMutablePointer<CChar>? = nil
        var recPtr: UnsafeMutablePointer<CChar>? = nil
        var deltaPtr: UnsafeMutablePointer<CChar>? = nil
        _ = harmony_streamable_parser_current_role(p, &rPtr, &err)
        _ = harmony_streamable_parser_current_channel(p, &chPtr, &err)
        _ = harmony_streamable_parser_current_content_type(p, &ctPtr, &err)
        _ = harmony_streamable_parser_current_recipient(p, &recPtr, &err)
        _ = harmony_streamable_parser_last_content_delta(p, &deltaPtr, &err)
        let role = rPtr.map { String(cString: $0) } ?? "(nil)"
        let channel = chPtr.map { String(cString: $0) } ?? "(nil)"
        let ctype = ctPtr.map { String(cString: $0) } ?? "(nil)"
        let recip = recPtr.map { String(cString: $0) } ?? "(nil)"
        var deltaInfo = "nil"
        if let d = deltaPtr {
            let s = String(cString: d)
            let preview = s.prefix(200).replacingOccurrences(of: "\n", with: " ")
            deltaInfo = "len=\(s.count) text=\(preview)"
        }
        if let r = rPtr { harmony_string_free(r) }
        if let c = chPtr { harmony_string_free(c) }
        if let t = ctPtr { harmony_string_free(t) }
        if let rc = recPtr { harmony_string_free(rc) }
        if let d = deltaPtr { harmony_string_free(d) }
        log.info("harmony state \(prefix, privacy: .public): role=\(role, privacy: .public) channel=\(channel, privacy: .public) ctype=\(ctype, privacy: .public) recipient=\(recip, privacy: .public) last_delta=\(deltaInfo, privacy: .public)")
    }

    private func logParserState(prefix: String) {
        guard let p = parser else { return }
        var err: UnsafeMutablePointer<CChar>?
        var rPtr: UnsafeMutablePointer<CChar>? = nil
        var chPtr: UnsafeMutablePointer<CChar>? = nil
        var ctPtr: UnsafeMutablePointer<CChar>? = nil
        var recPtr: UnsafeMutablePointer<CChar>? = nil
        var deltaPtr: UnsafeMutablePointer<CChar>? = nil
        _ = harmony_streamable_parser_current_role(p, &rPtr, &err)
        _ = harmony_streamable_parser_current_channel(p, &chPtr, &err)
        _ = harmony_streamable_parser_current_content_type(p, &ctPtr, &err)
        _ = harmony_streamable_parser_current_recipient(p, &recPtr, &err)
        _ = harmony_streamable_parser_last_content_delta(p, &deltaPtr, &err)
        let role = rPtr.map { String(cString: $0) } ?? "(nil)"
        let channel = chPtr.map { String(cString: $0) } ?? "(nil)"
        let ctype = ctPtr.map { String(cString: $0) } ?? "(nil)"
        let recip = recPtr.map { String(cString: $0) } ?? "(nil)"
        var deltaInfo = "nil"
        if let d = deltaPtr {
            let s = String(cString: d)
            let preview = s.prefix(200).replacingOccurrences(of: "\n", with: " ")
            deltaInfo = "len=\(s.count) text=\(preview)"
        }
        if let r = rPtr { harmony_string_free(r) }
        if let c = chPtr { harmony_string_free(c) }
        if let t = ctPtr { harmony_string_free(t) }
        if let rc = recPtr { harmony_string_free(rc) }
        if let d = deltaPtr { harmony_string_free(d) }
        log.debug("harmony state \(prefix, privacy: .public): role=\(role, privacy: .public) channel=\(channel, privacy: .public) ctype=\(ctype, privacy: .public) recipient=\(recip, privacy: .public) last_delta=\(deltaInfo, privacy: .public)")
    }

    private static func isFormattingMarkerText(_ s: String) -> Bool {
        // Markers and header atoms sometimes sampled as plain text by the model.
        if s == "<|channel|>" || s == "<|message|>" || s == "<|start|>" || s == "<|end|>" || s == "<|return|>" || s == "<|call|>" || s == "<|constrain|>" || s == "<|refusal|>" {
            return true
        }
        // Common atoms that appear in headers
        if s == "final" || s == "analysis" || s == "commentary" || s == "assistant" {
            return true
        }
        return false
    }
}
