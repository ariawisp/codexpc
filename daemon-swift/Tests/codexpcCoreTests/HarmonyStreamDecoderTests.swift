import XCTest
@testable import codexpcCore

final class HarmonyStreamDecoderTests: XCTestCase {
    func testDecoderInitAndNoCrashOnProcess() throws {
        // Decoder should initialize when Harmony C API is available.
        // If not available, skip the test gracefully.
        guard let decoder = try? HarmonyStreamDecoder() else {
            throw XCTSkip("Harmony C API not available in this environment")
        }
        // Process an arbitrary token id (likely non-special); expect no crash and optional nils.
        let res = decoder.process(token: 0)
        XCTAssertNotNil(res)
        // No assertions on delta/toolEvent content; just ensure it is safe to call.
    }
}

