import Foundation
import codexpcEngine

struct Args {
    var checkpoint = ""
    var prompt = "Hello"
    var tokens: Int = 16
    var temperature: Double = 0.0
}

func parseArgs() -> Args {
    var a = Args()
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let k = it.next() {
        switch k {
        case "--checkpoint": a.checkpoint = it.next() ?? a.checkpoint
        case "--prompt": a.prompt = it.next() ?? a.prompt
        case "--tokens": a.tokens = Int(it.next() ?? "16") ?? 16
        case "--temperature": a.temperature = Double(it.next() ?? "0.0") ?? 0.0
        default: break
        }
    }
    return a
}

let args = parseArgs()
guard !args.checkpoint.isEmpty else {
    fputs("usage: gptoss-smoke --checkpoint <path> [--prompt <text>] [--tokens <n>] [--temperature <float>]\n", stderr)
    exit(2)
}

var engine: codexpc_engine_t? = nil
let rcOpen = args.checkpoint.withCString { c in codexpc_engine_open(c, &engine) }
guard rcOpen == 0, let e = engine else {
    fputs("open failed rc=\(rcOpen)\n", stderr)
    exit(1)
}
defer { codexpc_engine_close(e) }

let rcReset = codexpc_engine_reset(e)
if rcReset != 0 { fputs("reset rc=\(rcReset)\n", stderr) }

var appended: Int = 0
let rcAppend = args.prompt.withCString { c in codexpc_engine_append_chars(e, c, strlen(c), &appended) }
print("append rc=\(rcAppend) tokens=\(appended)")

var endId: UInt32 = 0
let _ = codexpc_engine_get_end_token_id(e, &endId)

let maxT = max(1, args.tokens)
var toks = [UInt32](repeating: 0, count: maxT)
var outCount: Int = 0
let rcSample = codexpc_engine_sample(e, Float(args.temperature), 0, maxT, &toks, &outCount)
print("sample rc=\(rcSample) count=\(outCount)")

var buf = [UInt8](repeating: 0, count: 4096)
var out = ""
for i in 0..<outCount {
    if endId != 0 && toks[i] == endId { print("<END>"); break }
    var required: Int = 0
    var rc = codexpc_engine_decode_token(e, toks[i], &buf, buf.count, &required)
    if rc == -2 && required > buf.count { buf = [UInt8](repeating: 0, count: required); rc = codexpc_engine_decode_token(e, toks[i], &buf, buf.count, &required) }
    if rc != 0 { print("decode rc=\(rc) for token=\(toks[i]) req=\(required)"); continue }
    let s = String(bytes: buf.prefix(required), encoding: .utf8) ?? ""
    out += s
}
print("decoded=\n\(out)")

