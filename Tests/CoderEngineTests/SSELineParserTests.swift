import XCTest
@testable import CoderEngine

/// Test per SSELineParser — parser condiviso per stream SSE.
final class SSELineParserTests: XCTestCase {

    // MARK: - Basic Parsing

    func testBufferingUntilNewline() {
        var parser = SSELineParser()
        let bytes: [UInt8] = Array("data: hello".utf8)

        for byte in bytes {
            let result = parser.feed(byte)
            XCTAssertEqual(String(describing: result), String(describing: SSELineParser.LineResult.buffering))
        }
    }

    func testPayloadExtraction() {
        var parser = SSELineParser()
        let line = "data: {\"type\":\"text_delta\"}\n"
        var payload: String?

        for byte in Array(line.utf8) {
            if case .payload(let json) = parser.feed(byte) {
                payload = json
            }
        }

        XCTAssertEqual(payload, "{\"type\":\"text_delta\"}")
    }

    func testDoneSignal() {
        var parser = SSELineParser()
        let line = "data: [DONE]\n"
        var gotDone = false

        for byte in Array(line.utf8) {
            if case .done = parser.feed(byte) {
                gotDone = true
            }
        }

        XCTAssertTrue(gotDone)
    }

    func testNonDataLineIsBuffering() {
        var parser = SSELineParser()
        let line = "event: message_start\n"
        var results: [SSELineParser.LineResult] = []

        for byte in Array(line.utf8) {
            results.append(parser.feed(byte))
        }

        // L'ultima riga non-data dovrebbe restituire .buffering (non .payload)
        for result in results {
            if case .payload = result {
                XCTFail("Non-data line should not produce .payload")
            }
            if case .done = result {
                XCTFail("Non-data line should not produce .done")
            }
        }
    }

    // MARK: - Overflow Protection

    func testOverflowDetection() {
        let limit = 100
        var parser = SSELineParser(maxFrameBytes: limit)
        var overflowDetected = false

        // Invia limit+1 byte senza newline
        for _ in 0...limit {
            if case .overflow(let dropped) = parser.feed(65) { // 'A'
                overflowDetected = true
                XCTAssertEqual(dropped, limit + 1)
            }
        }

        XCTAssertTrue(overflowDetected)
    }

    func testRecoveryAfterOverflow() {
        let limit = 50
        var parser = SSELineParser(maxFrameBytes: limit)

        // Causa overflow
        for _ in 0...limit {
            _ = parser.feed(65) // 'A'
        }

        // Il parser ora skippa fino a newline
        let result1 = parser.feed(65) // ancora 'A' — skippato
        if case .buffering = result1 {} else {
            XCTFail("Should be buffering (skipping) after overflow")
        }

        // Invia newline per reset
        _ = parser.feed(10) // '\n'

        // Ora il parser dovrebbe funzionare normalmente
        let normalLine = "data: {\"ok\":true}\n"
        var payload: String?
        for byte in Array(normalLine.utf8) {
            if case .payload(let json) = parser.feed(byte) {
                payload = json
            }
        }

        XCTAssertEqual(payload, "{\"ok\":true}")
    }

    func testExactlyAtLimitIsAccepted() {
        let limit = 30
        var parser = SSELineParser(maxFrameBytes: limit)

        // "data: X\n" = esattamente entro il limite
        let line = "data: " + String(repeating: "X", count: limit - 8) + "\n"
        XCTAssertLessThanOrEqual(Array(line.utf8).count, limit)

        var payload: String?
        for byte in Array(line.utf8) {
            if case .payload(let json) = parser.feed(byte) {
                payload = json
            }
        }

        XCTAssertNotNil(payload)
    }

    // MARK: - Multiple Lines

    func testMultiplePayloadsInSequence() {
        var parser = SSELineParser()
        let lines = "data: {\"a\":1}\ndata: {\"b\":2}\ndata: [DONE]\n"
        var payloads: [String] = []
        var gotDone = false

        for byte in Array(lines.utf8) {
            switch parser.feed(byte) {
            case .payload(let json):
                payloads.append(json)
            case .done:
                gotDone = true
            default:
                break
            }
        }

        XCTAssertEqual(payloads, ["{\"a\":1}", "{\"b\":2}"])
        XCTAssertTrue(gotDone)
    }

    func testEmptyLinesAreIgnored() {
        var parser = SSELineParser()
        let lines = "\n\ndata: hello\n\n"
        var payloads: [String] = []

        for byte in Array(lines.utf8) {
            if case .payload(let json) = parser.feed(byte) {
                payloads.append(json)
            }
        }

        XCTAssertEqual(payloads, ["hello"])
    }

    // MARK: - Reset

    func testResetClearsState() {
        var parser = SSELineParser(maxFrameBytes: 50)

        // Accumula qualche byte
        for byte in Array("data: partial".utf8) {
            _ = parser.feed(byte)
        }

        parser.reset()

        // Dopo reset, un nuovo frame dovrebbe funzionare
        let line = "data: fresh\n"
        var payload: String?
        for byte in Array(line.utf8) {
            if case .payload(let json) = parser.feed(byte) {
                payload = json
            }
        }

        XCTAssertEqual(payload, "fresh")
    }
}
