import Foundation
import codexpcEngine

final class MetalRunner {
    private var engine: codexpc_engine_t? = nil
    private var endToken: UInt32 = 0

    init(checkpointPath: String) throws {
        var e: codexpc_engine_t? = nil
        let rc = checkpointPath.withCString { cpath in
            codexpc_engine_open(cpath, &e)
        }
        guard rc == 0, let handle = e else { throw NSError(domain: "codexpc", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: "engine open failed: \(rc)"]) }
        engine = handle
        var endId: UInt32 = 0
        if codexpc_engine_get_end_token_id(handle, &endId) == 0 { endToken = endId }
    }

    deinit { if let e = engine { codexpc_engine_close(e) } }

    func reset() throws {
        guard let e = engine else { return }
        let rc = codexpc_engine_reset(e)
        if rc != 0 { throw NSError(domain: "codexpc", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: "reset failed: \(rc)"]) }
    }

    // Appends text and returns number of tokens appended
    func append(text: String) throws -> Int {
        guard let e = engine else { return 0 }
        var appended: Int = 0
        let rc = text.withCString { cstr in
            codexpc_engine_append_chars(e, cstr, strlen(cstr), &appended)
        }
        if rc != 0 { throw NSError(domain: "codexpc", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: "append failed: \(rc)"]) }
        return appended
    }

    func appendSystemFormatted(_ instructions: String, formatter: HarmonyFormatter) throws -> Int {
        guard let e = engine else { return 0 }
        return try formatter.appendSystem(to: e, instructions: instructions)
    }

    func appendSystemAndUserFormatted(_ instructions: String?, userParts: [String], formatter: HarmonyFormatter) throws -> Int {
        guard let e = engine else { return 0 }
        return try formatter.appendSystemAndUser(to: e, instructions: instructions, userParts: userParts)
    }

    // Appends a pre-built Harmony conversation JSON via the formatter
    func appendConversationJSON(conversationJson: String, nextRole: String = "assistant", formatter: HarmonyFormatter) throws -> Int {
        guard let e = engine else { return 0 }
        return try formatter.appendConversationJSON(to: e, conversationJson: conversationJson, nextRole: nextRole)
    }

    // Streams tokens, calling onDelta with decoded text, and returns number of tokens generated
    func stream(temperature: Float, maxTokens: Int, isCancelled: @escaping () -> Bool, onDelta: @escaping (String) -> Void, onToolCall: ((String, String) -> Void)? = nil) throws -> Int {
        guard let e = engine else { return 0 }
        var generated = 0
        var seed: UInt64 = 0
        let batch = 16
        var tokens = [UInt32](repeating: 0, count: batch)
        var outCount: Int = 0
        var buf = [UInt8](repeating: 0, count: 2048)
        let useStub = (ProcessInfo.processInfo.environment["HARMONY_FFI_STUB"] == "1")
        let forceRaw = (ProcessInfo.processInfo.environment["CODEXPC_FORCE_RAW_DECODE"] == "1")
        let harmonyDecoder = (useStub || forceRaw) ? nil : (try? HarmonyStreamDecoder())

        while generated < maxTokens && !isCancelled() {
            outCount = 0
            let rc = codexpc_engine_sample(e, temperature, seed, Int(batch), &tokens, &outCount)
            if rc != 0 { throw NSError(domain: "codexpc", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: "sample failed: \(rc)"]) }
            if outCount == 0 { break }
            for i in 0..<outCount {
                if isCancelled() { return generated }
                let t = tokens[i]
                if endToken != 0 && t == endToken { return generated }
                if let dec = harmonyDecoder {
                    let res = dec.process(token: t)
                    if let d = res.delta, !d.isEmpty { onDelta(d) }
                    if let ev = res.toolEvent { onToolCall?(ev.name, ev.input) }
                } else {
                    var required: Int = 0
                    var drc = codexpc_engine_decode_token(e, t, &buf, buf.count, &required)
                    if drc == -2 { // grow buffer
                        buf = [UInt8](repeating: 0, count: required)
                        drc = codexpc_engine_decode_token(e, t, &buf, buf.count, &required)
                    }
                    if drc != 0 {
                        // Skip undecodable token; continue streaming
                        continue
                    }
                    let s = String(bytes: buf.prefix(required), encoding: .utf8) ?? ""
                    if !s.isEmpty { onDelta(s) }
                }
                generated += 1
                if generated >= maxTokens || isCancelled() { return generated }
            }
        }
        return generated
    }
}
