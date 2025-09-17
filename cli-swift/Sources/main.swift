import Foundation
import XPC

struct Args {
    var service = "com.yourorg.codexpc"
    var checkpoint = ""
    var prompt = ""
    var temperature: Double = 0.0
    var maxTokens: UInt64 = 128
    var health = false
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
        case "--max-tokens": a.maxTokens = UInt64(it.next() ?? "128") ?? 128
        case "--health": a.health = true
        default: break
        }
    }
    return a
}

let args = parseArgs()
if !args.health && args.checkpoint.isEmpty {
    fputs("usage: codexpc-cli [--health] --checkpoint <path> [--prompt <text>] [--service <name>] [--temperature <float>] [--max-tokens <n>]\n", stderr)
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
        case "created":
            fputs("[created]\n", stdout)
        case "output_text.delta":
            let t = xpc_dictionary_get_string(ev, "text").map { String(cString: $0) } ?? ""
            fputs(t, stdout)
            fflush(stdout)
        case "completed":
            fputs("\n[completed]\n", stdout)
            exit(0)
        case "error":
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
xpc_dictionary_set_string(msg, "type", args.health ? "health" : "create")
xpc_dictionary_set_string(msg, "req_id", reqId)
xpc_dictionary_set_string(msg, "model", "gpt-oss")
if !args.health {
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
