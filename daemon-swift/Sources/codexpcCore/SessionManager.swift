import Foundation
import os
import XPC

final class SessionManager {
    static let shared = SessionManager()
    static let maxSessions = 4

    private var sessions: [String: Session] = [:]
    private var reqToConn: [String: UInt] = [:]
    private var connToReqs: [UInt: Set<String>] = [:]
    private let lock = NSLock()

    func handleCreate(connection: xpc_connection_t, req: XpcMessage, reqId: String) {
        log.debug("create session req_id=\(reqId, privacy: .public)")
        lock.lock()
        if sessions.count >= Self.maxSessions {
            lock.unlock()
            let msg = xpc_dictionary_create(nil, nil, 0)
            xpc_dictionary_set_string(msg, "service", "codexpc")
            xpc_dictionary_set_uint64(msg, "proto_version", 1)
            xpc_dictionary_set_string(msg, "req_id", reqId)
            xpc_dictionary_set_uint64(msg, "ts_ns", UInt64(DispatchTime.now().uptimeNanoseconds))
            xpc_dictionary_set_string(msg, "type", "error")
            xpc_dictionary_set_string(msg, "code", "over_capacity")
            xpc_dictionary_set_string(msg, "message", "too many concurrent sessions")
            xpc_connection_send_message(connection, msg)
            log.error("over capacity; rejecting req_id=\(reqId, privacy: .public)")
            return
        }
        let s = Session(reqId: reqId, connection: connection, req: req) { [weak self] rid in
            guard let self = self else { return }
            self.lock.lock(); defer { self.lock.unlock() }
            self.sessions.removeValue(forKey: rid)
            if let cid = self.reqToConn.removeValue(forKey: rid) {
                var set = self.connToReqs[cid] ?? []
                set.remove(rid)
                if set.isEmpty { self.connToReqs.removeValue(forKey: cid) } else { self.connToReqs[cid] = set }
            }
            log.debug("session finished req_id=\(rid, privacy: .public)")
        }
        sessions[reqId] = s
        let cid: UInt = unsafeBitCast(connection, to: UInt.self)
        reqToConn[reqId] = cid
        var set = connToReqs[cid] ?? []
        set.insert(reqId)
        connToReqs[cid] = set
        lock.unlock()
        s.start()
    }

    func handleCancel(reqId: String) {
        lock.lock(); defer { lock.unlock() }
        sessions[reqId]?.cancel()
        log.debug("cancel signaled req_id=\(reqId, privacy: .public)")
    }

    func cancelAll(forConnection connection: xpc_connection_t) {
        let cid: UInt = unsafeBitCast(connection, to: UInt.self)
        lock.lock(); let reqs = connToReqs[cid] ?? []; lock.unlock()
        for rid in reqs { handleCancel(reqId: rid) }
        lock.lock(); connToReqs.removeValue(forKey: cid); lock.unlock()
        log.debug("cancelled all sessions for connection cid=\(cid)")
    }
}

final class Session {
    private let reqId: String
    private let connection: xpc_connection_t
    private var cancelled = false
    private let req: XpcMessage
    private let onFinish: (String) -> Void
    private let startNs: UInt64
    private let allowTools: Bool

    init(reqId: String, connection: xpc_connection_t, req: XpcMessage, onFinish: @escaping (String) -> Void) {
        self.reqId = reqId
        self.connection = connection
        self.req = req
        self.onFinish = onFinish
        self.startNs = DispatchTime.now().uptimeNanoseconds
        self.allowTools = ToolExecutor.Config.enabled
    }

    func start() {
        // Feature negotiation
        var features = ["health", "text_input", "harmony_system", "token_usage"]
        let toolsPresent = (req.object("tools") != nil)
        if toolsPresent { features.append("tools") }
        let reasoningPresent = (req.object("reasoning") != nil)
        if reasoningPresent { features.append("reasoning") }

        sendCreated(features: features)

        // Parse fields
        guard let checkpoint = req.string("checkpoint_path") else {
            sendError(code: "bad_request", message: "missing checkpoint_path"); return
        }
        let instructions = req.string("instructions") ?? ""
        var maxTokens = 0 // 0 = unlimited until EOS
        if let maxTok = req.uint64("max_output_tokens") { maxTokens = Int(maxTok) }
        var temperature: Float = 0.0
        if let sampling = req.dict("sampling") { temperature = Float(xpc_dictionary_get_double(sampling, "temperature")) }
        if let tflat = req.double("temperature") { temperature = Float(tflat) }

        log.debug("session start req_id=\(self.reqId, privacy: .public) ckpt=\(checkpoint, privacy: .public) temp=\(temperature, privacy: .private(mask: .hash)) max_tokens=\(maxTokens)")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                try self.runSession(checkpoint: checkpoint, instructions: instructions, maxTokens: maxTokens, temperature: temperature, toolsPresent: toolsPresent)
            } catch {
                log.error("engine error req_id=\(self.reqId, privacy: .public) error=\(String(describing: error), privacy: .public)")
                self.sendError(code: "engine_error", message: String(describing: error))
                let durMs = Double(DispatchTime.now().uptimeNanoseconds - self.startNs) / 1_000_000.0
                log.info("session duration_ms=\(durMs, privacy: .public) req_id=\(self.reqId, privacy: .public)")
                self.onFinish(self.reqId)
            }
        }
    }

    private func runSession(checkpoint: String, instructions: String, maxTokens: Int, temperature: Float, toolsPresent: Bool) throws {
        let runner = try MetalRunner(checkpointPath: checkpoint)
        try runner.reset()
            var inputTokens: UInt64 = 0
            // Prefer a prebuilt Harmony conversation JSON if provided
            if let convPtr = xpc_dictionary_get_string(req.obj, "harmony_conversation") {
                let conv = String(cString: convPtr)
                let fmt = try HarmonyFormatter()
                let appended = try runner.appendConversationJSON(conversationJson: conv, nextRole: "assistant", formatter: fmt)
                inputTokens += UInt64(appended)
                log.info("harmony append (json) tokens=\(appended)")
            } else {
                var userParts: [String] = []
                if let arr = req.object("input"), xpc_get_type(arr) == XPC_TYPE_ARRAY {
                    _ = xpc_array_apply(arr) { (_, item) -> Bool in
                        if xpc_get_type(item) == XPC_TYPE_DICTIONARY {
                            if let tptr = xpc_dictionary_get_string(item, "text") {
                                let t = String(cString: tptr)
                                userParts.append(t)
                            }
                        }
                        return true
                    }
                }
                if toolsPresent { self.sendToolPlaceholder() }
                let fmt = try HarmonyFormatter()
                let appended = try runner.appendSystemAndUserFormatted(instructions.isEmpty ? nil : instructions, userParts: userParts, formatter: fmt)
                inputTokens += UInt64(appended)
                log.info("harmony append tokens=\(appended) user_parts=\(userParts.count)")
            }
            // No forced tool call path; tools are optional and controlled by ToolExecutor.Config
            let emitter = StreamEmitter(flushIntervalMs: 20, maxBufferBytes: 4096) { [weak self] chunk in
                self?.send(eventType: "output_text.delta", body: ["text": chunk])
            }
            emitter.start()
            var sawDelta = false
            // Test hook: force a single tool call/output if requested via env.
            if let force = ProcessInfo.processInfo.environment["CODEXPC_TEST_FORCE_TOOL"], !force.isEmpty {
                var name = "echo"
                var input = "{}"
                if let idx = force.firstIndex(of: ":") {
                    name = String(force[..<idx])
                    input = String(force[force.index(after: idx)...])
                } else {
                    input = force
                }
                self.sendToolCall(name: name, input: input)
                if self.allowTools {
                    let res = ToolExecutor.executeEnforced(name: name, input: input)
                    if res.ok { self.sendToolOutput(name: name, output: res.output) }
                    else { self.sendToolFailure(name: name, error: res.output) }
                }
            }
            let watchdog = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            watchdog.schedule(deadline: .now() + .seconds(5), repeating: .seconds(5))
            watchdog.setEventHandler { [weak self] in
                guard let self = self else { return }
                if !sawDelta {
                    log.debug("waiting for first tokens req_id=\(self.reqId, privacy: .public)")
                } else {
                    watchdog.cancel()
                }
            }
            watchdog.resume()
            // 0 means unlimited; stream until EOS or cancel
            let effMaxTokens = (maxTokens <= 0) ? Int.max : maxTokens
            let outTok = try runner.stream(temperature: temperature, maxTokens: effMaxTokens, isCancelled: { [weak self] in
                return self?.cancelled ?? true
            }, onDelta: { text in
                if !sawDelta && !text.isEmpty { sawDelta = true }
                emitter.submit(text)
            }, onToolCall: { [weak self] name, input in
                guard let self = self else { return }
                self.sendToolCall(name: name, input: input)
                if self.allowTools {
                    let res = ToolExecutor.executeEnforced(name: name, input: input)
                    if res.ok { self.sendToolOutput(name: name, output: res.output) }
                    else { self.sendToolFailure(name: name, error: res.output) }
                }
            })
            watchdog.cancel()
            emitter.close()
            self.sendCompleted(inputTokens: inputTokens, outputTokens: UInt64(outTok))
        let durMs = Double(DispatchTime.now().uptimeNanoseconds - self.startNs) / 1_000_000.0
        log.debug("session duration_ms=\(durMs, privacy: .public) req_id=\(self.reqId, privacy: .public)")
        self.onFinish(self.reqId)
    }

    func cancel() { cancelled = true }

    private func send(eventType: String, body: [String: Any]) {
        let msg = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_string(msg, "service", "codexpc")
        xpc_dictionary_set_uint64(msg, "proto_version", 1)
        xpc_dictionary_set_string(msg, "req_id", reqId)
        xpc_dictionary_set_uint64(msg, "ts_ns", UInt64(DispatchTime.now().uptimeNanoseconds))
        xpc_dictionary_set_string(msg, "type", eventType)
        for (k, v) in body {
            if let s = v as? String { xpc_dictionary_set_string(msg, k, s) }
            if let u = v as? UInt64 { xpc_dictionary_set_uint64(msg, k, u) }
        }
        xpc_connection_send_message(connection, msg)
    }

    private func sendError(code: String, message: String) {
        send(eventType: "error", body: ["code": code, "message": message])
    }

    private func sendCreated(features: [String]) {
        let msg = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_string(msg, "service", "codexpc")
        xpc_dictionary_set_uint64(msg, "proto_version", 1)
        xpc_dictionary_set_string(msg, "req_id", reqId)
        xpc_dictionary_set_uint64(msg, "ts_ns", UInt64(DispatchTime.now().uptimeNanoseconds))
        xpc_dictionary_set_string(msg, "type", "created")
        let arr = xpc_array_create(nil, 0)
        for f in features {
            f.withCString { c in xpc_array_append_value(arr, xpc_string_create(c)) }
        }
        xpc_dictionary_set_value(msg, "features", arr)
        xpc_connection_send_message(connection, msg)
    }

    private func sendCompleted(inputTokens: UInt64, outputTokens: UInt64) {
        let msg = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_string(msg, "service", "codexpc")
        xpc_dictionary_set_uint64(msg, "proto_version", 1)
        xpc_dictionary_set_string(msg, "req_id", reqId)
        xpc_dictionary_set_uint64(msg, "ts_ns", UInt64(DispatchTime.now().uptimeNanoseconds))
        xpc_dictionary_set_string(msg, "type", "completed")
        xpc_dictionary_set_string(msg, "response_id", reqId)
        let usage = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_uint64(usage, "input_tokens", inputTokens)
        xpc_dictionary_set_uint64(usage, "output_tokens", outputTokens)
        xpc_dictionary_set_uint64(usage, "total_tokens", inputTokens + outputTokens)
        xpc_dictionary_set_value(msg, "token_usage", usage)
        xpc_connection_send_message(connection, msg)
    }

    private func sendToolPlaceholder() {
        let msg = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_string(msg, "service", "codexpc")
        xpc_dictionary_set_uint64(msg, "proto_version", 1)
        xpc_dictionary_set_string(msg, "req_id", reqId)
        xpc_dictionary_set_uint64(msg, "ts_ns", UInt64(DispatchTime.now().uptimeNanoseconds))
        xpc_dictionary_set_string(msg, "type", "output_item.done")
        let item = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_string(item, "type", "tool_call.placeholder")
        xpc_dictionary_set_string(item, "status", "skipped")
        xpc_dictionary_set_string(item, "name", "placeholder")
        xpc_dictionary_set_string(item, "input", "{}")
        xpc_dictionary_set_value(msg, "item", item)
        xpc_connection_send_message(connection, msg)
    }

    private func sendToolCall(name: String, input: String) {
        let msg = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_string(msg, "service", "codexpc")
        xpc_dictionary_set_uint64(msg, "proto_version", 1)
        xpc_dictionary_set_string(msg, "req_id", reqId)
        xpc_dictionary_set_uint64(msg, "ts_ns", UInt64(DispatchTime.now().uptimeNanoseconds))
        xpc_dictionary_set_string(msg, "type", "output_item.done")
        let item = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_string(item, "type", "tool_call")
        xpc_dictionary_set_string(item, "status", "requested")
        xpc_dictionary_set_string(item, "name", name)
        xpc_dictionary_set_string(item, "input", input)
        if Session.isValidJson(input) {
            xpc_dictionary_set_string(item, "arguments", input)
        }
        xpc_dictionary_set_value(msg, "item", item)
        xpc_connection_send_message(connection, msg)
    }

    private func sendToolOutput(name: String, output: String) {
        let msg = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_string(msg, "service", "codexpc")
        xpc_dictionary_set_uint64(msg, "proto_version", 1)
        xpc_dictionary_set_string(msg, "req_id", reqId)
        xpc_dictionary_set_uint64(msg, "ts_ns", UInt64(DispatchTime.now().uptimeNanoseconds))
        xpc_dictionary_set_string(msg, "type", "output_item.done")
        let item = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_string(item, "type", "tool_call.output")
        xpc_dictionary_set_string(item, "status", "completed")
        xpc_dictionary_set_string(item, "name", name)
        xpc_dictionary_set_string(item, "output", output)
        xpc_dictionary_set_value(msg, "item", item)
        xpc_connection_send_message(connection, msg)
    }

    private func sendToolFailure(name: String, error: String) {
        let msg = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_string(msg, "service", "codexpc")
        xpc_dictionary_set_uint64(msg, "proto_version", 1)
        xpc_dictionary_set_string(msg, "req_id", reqId)
        xpc_dictionary_set_uint64(msg, "ts_ns", UInt64(DispatchTime.now().uptimeNanoseconds))
        xpc_dictionary_set_string(msg, "type", "output_item.done")
        let item = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_string(item, "type", "tool_call.output")
        xpc_dictionary_set_string(item, "status", "failed")
        xpc_dictionary_set_string(item, "name", name)
        xpc_dictionary_set_string(item, "output", error)
        xpc_dictionary_set_value(msg, "item", item)
        xpc_connection_send_message(connection, msg)
    }

    private static func isValidJson(_ s: String) -> Bool {
        guard let data = s.data(using: .utf8) else { return false }
        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [])
            return true
        } catch { return false }
    }
}
