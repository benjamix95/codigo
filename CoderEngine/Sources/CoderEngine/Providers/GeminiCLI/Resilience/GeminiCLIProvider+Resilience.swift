import Foundation

public extension GeminiCLIProvider {
    static func userFacingErrorMessage(from error: Error) -> String {
        if let cancellation = error as? CancellationError {
            return cancellation.localizedDescription
        }

        let processError = error as? ProcessRunner.ProcessRunnerError
        let candidates = [
            processError?.message,
            processError?.stdoutTail,
            error.localizedDescription,
        ].compactMap { $0 }.filter { !$0.isEmpty }

        for candidate in candidates {
            if let parsed = parseGeminiCLIErrorMessage(from: candidate) {
                return parsed
            }
        }

        return error.localizedDescription
    }

    static func parseGeminiCLIErrorMessage(from raw: String) -> String? {
        let objects = extractJSONObjectStrings(from: raw)
        for object in objects.reversed() {
            guard let dict = decodeJSONDictionary(object) else { continue }
            if let message = geminiErrorMessage(from: dict, raw: raw) {
                return message
            }
        }

        if raw.contains("[object Object]"), let http = firstHTTPStatusCode(in: raw) {
            if http == 404 {
                return "Gemini CLI: HTTP 404 error (resource/model not found). Check the selected model or update the CLI."
            }
            return "Gemini CLI: HTTP error \(http)."
        }

        return nil
    }

    static func geminiErrorMessage(from json: [String: Any], raw: String) -> String? {
        let topError = json["error"] as? [String: Any]
        let topMessage = nonEmptyString(topError?["message"]) ?? nonEmptyString(json["message"])
        let topCode = nonEmptyString(topError?["code"]) ?? nonEmptyString(json["code"])

        let httpCode = firstHTTPStatusCode(in: raw)
            ?? intValue(topCode)
            ?? intValue(nonEmptyString(json["status"]))

        let cleanedMessage = cleanedGeminiErrorMessage(topMessage)

        if let code = httpCode, code == 404 {
            if let cleanedMessage, !cleanedMessage.isEmpty {
                return "Gemini CLI: HTTP 404 error — \(cleanedMessage)"
            }
            return "Gemini CLI: HTTP 404 error (resource/model not found). Check the selected model or update the CLI."
        }

        if let code = httpCode {
            if let cleanedMessage, !cleanedMessage.isEmpty {
                return "Gemini CLI: HTTP error \(code) — \(cleanedMessage)"
            }
            return "Gemini CLI: HTTP error \(code)."
        }

        if let cleanedMessage, !cleanedMessage.isEmpty {
            return "Gemini CLI: \(cleanedMessage)"
        }

        if raw.contains("[object Object]") {
            return "Gemini CLI: request failed (no detailed error). Check account and model configuration."
        }

        return nil
    }

    static func cleanedGeminiErrorMessage(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed == "[object Object]" { return nil }
        return trimmed
    }

    static func firstHTTPStatusCode(in text: String) -> Int? {
        let patterns = [
            #"(?i)\bhttp\s*([45]\d{2})\b"#,
            #"(?i)\bstatus(?:\s*code)?\s*[:=]?\s*([45]\d{2})\b"#,
            #"(?i)\bcode\s*[:=]?\s*([45]\d{2})\b"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  let codeRange = Range(match.range(at: 1), in: text),
                  let code = Int(text[codeRange]) else { continue }
            return code
        }
        return nil
    }

    static func intValue(_ text: String?) -> Int? {
        guard let text else { return nil }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return Int(cleaned)
    }
}
