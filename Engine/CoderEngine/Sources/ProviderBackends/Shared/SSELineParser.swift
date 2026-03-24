import Foundation

// MARK: - SSELineParser

/// Parser condiviso per stream SSE byte-by-byte con protezione overflow.
///
/// Accumula byte fino a newline, gestisce frame oversized,
/// e restituisce le linee "data: ..." come payload JSON.
/// Usato da AnthropicAPIProvider e OpenAIAPIProvider per eliminare
/// la duplicazione del buffer management SSE.
struct SSELineParser {

    /// Limite massimo in byte per un singolo frame SSE.
    let maxFrameBytes: Int

    private var buffer: [UInt8] = []
    private var skipUntilNewline = false

    init(maxFrameBytes: Int = 1_048_576) {
        self.maxFrameBytes = maxFrameBytes
    }

    // MARK: - Result

    enum LineResult {
        /// Frame SSE valido con payload JSON (senza prefisso "data: ").
        case payload(String)
        /// Segnale [DONE] ricevuto.
        case done
        /// Frame overflow: il buffer ha superato il limite.
        case overflow(droppedBytes: Int)
        /// Byte accumulato, nessuna linea completa ancora.
        case buffering
    }

    // MARK: - Feed

    /// Processa un singolo byte dallo stream SSE.
    mutating func feed(_ byte: UInt8) -> LineResult {
        if skipUntilNewline {
            if byte == 10 { skipUntilNewline = false }
            return .buffering
        }

        buffer.append(byte)

        if buffer.count > maxFrameBytes {
            let droppedSize = buffer.count
            buffer.removeAll()
            skipUntilNewline = true
            return .overflow(droppedBytes: droppedSize)
        }

        guard byte == 10 else { return .buffering }

        let line = String(bytes: buffer, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        buffer.removeAll()

        guard line.hasPrefix("data: ") else { return .buffering }
        let jsonStr = String(line.dropFirst(6))

        if jsonStr == "[DONE]" {
            return .done
        }

        return .payload(jsonStr)
    }

    // MARK: - Reset

    mutating func reset() {
        buffer.removeAll()
        skipUntilNewline = false
    }
}
