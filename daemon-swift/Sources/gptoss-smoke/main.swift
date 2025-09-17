import Foundation
import codexpcEngine

struct Args {
    var checkpoint = ""
    var prompt = "Hello"
    var tokens: Int = 16 // 0 = unlimited
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
    fputs("usage: gptoss-smoke --checkpoint <path> [--prompt <text>] [--tokens <n (0=unlimited)>] [--temperature <float>]\n", stderr)
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
if rcReset != 0 { /* continue */ }

var appended: Int = 0
_ = args.prompt.withCString { c in codexpc_engine_append_chars(e, c, strlen(c), &appended) }

// Emit created marker
fputs("[created]\n", stdout); fflush(stdout)

var endId: UInt32 = 0
let _ = codexpc_engine_get_end_token_id(e, &endId)

let batch = 16
var toks = [UInt32](repeating: 0, count: batch)
var outCount: Int = 0
var buf = [UInt8](repeating: 0, count: 4096)
let temp = Float(args.temperature)
let unlimited = (args.tokens <= 0)
var generated = 0

outer: while unlimited || generated < args.tokens {
    outCount = 0
    let rc = codexpc_engine_sample(e, temp, 0, batch, &toks, &outCount)
    if rc != 0 || outCount == 0 { break }
    for i in 0..<outCount {
        let t = toks[i]
        if endId != 0 && t == endId { break outer }
        var required: Int = 0
        var drc = codexpc_engine_decode_token(e, t, &buf, buf.count, &required)
        if drc == -2 && required > buf.count {
            buf = [UInt8](repeating: 0, count: required)
            drc = codexpc_engine_decode_token(e, t, &buf, buf.count, &required)
        }
        if drc == 0 {
            let s = String(bytes: buf.prefix(required), encoding: .utf8) ?? ""
            if !s.isEmpty { fputs(s, stdout); fflush(stdout) }
        }
        generated += 1
        if !unlimited && generated >= args.tokens { break outer }
    }
}

// Emit completed marker
fputs("\n[completed]\n", stdout); fflush(stdout)
