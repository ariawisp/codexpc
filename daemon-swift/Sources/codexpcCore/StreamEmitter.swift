import Foundation

final class StreamEmitter {
    private let flushIntervalMs: Int
    private let maxBufferBytes: Int
    private let onFlush: (String) -> Void

    private let queue = DispatchQueue(label: "com.yourorg.codexpc.stream")
    private var buffer = Data()
    private var timer: DispatchSourceTimer?
    private var closed = false

    init(flushIntervalMs: Int = 20, maxBufferBytes: Int = 4096, onFlush: @escaping (String) -> Void) {
        self.flushIntervalMs = flushIntervalMs
        self.maxBufferBytes = maxBufferBytes
        self.onFlush = onFlush
    }

    func start() {
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now() + .milliseconds(flushIntervalMs), repeating: .milliseconds(flushIntervalMs))
        timer?.setEventHandler { [weak self] in self?.flushIfNeeded(force: false) }
        timer?.resume()
    }

    func submit(_ text: String) {
        guard !closed else { return }
        queue.async { [weak self] in
            guard let self = self, !self.closed else { return }
            if let d = text.data(using: .utf8) {
                self.buffer.append(d)
                if self.buffer.count >= self.maxBufferBytes {
                    self.flushIfNeeded(force: true)
                }
            }
        }
    }

    func close() {
        queue.sync {
            self.closed = true
            self.flushIfNeeded(force: true)
            self.timer?.cancel()
            self.timer = nil
        }
    }

    private func flushIfNeeded(force: Bool) {
        if buffer.isEmpty { return }
        if !force && buffer.count < 1 { return }
        let s = String(data: buffer, encoding: .utf8) ?? ""
        buffer.removeAll(keepingCapacity: true)
        if !s.isEmpty { onFlush(s) }
    }
}
