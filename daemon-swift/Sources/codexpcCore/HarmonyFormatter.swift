import Foundation
import HarmonyFFI
import codexpcEngine

final class HarmonyFormatter {
    func appendSystem(to engine: codexpc_engine_t, instructions: String) throws {
        instructions.withCString { cstr in
            var tokPtr: UnsafeMutablePointer<UInt32>? = nil
            var tokLen: Int = 0
            let rc = harmony_render_system_tokens(cstr, &tokPtr, &tokLen)
            if rc != 0 { return }
            guard let toks = tokPtr else { return }
            defer { harmony_tokens_free(toks, tokLen) }
            _ = codexpc_engine_append_tokens(engine, toks, tokLen)
        }
    }
}
