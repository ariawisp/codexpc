@testable import codexpcCore
import XCTest

final class MetalRunnerStubTests: XCTestCase {
    func testStubEngineStreams() throws {
        // Requires CODEXPC_STUB_ENGINE=1
        let runner = try MetalRunner(checkpointPath: "/dev/null")
        try runner.reset()
        var out = ""
        let gen = try runner.stream(temperature: 0.0, maxTokens: 3, isCancelled: { false }) { s in
            out += s
        }
        XCTAssertEqual(gen, 3)
        XCTAssertEqual(out, "Hi\n")
    }
}

