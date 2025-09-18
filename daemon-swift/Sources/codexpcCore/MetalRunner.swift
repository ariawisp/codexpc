import Foundation
import codexpcEngine
import os
import Darwin

// Function pointer types for dynamic engine loading
typealias fn_open_t = @convention(c) (UnsafePointer<CChar>?, UnsafeMutablePointer<codexpc_engine_t?>?) -> Int32
typealias fn_close_t = @convention(c) (codexpc_engine_t?) -> Void
typealias fn_reset_t = @convention(c) (codexpc_engine_t?) -> Int32
typealias fn_append_tokens_t = @convention(c) (codexpc_engine_t?, UnsafePointer<UInt32>?, Int) -> Int32
typealias fn_append_chars_t = @convention(c) (codexpc_engine_t?, UnsafePointer<CChar>?, Int, UnsafeMutablePointer<Int>?) -> Int32
typealias fn_sample_t = @convention(c) (codexpc_engine_t?, Float, UInt64, Int, UnsafeMutablePointer<UInt32>?, UnsafeMutablePointer<Int>?) -> Int32
typealias fn_decode_token_t = @convention(c) (codexpc_engine_t?, UInt32, UnsafeMutableRawPointer?, Int, UnsafeMutablePointer<Int>?) -> Int32
typealias fn_get_end_token_id_t = @convention(c) (codexpc_engine_t?, UnsafeMutablePointer<UInt32>?) -> Int32
typealias fn_get_special_token_id_t = @convention(c) (codexpc_engine_t?, Int32, UnsafeMutablePointer<UInt32>?) -> Int32

// Multi-agent / shared-KV API (optional)
typealias fn_shared_kv_open_t = @convention(c) (codexpc_engine_t?, Int32, UnsafeMutablePointer<OpaquePointer?>?) -> Int32
typealias fn_shared_kv_open_ex_t = @convention(c) (codexpc_engine_t?, Int32, Int32, Int32, UnsafeMutablePointer<OpaquePointer?>?) -> Int32
typealias fn_shared_kv_close_t = @convention(c) (OpaquePointer?) -> Void
typealias fn_agent_open_t = @convention(c) (codexpc_engine_t?, OpaquePointer?, UnsafeMutablePointer<OpaquePointer?>?) -> Int32
typealias fn_agent_close_t = @convention(c) (OpaquePointer?) -> Void
typealias fn_agent_reset_t = @convention(c) (OpaquePointer?) -> Int32
typealias fn_agent_append_tokens_t = @convention(c) (OpaquePointer?, UnsafePointer<UInt32>?, Int) -> Int32
typealias fn_agent_append_chars_t = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, Int, UnsafeMutablePointer<Int>?) -> Int32
typealias fn_agent_set_boundary_t = @convention(c) (OpaquePointer?, Int32) -> Int32
typealias fn_agent_set_logit_mask_t = @convention(c) (OpaquePointer?, UnsafePointer<Int32>?, Int, UnsafePointer<Int32>?, Int) -> Int32
typealias fn_agent_clear_logit_mask_t = @convention(c) (OpaquePointer?) -> Int32
typealias fn_agent_sample_t = @convention(c) (OpaquePointer?, Float, UInt64, Int, UnsafeMutablePointer<UInt32>?, UnsafeMutablePointer<Int>?) -> Int32

struct EngineCalls {
    let open: fn_open_t
    let close: fn_close_t
    let reset: fn_reset_t
    let append_tokens: fn_append_tokens_t
    let append_chars: fn_append_chars_t
    let sample: fn_sample_t
    let decode_token: fn_decode_token_t
    let get_end_token_id: fn_get_end_token_id_t
    let get_special_token_id: fn_get_special_token_id_t
    // optional multi-agent
    let shared_kv_open: fn_shared_kv_open_t?
    let shared_kv_open_ex: fn_shared_kv_open_ex_t?
    let shared_kv_close: fn_shared_kv_close_t?
    let agent_open: fn_agent_open_t?
    let agent_close: fn_agent_close_t?
    let agent_reset: fn_agent_reset_t?
    let agent_append_tokens: fn_agent_append_tokens_t?
    let agent_append_chars: fn_agent_append_chars_t?
    let agent_set_boundary: fn_agent_set_boundary_t?
    let agent_set_logit_mask: fn_agent_set_logit_mask_t?
    let agent_clear_logit_mask: fn_agent_clear_logit_mask_t?
    let agent_sample: fn_agent_sample_t?
}

private func defaultEngineCalls() -> EngineCalls {
    return EngineCalls(
        open: codexpc_engine_open,
        close: codexpc_engine_close,
        reset: codexpc_engine_reset,
        append_tokens: codexpc_engine_append_tokens,
        append_chars: codexpc_engine_append_chars,
        sample: codexpc_engine_sample,
        decode_token: codexpc_engine_decode_token,
        get_end_token_id: codexpc_engine_get_end_token_id,
        get_special_token_id: codexpc_engine_get_special_token_id,
        shared_kv_open: nil, shared_kv_open_ex: nil, shared_kv_close: nil,
        agent_open: nil, agent_close: nil, agent_reset: nil,
        agent_append_tokens: nil, agent_append_chars: nil,
        agent_set_boundary: nil, agent_set_logit_mask: nil,
        agent_clear_logit_mask: nil, agent_sample: nil
    )
}

final class DynamicEngineLoader {
    static func load(path: String) -> EngineCalls? {
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else { return nil }
        func sym<T>(_ name: String, as type: T.Type) -> T? {
            guard let raw = dlsym(handle, name) else { return nil }
            return unsafeBitCast(raw, to: type)
        }
        guard let fOpen = sym("codexpc_engine_open", as: fn_open_t.self),
              let fClose = sym("codexpc_engine_close", as: fn_close_t.self),
              let fReset = sym("codexpc_engine_reset", as: fn_reset_t.self),
              let fAppendTokens = sym("codexpc_engine_append_tokens", as: fn_append_tokens_t.self),
              let fAppendChars = sym("codexpc_engine_append_chars", as: fn_append_chars_t.self),
              let fSample = sym("codexpc_engine_sample", as: fn_sample_t.self),
              let fDecode = sym("codexpc_engine_decode_token", as: fn_decode_token_t.self),
              let fEnd = sym("codexpc_engine_get_end_token_id", as: fn_get_end_token_id_t.self),
              let fSpec = sym("codexpc_engine_get_special_token_id", as: fn_get_special_token_id_t.self)
        else { return nil }
        // Optional multi-agent symbols
        let skvOpen  = sym("codexpc_engine_shared_kv_open", as: fn_shared_kv_open_t.self)
        let skvOpenEx = sym("codexpc_engine_shared_kv_open_ex", as: fn_shared_kv_open_ex_t.self)
        let skvClose = sym("codexpc_engine_shared_kv_close", as: fn_shared_kv_close_t.self)
        let agOpen   = sym("codexpc_engine_agent_open", as: fn_agent_open_t.self)
        let agClose  = sym("codexpc_engine_agent_close", as: fn_agent_close_t.self)
        let agReset  = sym("codexpc_engine_agent_reset", as: fn_agent_reset_t.self)
        let agATok   = sym("codexpc_engine_agent_append_tokens", as: fn_agent_append_tokens_t.self)
        let agAChr   = sym("codexpc_engine_agent_append_chars", as: fn_agent_append_chars_t.self)
        let agBound  = sym("codexpc_engine_agent_set_boundary", as: fn_agent_set_boundary_t.self)
        let agMask   = sym("codexpc_engine_agent_set_logit_mask", as: fn_agent_set_logit_mask_t.self)
        let agClr    = sym("codexpc_engine_agent_clear_logit_mask", as: fn_agent_clear_logit_mask_t.self)
        let agSamp   = sym("codexpc_engine_agent_sample", as: fn_agent_sample_t.self)
        return EngineCalls(open: fOpen, close: fClose, reset: fReset, append_tokens: fAppendTokens, append_chars: fAppendChars, sample: fSample, decode_token: fDecode, get_end_token_id: fEnd, get_special_token_id: fSpec,
                           shared_kv_open: skvOpen, shared_kv_open_ex: skvOpenEx, shared_kv_close: skvClose,
                           agent_open: agOpen, agent_close: agClose, agent_reset: agReset,
                           agent_append_tokens: agATok, agent_append_chars: agAChr,
                           agent_set_boundary: agBound, agent_set_logit_mask: agMask,
                           agent_clear_logit_mask: agClr, agent_sample: agSamp)
    }
}

final class MetalRunner {
    private var engine: codexpc_engine_t? = nil
    private static var calls: EngineCalls = defaultEngineCalls()
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
            // Optional dynamic engine: load from CODEXPC_ENGINE_LIB if set
            if let libPath = getenv("CODEXPC_ENGINE_LIB") {
                let s = String(cString: libPath)
                if let dyn = DynamicEngineLoader.load(path: s) {
                    Self.calls = dyn
                    log.info("using dynamic engine lib=\(s, privacy: .public)")
                } else {
                    log.error("failed to load dynamic engine from \(s, privacy: .public); falling back to default")
                    Self.calls = defaultEngineCalls()
                }
            } else {
                Self.calls = defaultEngineCalls()
            }
            var e: codexpc_engine_t? = nil
            let rc = checkpointPath.withCString { cpath in
                Self.calls.open(cpath, &e)
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
            Self.calls.close(e)
        }
    }

    func reset() throws {
        guard let e = engine else { return }
        let rc = Self.calls.reset(e)
        if rc != 0 { throw NSError(domain: "codexpc", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: "reset failed: \(rc)"]) }
    }

    // Appends text and returns number of tokens appended
    func append(text: String) throws -> Int {
        guard let e = engine else { return 0 }
        var appended: Int = 0
        let rc = text.withCString { cstr in
            Self.calls.append_chars(e, cstr, strlen(cstr), &appended)
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
            return Self.calls.append_tokens(e, base, bp.count)
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
                _ = Self.calls.get_special_token_id(e, typ, &gid)
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
            let rc = Self.calls.sample(e, temp, seed, Int(batch), &tokens, &outCount)
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
                    let rc0 = Self.calls.decode_token(e, t, nil, 0, &needed)
                    var s = ""
                    if rc0 == -2 && needed > 0 {
                        var buf = [UInt8](repeating: 0, count: needed)
                        var need2 = 0
                        let bufCount = buf.count
                        let rc1 = buf.withUnsafeMutableBytes { rawPtr -> Int32 in
                            let base = rawPtr.baseAddress
                            return Self.calls.decode_token(e, t, base, bufCount, &need2)
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
        _ = Self.calls.sample(e, 0.0, 0, 1, &toks, &outCount)
    }

    // --- Optional multi-agent wrappers ---

    struct SharedKV { let raw: OpaquePointer }
    struct Agent { let raw: OpaquePointer }

    func sharedKvOpen(capacityTokens: Int, slots: Int = 1, layout: Int = 0) throws -> SharedKV {
        guard let e = engine else { throw NSError(domain: "codexpc", code: -1, userInfo: [NSLocalizedDescriptionKey: "engine not open"]) }
        var out: OpaquePointer? = nil
        var rc: Int32 = -1
        if let fex = Self.calls.shared_kv_open_ex {
            rc = fex(e, Int32(capacityTokens), Int32(slots), Int32(layout), &out)
        } else if let f = Self.calls.shared_kv_open {
            rc = f(e, Int32(capacityTokens), &out)
        }
        if rc != 0 || out == nil { throw NSError(domain: "codexpc", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: "shared_kv_open failed: \(rc)"]) }
        return SharedKV(raw: out!)
    }

    func sharedKvClose(_ skv: SharedKV) {
        guard let f = Self.calls.shared_kv_close else { return }
        f(skv.raw)
    }

    func agentOpen(_ skv: SharedKV, slot: Int? = nil) throws -> Agent {
        guard let e = engine else { throw NSError(domain: "codexpc", code: -1, userInfo: [NSLocalizedDescriptionKey: "engine not open"]) }
        var out: OpaquePointer? = nil
        var rc: Int32 = -1
        if let s = slot, let fex = Self.calls.agent_open_ex {
            rc = fex(e, skv.raw, Int32(s), &out)
        } else if let f = Self.calls.agent_open {
            rc = f(e, skv.raw, &out)
        }
        if rc != 0 || out == nil { throw NSError(domain: "codexpc", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: "agent_open failed: \(rc)"]) }
        return Agent(raw: out!)
    }

    func agentClose(_ agent: Agent) {
        Self.calls.agent_close?(agent.raw)
    }

    func agentReset(_ agent: Agent) -> Int32 { Self.calls.agent_reset?(agent.raw) ?? -1 }

    func agentAppend(tokens: [UInt32], to agent: Agent) -> Int32 {
        return tokens.withUnsafeBufferPointer { bp in
            if let base = bp.baseAddress { return Self.calls.agent_append_tokens?(agent.raw, base, bp.count) ?? -1 }
            return 0
        }
    }

    func agentAppend(text: String, to agent: Agent) throws -> Int {
        guard let f = Self.calls.agent_append_chars else { return 0 }
        var outCount: Int = 0
        try text.withCString { cstr in
            let rc = f(agent.raw, cstr, text.utf8.count, &outCount)
            if rc != 0 { throw NSError(domain: "codexpc", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: "agent_append_chars failed: \(rc)"]) }
        }
        return outCount
    }

    func agentSetBoundary(_ agent: Agent, atBoundary: Bool) -> Int32 {
        return Self.calls.agent_set_boundary?(agent.raw, atBoundary ? 1 : 0) ?? -1
    }

    func agentSetLogitMask(_ agent: Agent, allowed: [Int32]?, banned: [Int32]?) -> Int32 {
        let aPtr = allowed?.withUnsafeBufferPointer { $0.baseAddress }
        let aLen = Int32(allowed?.count ?? 0)
        let bPtr = banned?.withUnsafeBufferPointer { $0.baseAddress }
        let bLen = Int32(banned?.count ?? 0)
        return Self.calls.agent_set_logit_mask?(agent.raw, aPtr, Int(aLen), bPtr, Int(bLen)) ?? -1
    }

    func agentClearLogitMask(_ agent: Agent) -> Int32 { Self.calls.agent_clear_logit_mask?(agent.raw) ?? -1 }

    func agentSample(_ agent: Agent, temperature: Float, seed: UInt64, maxTokens: Int) throws -> [UInt32] {
        guard let f = Self.calls.agent_sample else { throw NSError(domain: "codexpc", code: -1, userInfo: [NSLocalizedDescriptionKey: "agent_sample symbol not available"]) }
        var buf = [UInt32](repeating: 0, count: maxTokens)
        var outCount: Int = 0
        let rc = f(agent.raw, temperature, seed, maxTokens, &buf, &outCount)
        if rc != 0 { throw NSError(domain: "codexpc", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: "agent_sample failed: \(rc)"]) }
        return Array(buf.prefix(outCount))
    }
}
}
