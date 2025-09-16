@testable import codexpcCore
import XCTest

final class StreamEmitterTests: XCTestCase {
    func testCloseFlushesAll() {
        let exp = expectation(description: "flushed")
        var collected = ""
        let emitter = StreamEmitter(flushIntervalMs: 1000, maxBufferBytes: 4096, minFlushBytes: 4096) { s in
            collected += s
            exp.fulfill()
        }
        emitter.start()
        emitter.submit("Hello, ")
        emitter.submit("world!")
        emitter.close()
        waitForExpectations(timeout: 2.0)
        XCTAssertEqual(collected, "Hello, world!")
    }
}

