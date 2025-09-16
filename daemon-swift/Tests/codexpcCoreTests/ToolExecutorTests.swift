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
}
