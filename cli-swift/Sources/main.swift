import Foundation
import XPC
import Dispatch

struct Args {
    var service = "com.yourorg.codexpc"
    var checkpoint = ""
    var prompt = ""
    var temperature: Double = 0.0
    var maxTokens: UInt64 = 0
    var health = false
    var handshake = false
}

func parseArgs() -> Args {
    var a = Args()
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let k = it.next() {
        switch k {
        case "--service": a.service = it.next() ?? a.service
        case "--checkpoint": a.checkpoint = it.next() ?? a.checkpoint
        case "--prompt": a.prompt = it.next() ?? a.prompt
        case "--temperature": a.temperature = Double(it.next() ?? "0") ?? 0.0
        case "--max-tokens": a.maxTokens = UInt64(it.next() ?? "0") ?? 0
        case "--health": a.health = true
        case "--handshake": a.handshake = true
        default: break
        }
    }
    return a
}

let args = parseArgs()
if !(args.health || args.handshake) && args.checkpoint.isEmpty {
    fputs("usage: codexpc-cli [--health] [--handshake] --checkpoint <path> [--prompt <text>] [--service <name>] [--temperature <float>] [--max-tokens <n (0=unlimited)>]\n", stderr)
    exit(2)
}

let reqId = UUID().uuidString
let conn = xpc_connection_create_mach_service(args.service, nil, 0)
xpc_connection_set_event_handler(conn) { ev in
    if xpc_get_type(ev) == XPC_TYPE_DICTIONARY {
        guard let rid = xpc_dictionary_get_string(ev, "req_id"), String(cString: rid) == reqId else { return }
        let typ = xpc_dictionary_get_string(ev, "type").map { String(cString: $0) } ?? ""
        switch typ {
        case "health.ok":
            fputs("health: ok\n", stdout)
            exit(0)
        case "handshake.ok":
            var dict: [String: Any] = [:]
            if let enc = xpc_dictionary_get_string(ev, "encoding_name") { dict["encoding_name"] = String(cString: enc) }
            if let st = xpc_dictionary_get_value(ev, "special_tokens"), xpc_get_type(st) == XPC_TYPE_ARRAY {
                var arr: [String] = []
                _ = xpc_array_apply(st) { (_, v) -> Bool in
                    if xpc_get_type(v) == XPC_TYPE_STRING, let p = xpc_string_get_string_ptr(v) {
                        arr.append(String(cString: p))
                    }
                    return true
                }
                dict["special_tokens"] = arr
            }
            if let sta = xpc_dictionary_get_value(ev, "stop_tokens_for_assistant_actions"), xpc_get_type(sta) == XPC_TYPE_ARRAY {
                var arr: [UInt64] = []
                _ = xpc_array_apply(sta) { (_, v) -> Bool in
                    if xpc_get_type(v) == XPC_TYPE_UINT64 { arr.append(xpc_uint64_get_value(v)) }
                    return true
                }
                dict["stop_tokens_for_assistant_actions"] = arr
            }
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]), let s = String(data: data, encoding: .utf8) {
                fputs("\n\(s)\n", stdout)
            } else {
                fputs("handshake: ok\n", stdout)
            }
            exit(0)
        case "created":
            fputs("[created]\n", stdout)
        case "output_text.delta":
            let t = xpc_dictionary_get_string(ev, "text").map { String(cString: $0) } ?? ""
            fputs(t, stdout)
            fflush(stdout)
        case "completed":
            fputs("\n[completed]\n", stdout)
            exit(0)
        case "output_item.done":
            if let item = xpc_dictionary_get_value(ev, "item") {
                let itype = xpc_dictionary_get_string(item, "type").map { String(cString: $0) } ?? ""
                let status = xpc_dictionary_get_string(item, "status").map { String(cString: $0) } ?? ""
                let name = xpc_dictionary_get_string(item, "name").map { String(cString: $0) } ?? ""
                if itype == "tool_call" || itype == "tool_call.placeholder" {
                    let input = xpc_dictionary_get_string(item, "input").map { String(cString: $0) }
                    let args = xpc_dictionary_get_string(item, "arguments").map { String(cString: $0) }
                    let show = input ?? args ?? ""
                    fputs("\n[tool_call] name=\(name) status=\(status) input=\(show)\n", stdout)
                } else if itype == "tool_call.output" {
                    let output = xpc_dictionary_get_string(item, "output").map { String(cString: $0) } ?? ""
                    fputs("\n[tool_call.output] name=\(name) status=\(status) output=\(output)\n", stdout)
                }
            }
        case "error", "handshake.error":
            let code = xpc_dictionary_get_string(ev, "code").map { String(cString: $0) } ?? ""
            let msg = xpc_dictionary_get_string(ev, "message").map { String(cString: $0) } ?? ""
            fputs("error: \(code): \(msg)\n", stderr)
            exit(1)
        default:
            break
        }
    }
}
xpc_connection_resume(conn)

let msg = xpc_dictionary_create(nil, nil, 0)
xpc_dictionary_set_string(msg, "service", args.service)
xpc_dictionary_set_uint64(msg, "proto_version", 1)
xpc_dictionary_set_string(msg, "type", args.health ? "health" : (args.handshake ? "handshake" : "create"))
xpc_dictionary_set_string(msg, "req_id", reqId)
xpc_dictionary_set_string(msg, "model", "gpt-oss")
if !(args.health || args.handshake) {
    xpc_dictionary_set_string(msg, "checkpoint_path", args.checkpoint)
    // Prefer sending the prompt as a user input to encourage 'final' channel output
    if !args.prompt.isEmpty {
        let arr = xpc_array_create(nil, 0)
        let item = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_string(item, "text", args.prompt)
        xpc_array_append_value(arr, item)
        xpc_dictionary_set_value(msg, "input", arr)
    }
    // Keep instructions empty for this CLI to avoid double-including prompt in system
    xpc_dictionary_set_string(msg, "instructions", "")
    xpc_dictionary_set_uint64(msg, "max_output_tokens", args.maxTokens)
    let sampling = xpc_dictionary_create(nil, nil, 0)
    xpc_dictionary_set_double(sampling, "temperature", args.temperature)
    xpc_dictionary_set_value(msg, "sampling", sampling)
}
xpc_connection_send_message(conn, msg)

RunLoop.current.run()
