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

    func appendSystemAndUserFormatted(_ instructions: String?, userParts: [String], formatter: HarmonyFormatter, toolsJson: String? = nil, primeWith decoder: HarmonyStreamDecoder? = nil) throws -> Int {
        guard let e = engine else { return 0 }
        return try formatter.appendSystemAndUser(to: e, instructions: instructions, userParts: userParts, toolsJson: toolsJson, primeParser: decoder?.rawParser)
    }

    // Appends a pre-built Harmony conversation JSON via the formatter
    func appendConversationJSON(conversationJson: String, nextRole: String = "assistant", formatter: HarmonyFormatter, toolsJson: String? = nil, primeWith decoder: HarmonyStreamDecoder? = nil) throws -> Int {
        guard let e = engine else { return 0 }
        return try formatter.appendConversationJSON(to: e, conversationJson: conversationJson, nextRole: nextRole, toolsJson: toolsJson, primeParser: decoder?.rawParser)
    }

    func appendToolMessage(toolName: String, output: String, formatter: HarmonyFormatter) throws -> Int {
        guard let e = engine else { return 0 }
        return try formatter.appendToolMessage(to: e, toolName: toolName, output: output)
    }

    func appendMessages(_ messages: [HarmonyFormatter.HarmonyMsg], formatter: HarmonyFormatter, toolsJson: String? = nil, primeWith decoder: HarmonyStreamDecoder? = nil) throws -> Int {
        guard let e = engine else { return 0 }
        return try formatter.appendMessages(to: e, messages: messages, toolsJson: toolsJson, primeParser: decoder?.rawParser)
    }

    func appendTokens(_ tokens: [UInt32]) throws -> Int {
        guard let e = engine else { return 0 }
        if tokens.isEmpty { return 0 }
        var toks = tokens
        let rc = toks.withUnsafeMutableBufferPointer { bp -> Int32 in
            if let base = bp.baseAddress {
                return codexpc_engine_append_tokens(e, base, bp.count)
            }
            return 0
        }
        if rc != 0 { throw NSError(domain: "codexpc", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: "append tokens failed: \(rc)"]) }
        return tokens.count
    }

    // Streams tokens, calling onDelta with decoded text, and returns number of tokens generated
    func stream(temperature: Float, maxTokens: Int, isCancelled: @escaping () -> Bool, onDelta: @escaping (String) -> Void, onToolCall: ((String, String, String) -> Void)? = nil, using decoder: HarmonyStreamDecoder? = nil) throws -> Int {
        guard let e = engine else { return 0 }
        var generated = 0
        var tokensSinceDelta = 0
        var finalLen = 0
        let seed: UInt64 = 0
        let batch = 16
        var tokens = [UInt32](repeating: 0, count: batch)
        var outCount: Int = 0
        let harmonyDecoder = try (decoder ?? HarmonyStreamDecoder())
        // One-time check: verify Harmony vs GPT-OSS special token IDs align
        do {
            var ids: [(String, Int32, UInt32, [UInt32])] = []
            func q(_ name: String, _ typ: Int32) {
                var gid: UInt32 = 0
                _ = codexpc_engine_get_special_token_id(e, typ, &gid)
                let hids = harmonyDecoder.encode(text: name, allowedSpecial: [name]) // allow this special passthrough
                ids.append((name, typ, gid, hids))
            }
            q("<|start|>", 2)
            q("<|message|>", 3)
            q("<|end|>", 4)
            q("<|return|>", 1)
            q("<|channel|>", 7)
            q("<|call|>", 8)
            q("<|constrain|>", 6)
            q("<|refusal|>", 5)
            var lines: [String] = []
            for (name, typ, gid, hids) in ids {
                let hid = hids.first.map { String($0) } ?? "(none)"
                lines.append("\(name) type=\(typ) gptoss=\(gid) harmony=\(hid)")
            }
            log.info("special token ids: \(lines.joined(separator: "; "), privacy: .public)")
            let helloIds = harmonyDecoder.encode(text: "Hello")
            log.info("harmony encode('Hello') -> \(helloIds.map(String.init).joined(separator: ", "), privacy: .public)")
        }
        // Clamp temperature to a sane range and handle NaN/infinite
        var temp = temperature
        if !temp.isFinite || temp < 0 { temp = 0.0 }
        if temp > 4.0 { temp = 4.0 }
        log.info("stream start temp=\(temp, privacy: .public) max=\(maxTokens) harmony=true")
        var loggedSample = false
        var emptySamples = 0
        var loggedFirstDelta = false

        while generated < maxTokens && !isCancelled() {
            outCount = 0
            let rc = codexpc_engine_sample(e, temp, seed, Int(batch), &tokens, &outCount)
            if rc != 0 { throw NSError(domain: "codexpc", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: "sample failed: \(rc)"]) }
            if !loggedSample { log.info("sample rc=\(rc) out=\(outCount)"); loggedSample = true }
            if outCount == 0 {
                emptySamples += 1
                // If the engine produced at least one token previously and now reports none,
                // consider the sequence ended and flush EOS into the Harmony parser so it can
                // surface any pending final delta and STOP.
                if generated > 0 {
                    log.info("engine idle after \(generated) tokens; flushing EOS")
                    let res = harmonyDecoder.processEOS()
                    if let d = res.delta, !d.isEmpty {
                        if !loggedFirstDelta { log.info("first delta len=\(d.count)"); loggedFirstDelta = true }
                        onDelta(d)
                    }
                    if let ev = res.toolEvent { onToolCall?(ev.name, ev.input, ev.callId) }
                    return generated
                }
                // Otherwise, keep waiting for first tokens and try again.
                if emptySamples % 10 == 0 { log.debug("sample empty count=\(emptySamples)") }
                continue
            }
            // For visibility, decode and log the first few tokens when no deltas yet.
            if !loggedFirstDelta {
                let preview = min(outCount, 8)
                var parts: [String] = []
                for i in 0..<preview {
                    let t = tokens[i]
                    var needed: Int = 0
                    let rc0 = codexpc_engine_decode_token(e, t, nil, 0, &needed)
                    var s = ""
                    if rc0 == -2 && needed > 0 {
                        var buf = [UInt8](repeating: 0, count: needed)
                        var need2 = 0
                        let bufCount = buf.count
                        let rc1 = buf.withUnsafeMutableBytes { rawPtr -> Int32 in
                            let base = rawPtr.baseAddress
                            return codexpc_engine_decode_token(e, t, base, bufCount, &need2)
                        }
                        if rc1 == 0 {
                            s = String(bytes: buf.prefix(need2), encoding: .utf8) ?? ""
                        }
                    }
                    let sp = s.replacingOccurrences(of: "\n", with: " ")
                    parts.append("#\(i)=\(t) '" + sp + "'")
                }
                if !parts.isEmpty { log.info("first tokens: \(parts.joined(separator: ", "), privacy: .public)") }
            }

            for i in 0..<outCount {
                if isCancelled() { return generated }
                let t = tokens[i]
                let res = harmonyDecoder.process(token: t)
                if let d = res.delta, !d.isEmpty {
                    if !loggedFirstDelta { log.info("first delta len=\(d.count)"); loggedFirstDelta = true }
                    onDelta(d)
                    tokensSinceDelta = 0
                    finalLen += d.count
                }
                if let ev = res.toolEvent { onToolCall?(ev.name, ev.input, ev.callId); return generated }
                if res.isStop { return generated }
                generated += 1
                tokensSinceDelta += 1
                if !loggedFirstDelta && tokensSinceDelta == 128 {
                    log.info("no final deltas yet after 128 tokens; dumping parser state")
                    harmonyDecoder.logInfoState(prefix: "no_final_deltas_128")
                } else if !loggedFirstDelta && tokensSinceDelta % 512 == 0 {
                    log.info("still waiting for final deltas; tokens=\(tokensSinceDelta)")
                }
                // If we've emitted some final text but made no progress after a while, flush EOS to finish
                if finalLen > 0 && tokensSinceDelta >= 64 {
                    log.info("no progress in final channel after \(tokensSinceDelta) tokens; flushing EOS")
                    let res = harmonyDecoder.processEOS()
                    if let d = res.delta, !d.isEmpty { onDelta(d) }
                    if let ev = res.toolEvent { onToolCall?(ev.name, ev.input, ev.callId) }
                    return generated
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
