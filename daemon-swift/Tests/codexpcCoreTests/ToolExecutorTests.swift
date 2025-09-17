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
        // Enable tools and allow only echo
        let prevEnabled = ToolExecutor.Config.enabled
        let prevAllowed = ToolExecutor.Config.allowed
        ToolExecutor.Config.enabled = true
        ToolExecutor.Config.allowed = ["echo"]
        let allowed = ToolExecutor.executeWithStatus(name: "echo", input: "x")
        let blocked = ToolExecutor.executeWithStatus(name: "upper", input: "x")
        XCTAssertEqual(allowed.output, "x")
        XCTAssertTrue(allowed.ok)
        XCTAssertTrue(blocked.output.contains("not allowed"))
        XCTAssertFalse(blocked.ok)
        // restore
        ToolExecutor.Config.allowed = prevAllowed
        ToolExecutor.Config.enabled = prevEnabled
    }

    func testOutputCapIsApplied() {
        let prevEnabled = ToolExecutor.Config.enabled
        let prevMax = ToolExecutor.Config.maxOutputBytes
        ToolExecutor.Config.enabled = true
        ToolExecutor.Config.maxOutputBytes = 8
        let long = String(repeating: "é", count: 16) // multi-byte char
        let res = ToolExecutor.executeEnforced(name: "echo", input: long)
        XCTAssertTrue(res.ok)
        XCTAssertLessThanOrEqual(res.output.utf8.count, 8)
        ToolExecutor.Config.maxOutputBytes = prevMax
        ToolExecutor.Config.enabled = prevEnabled
    }

    func testTimeoutTriggersFailure() {
        let prevEnabled = ToolExecutor.Config.enabled
        let prevTimeout = ToolExecutor.Config.timeoutMs
        let prevDelay = ToolExecutor.Config.testDelayMs
        ToolExecutor.Config.enabled = true
        ToolExecutor.Config.timeoutMs = 10
        ToolExecutor.Config.testDelayMs = 50
        let res = ToolExecutor.executeEnforced(name: "echo", input: "hello")
        XCTAssertFalse(res.ok)
        XCTAssertTrue(res.output.contains("timed out"))
        ToolExecutor.Config.testDelayMs = prevDelay
        ToolExecutor.Config.timeoutMs = prevTimeout
        ToolExecutor.Config.enabled = prevEnabled
    }

    func testInvalidJsonArgumentsFailValidation() {
        // Input looks like JSON but is invalid -> should fail validation
        let bad = ToolExecutor.executeWithStatus(name: "echo", input: "{bad}")
        XCTAssertFalse(bad.ok)
        XCTAssertTrue(bad.output.contains("invalid arguments"))

        // JSON without any string field should also fail
        let noString = ToolExecutor.executeWithStatus(name: "upper", input: "{\"n\":123}")
        XCTAssertFalse(noString.ok)
        XCTAssertTrue(noString.output.contains("invalid arguments"))
    }

    func testUnsupportedToolIsRejected() {
        let res = ToolExecutor.executeWithStatus(name: "does_not_exist", input: "hi")
        XCTAssertFalse(res.ok)
        XCTAssertTrue(res.output.contains("unsupported tool"))
    }
}
