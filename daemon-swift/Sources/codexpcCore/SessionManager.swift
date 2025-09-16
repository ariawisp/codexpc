import Foundation
import os
import XPC

final class SessionManager {
    static let shared = SessionManager()

    private var sessions: [String: Session] = [:]
    private let lock = NSLock()

    func handleCreate(connection: xpc_connection_t, req: XpcMessage, reqId: String) {
        let s = Session(reqId: reqId, connection: connection, req: req) { [weak self] rid in
            guard let self = self else { return }
            self.lock.lock(); self.sessions.removeValue(forKey: rid); self.lock.unlock()
        }
        lock.lock(); sessions[reqId] = s; lock.unlock()
        s.start()
    }

    func handleCancel(reqId: String) {
        lock.lock(); defer { lock.unlock() }
        sessions[reqId]?.cancel()
    }
}

final class Session {
    private let reqId: String
    private let connection: xpc_connection_t
    private var cancelled = false
    private let req: XpcMessage
    private let onFinish: (String) -> Void

    init(reqId: String, connection: xpc_connection_t, req: XpcMessage, onFinish: @escaping (String) -> Void) {
        self.reqId = reqId
        self.connection = connection
        self.req = req
        self.onFinish = onFinish
    }

    func start() {
        send(eventType: "created", body: [:])

        // Parse fields
        guard let checkpoint = req.string("checkpoint_path") else {
            sendError(code: "bad_request", message: "missing checkpoint_path"); return
        }
        let instructions = req.string("instructions") ?? ""
        var maxTokens = 128
        if let maxTok = req.uint64("max_output_tokens") { maxTokens = Int(maxTok) }
        var temperature: Float = 0.0
        if let sampling = req.dict("sampling") { temperature = Float(xpc_dictionary_get_double(sampling, "temperature")) }
        if let tflat = req.double("temperature") { temperature = Float(tflat) }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let runner = try MetalRunner(checkpointPath: checkpoint)
                try runner.reset()
                if !instructions.isEmpty {
                    let fmt = HarmonyFormatter()
                    try runner.appendSystemFormatted(instructions, formatter: fmt)
                }
                let emitter = StreamEmitter(flushIntervalMs: 20, maxBufferBytes: 4096) { [weak self] chunk in
                    self?.send(eventType: "output_text.delta", body: ["text": chunk])
                }
                emitter.start()
                try runner.stream(temperature: temperature, maxTokens: maxTokens, isCancelled: { [weak self] in
                    return self?.cancelled ?? true
                }, onDelta: { text in
                    emitter.submit(text)
                })
                emitter.close()
            } catch {
                self.sendError(code: "engine_error", message: String(describing: error))
            }
            self.send(eventType: "completed", body: ["response_id": self.reqId])
            self.onFinish(self.reqId)
        }
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
}
