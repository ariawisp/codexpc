import XCTest
@testable import codexpcCore

final class ToolExecutorTests: XCTestCase {
    func testEchoJsonExtractsMsg() {
        let out = ToolExecutor.execute(name: "echo", input: "{\"msg\":\"hello\"}")
        XCTAssertEqual(out, "hello")
    }

    func testUpperJsonExtractsMsgAndUppercases() {
        let out = ToolExecutor.execute(name: "upper", input: "{\"msg\":\"hello\"}")
        XCTAssertEqual(out, "HELLO")
    }

    func testAllowedToolsGate() {
        // Simulate allowed list by setting env var
        setenv("CODEXPC_ALLOWED_TOOLS", "echo", 1)
        let allowed = ToolExecutor.executeWithStatus(name: "echo", input: "x")
        let blocked = ToolExecutor.executeWithStatus(name: "upper", input: "x")
        XCTAssertEqual(allowed.output, "x")
        XCTAssertTrue(allowed.ok)
        XCTAssertTrue(blocked.output.contains("not allowed"))
        XCTAssertFalse(blocked.ok)
        unsetenv("CODEXPC_ALLOWED_TOOLS")
    }

    func testOutputCapIsApplied() {
        setenv("CODEXPC_TOOL_MAX_OUTPUT_BYTES", "8", 1)
        let long = String(repeating: "é", count: 16) // multi-byte char
        let res = ToolExecutor.executeEnforced(name: "echo", input: long)
        XCTAssertTrue(res.ok)
        XCTAssertLessThanOrEqual(res.output.utf8.count, 8)
        unsetenv("CODEXPC_TOOL_MAX_OUTPUT_BYTES")
    }

    func testTimeoutTriggersFailure() {
        setenv("CODEXPC_TOOL_TIMEOUT_MS", "10", 1)
        setenv("CODEXPC_TEST_TOOL_DELAY_MS", "50", 1)
        let res = ToolExecutor.executeEnforced(name: "echo", input: "hello")
        XCTAssertFalse(res.ok)
        XCTAssertTrue(res.output.contains("timed out"))
        unsetenv("CODEXPC_TEST_TOOL_DELAY_MS")
        unsetenv("CODEXPC_TOOL_TIMEOUT_MS")
    }
}
