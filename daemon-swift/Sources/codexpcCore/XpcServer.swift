import Foundation
import os
import XPC

let log = Logger(subsystem: "com.yourorg.codexpc", category: "daemon")

public final class XpcServer {
    private let serviceName: String
    private let sessionManager = SessionManager()

    public init(serviceName: String) {
        self.serviceName = serviceName
    }

    public func run() {
        log.info("Starting XPC service: \(self.serviceName, privacy: .public)")

        let conn = xpc_connection_create_mach_service(self.serviceName, nil, UInt64(XPC_CONNECTION_MACH_SERVICE_LISTENER))
        xpc_connection_set_event_handler(conn) { client in
            let pid = xpc_connection_get_pid(client)
            log.info("client connected pid=\(pid)")
            xpc_connection_set_event_handler(client) { event in
                Self.handleEvent(connection: client, event: event)
            }
            xpc_connection_resume(client)
        }
        xpc_connection_resume(conn)

        // Keep the runloop alive.
        RunLoop.current.run()
    }

    static func handleEvent(connection: xpc_connection_t, event: xpc_object_t) {
        let type = xpc_get_type(event)
        if type == XPC_TYPE_ERROR {
            if xpc_equal(event, XPC_ERROR_CONNECTION_INVALID) {
                log.debug("client connection invalid")
                SessionManager.shared.cancelAll(forConnection: connection)
            } else if xpc_equal(event, XPC_ERROR_TERMINATION_IMMINENT) {
                log.debug("termination imminent")
            } else {
                log.debug("xpc error event")
            }
            return
        }

        guard type == XPC_TYPE_DICTIONARY else {
            log.error("unexpected xpc type")
            return
        }

        let req = XpcMessage(event)
        guard let msgType = req.string("type"), let reqId = req.string("req_id") else {
            log.error("missing type/req_id")
            return
        }

        // Validate proto_version (expect 1)
        if let pv = req.uint64("proto_version"), pv != 1 {
            let msg = xpc_dictionary_create(nil, nil, 0)
            xpc_dictionary_set_string(msg, "service", "codexpc")
            xpc_dictionary_set_uint64(msg, "proto_version", 1)
            xpc_dictionary_set_string(msg, "req_id", reqId)
            xpc_dictionary_set_uint64(msg, "ts_ns", UInt64(DispatchTime.now().uptimeNanoseconds))
            xpc_dictionary_set_string(msg, "type", "error")
            xpc_dictionary_set_string(msg, "code", "unsupported_protocol")
            xpc_dictionary_set_string(msg, "message", "expected proto_version=1")
            xpc_connection_send_message(connection, msg)
            return
        }

        log.debug("recv msg type=\(msgType, privacy: .public) req_id=\(reqId, privacy: .public)")
        switch msgType {
        case "create":
            SessionManager.shared.handleCreate(connection: connection, req: req, reqId: reqId)
        case "cancel":
            SessionManager.shared.handleCancel(reqId: reqId)
        case "health":
            log.debug("health ping req_id=\(reqId, privacy: .public)")
            let msg = xpc_dictionary_create(nil, nil, 0)
            xpc_dictionary_set_string(msg, "service", "codexpc")
            xpc_dictionary_set_uint64(msg, "proto_version", 1)
            xpc_dictionary_set_string(msg, "req_id", reqId)
            xpc_dictionary_set_uint64(msg, "ts_ns", UInt64(DispatchTime.now().uptimeNanoseconds))
            xpc_dictionary_set_string(msg, "type", "health.ok")
            xpc_connection_send_message(connection, msg)
        default:
            log.error("unknown message type: \(msgType, privacy: .public)")
        }
    }
}

final class XpcMessage {
    let obj: xpc_object_t
    init(_ o: xpc_object_t) { obj = o }
    func string(_ key: String) -> String? {
        guard let cstr = xpc_dictionary_get_string(obj, key) else { return nil }
        return String(cString: cstr)
    }
    func uint64(_ key: String) -> UInt64? {
        return xpc_dictionary_get_uint64(obj, key)
    }
    func double(_ key: String) -> Double? {
        return xpc_dictionary_get_double(obj, key)
    }
    func dict(_ key: String) -> xpc_object_t? {
        return xpc_dictionary_get_value(obj, key)
    }
    func object(_ key: String) -> xpc_object_t? {
        return xpc_dictionary_get_value(obj, key)
    }
}
