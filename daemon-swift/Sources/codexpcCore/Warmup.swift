import Foundation
import os

public enum Warmup {
    // Check known locations for a warmup checkpoint path and precompile kernels.
    public static func runIfConfigured() {
        // Known config files that may contain a single line: checkpoint path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/codexpc/etc/warmup-checkpoint",
            "/opt/codexpc/etc/warmup-checkpoint",
        ]
        var checkpoint: String? = nil
        for path in candidates {
            if FileManager.default.fileExists(atPath: path),
               let data = try? String(contentsOfFile: path, encoding: .utf8) {
                let trimmed = data.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && FileManager.default.fileExists(atPath: trimmed) {
                    checkpoint = trimmed
                    break
                }
            }
        }
        // Fallback: conventional local path used in docs
        if checkpoint == nil {
            let defaultCkpt = "\(home)/gpt-oss-20b/metal/model.bin"
            if FileManager.default.fileExists(atPath: defaultCkpt) {
                checkpoint = defaultCkpt
            }
        }
        guard let ckpt = checkpoint else { return }
        DispatchQueue.global(qos: .utility).async {
            let t0 = DispatchTime.now().uptimeNanoseconds
            do {
                let runner = try MetalRunner(checkpointPath: ckpt)
                runner.warmup()
                let durMs = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000.0
                log.debug("warmup done ckpt=\(ckpt, privacy: .public) duration_ms=\(durMs, privacy: .public)")
                _ = runner // keep alive until end of scope
            } catch {
                log.debug("warmup skipped/failed ckpt=\(ckpt, privacy: .public) error=\(String(describing: error), privacy: .public)")
            }
        }
    }
}
