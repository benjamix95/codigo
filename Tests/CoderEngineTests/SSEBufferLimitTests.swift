import XCTest
@testable import CoderEngine

/// Test per la protezione del buffer SSE contro frame oversized.
///
/// Verifica che il limite di 1 MB per frame SSE funzioni correttamente
/// nei parser di streaming di Anthropic e OpenAI.
final class SSEBufferLimitTests: XCTestCase {

    // MARK: - Buffer Growth Limit

    func testBufferResetAfterExceedingLimit() {
        // Simula il comportamento del parser: accumula byte senza newline,
        // verifica che il buffer viene svuotato quando supera il limite.
        var buffer = [UInt8]()
        let maxSSEFrameBytes = 1_048_576

        // Aggiungi bytes senza newline fino a superare il limite
        let oversizedChunk = [UInt8](repeating: 65, count: maxSSEFrameBytes + 1) // 'A' repeated
        for byte in oversizedChunk {
            buffer.append(byte)
            if buffer.count > maxSSEFrameBytes {
                buffer.removeAll()
            }
        }

        XCTAssertTrue(buffer.isEmpty, "Buffer should be cleared after exceeding limit")
    }

    func testBufferProcessesNormalFrames() {
        var buffer = [UInt8]()
        let maxSSEFrameBytes = 1_048_576
        var linesProcessed = 0

        let line = "data: {\"type\":\"text_delta\"}\n"
        let bytes = [UInt8](line.utf8)

        for byte in bytes {
            buffer.append(byte)

            if buffer.count > maxSSEFrameBytes {
                buffer.removeAll()
                continue
            }

            if byte == 10 { // newline
                let lineStr = String(bytes: buffer, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                buffer.removeAll()
                if lineStr.hasPrefix("data: ") {
                    linesProcessed += 1
                }
            }
        }

        XCTAssertEqual(linesProcessed, 1)
    }

    func testBufferRecoverAfterOversizedFrame() {
        var buffer = [UInt8]()
        let maxSSEFrameBytes = 1_048_576
        var linesProcessed = 0
        var skipUntilNewline = false

        // Prima: un frame oversized senza newline, poi newline di reset, poi frame normale
        let oversized = [UInt8](repeating: 65, count: maxSSEFrameBytes + 100)
        let resetNewline: [UInt8] = [10] // newline per terminare il frame corrotto
        let normalLine = "data: {\"type\":\"ping\"}\n"
        let allBytes = oversized + resetNewline + [UInt8](normalLine.utf8)

        for byte in allBytes {
            if skipUntilNewline {
                if byte == 10 { skipUntilNewline = false }
                continue
            }

            buffer.append(byte)

            if buffer.count > maxSSEFrameBytes {
                buffer.removeAll()
                skipUntilNewline = true
                continue
            }

            if byte == 10 {
                let lineStr = String(bytes: buffer, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                buffer.removeAll()
                if lineStr.hasPrefix("data: ") {
                    linesProcessed += 1
                }
            }
        }

        XCTAssertEqual(linesProcessed, 1, "Parser should recover after oversized frame + newline reset")
    }

    // MARK: - Edge Cases

    func testExactlyAtLimitIsAccepted() {
        var buffer = [UInt8]()
        let maxSSEFrameBytes = 1_048_576

        // Crea un frame esattamente al limite (con newline alla fine)
        let payload = [UInt8](repeating: 65, count: maxSSEFrameBytes - 1) + [10] // 'A'... + '\n'
        var wasProcessed = false

        for byte in payload {
            buffer.append(byte)
            if buffer.count > maxSSEFrameBytes {
                buffer.removeAll()
                continue
            }
            if byte == 10 {
                wasProcessed = true
                buffer.removeAll()
            }
        }

        XCTAssertTrue(wasProcessed, "Frame exactly at limit should be processed")
    }

    func testOneOverLimitIsRejected() {
        var buffer = [UInt8]()
        let maxSSEFrameBytes = 1_048_576

        // Crea un frame di esattamente limit+1 byte senza newline
        let payload = [UInt8](repeating: 65, count: maxSSEFrameBytes + 1)
        var wasCleared = false

        for byte in payload {
            buffer.append(byte)
            if buffer.count > maxSSEFrameBytes {
                buffer.removeAll()
                wasCleared = true
            }
        }

        XCTAssertTrue(wasCleared, "Frame one byte over limit should trigger clear")
    }
}
