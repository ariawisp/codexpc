import Foundation
import codexpcEngine
import os

final class MetalRunner {
    private var engine: codexpc_engine_t? = nil
    private static var cacheLock = NSLock()
    private static var engineCache: [String: (eng: codexpc_engine_t, ref: Int)] = [:]
    private var endToken: UInt32 = 0

    init(checkpointPath: String) throws {
        // Simple process-wide engine cache keyed by checkpoint path
        Self.cacheLock.lock()
        if var entry = Self.engineCache[checkpointPath] {
            entry.ref += 1
            Self.engineCache[checkpointPath] = entry
            self.engine = entry.eng
            Self.cacheLock.unlock()
            let ptrStr = String(format: "%p", unsafeBitCast(entry.eng, to: Int.self))
            log.debug("engine cache hit ckpt=\(checkpointPath, privacy: .public) eng=\(ptrStr, privacy: .public) ref=\(entry.ref, privacy: .public)")
        } else {
            Self.cacheLock.unlock()
            var e: codexpc_engine_t? = nil
            let rc = checkpointPath.withCString { cpath in
                codexpc_engine_open(cpath, &e)
            }
            guard rc == 0, let handle = e else { throw NSError(domain: "codexpc", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: "engine open failed: \(rc)"]) }
            self.engine = handle
            Self.cacheLock.lock()
            Self.engineCache[checkpointPath] = (eng: handle, ref: 1)
            Self.cacheLock.unlock()
            let ptrStr = String(format: "%p", unsafeBitCast(handle, to: Int.self))
            log.debug("engine open ckpt=\(checkpointPath, privacy: .public) eng=\(ptrStr, privacy: .public) ref=1")
        }
        var endId: UInt32 = 0
        if let e = self.engine, codexpc_engine_get_end_token_id(e, &endId) == 0 { endToken = endId }
    }

    deinit {
        guard let e = engine else { return }
        // Decrement refcount and close when last user drops
        // We cannot retrieve the key here; rely on pointer identity removal
        Self.cacheLock.lock()
        if let (key, entry) = Self.engineCache.first(where: { $0.value.eng == e }) {
            let newRef = entry.ref - 1
            if newRef <= 0 {
                Self.engineCache.removeValue(forKey: key)
                Self.cacheLock.unlock()
                codexpc_engine_close(e)
            } else {
                Self.engineCache[key] = (eng: e, ref: newRef)
                Self.cacheLock.unlock()
            }
        } else {
            Self.cacheLock.unlock()
            codexpc_engine_close(e)
        }
    }

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
        let seed: UInt64 = 0
        let batch = 16
        var tokens = [UInt32](repeating: 0, count: batch)
        var outCount: Int = 0
        var buf = [UInt8](repeating: 0, count: 2048)
        let harmonyDecoder = try? HarmonyStreamDecoder()
        var usingHarmony = (harmonyDecoder != nil)
        // Clamp temperature to a sane range and handle NaN/infinite
        var temp = temperature
        if !temp.isFinite || temp < 0 { temp = 0.0 }
        if temp > 4.0 { temp = 4.0 }
        log.info("stream start temp=\(temp, privacy: .public) max=\(maxTokens) harmony=\(usingHarmony)")
        var loggedSample = false
        var emptySamples = 0
        var loggedFirstDelta = false
        var sawFinal = false

        while generated < maxTokens && !isCancelled() {
            outCount = 0
            let rc = codexpc_engine_sample(e, temp, seed, Int(batch), &tokens, &outCount)
            if rc != 0 { throw NSError(domain: "codexpc", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: "sample failed: \(rc)"]) }
            if !loggedSample { log.info("sample rc=\(rc) out=\(outCount)"); loggedSample = true }
            if outCount == 0 {
                emptySamples += 1
                if emptySamples % 10 == 0 { log.debug("sample empty count=\(emptySamples)") }
                continue
            }
            for i in 0..<outCount {
                if isCancelled() { return generated }
                let t = tokens[i]
                if !usingHarmony, endToken != 0 && t == endToken { return generated }
                if usingHarmony, let dec = harmonyDecoder {
                    let res = dec.process(token: t)
                    if let d = res.delta, !d.isEmpty {
                        if !loggedFirstDelta { log.info("first delta len=\(d.count)"); loggedFirstDelta = true }
                        sawFinal = true
                        onDelta(d)
                    }
                    if let ev = res.toolEvent { onToolCall?(ev.name, ev.input); return generated }
                    if res.isStop {
                        if sawFinal {
                            return generated
                        } else {
                            // Ignore premature stop until we have final
                            continue
                        }
                    }
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
                    if !s.isEmpty {
                        if !loggedFirstDelta { log.info("first delta len=\(s.count)"); loggedFirstDelta = true }
                        onDelta(s)
                    }
                }
                generated += 1
                // If Harmony produced no deltas across a reasonable number of tokens, fall back to raw decode
                if usingHarmony && !loggedFirstDelta && generated >= 128 {
                    usingHarmony = false
                    log.info("decoder fallback: switching to raw decode after \(generated) tokens without delta")
                }
                if generated >= maxTokens || isCancelled() { return generated }
            }
        }
        return generated
    }

    // Minimal warmup: trigger a tiny sample to compile kernels without emitting logs/deltas
    func warmup() {
        guard let e = engine else { return }
        var toks = [UInt32](repeating: 0, count: 1)
        var outCount: Int = 0
        _ = codexpc_engine_sample(e, 0.0, 0, 1, &toks, &outCount)
    }
}
