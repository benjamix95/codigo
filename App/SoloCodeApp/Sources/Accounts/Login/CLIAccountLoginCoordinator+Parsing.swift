import Foundation

extension CLIAccountLoginCoordinator {
    nonisolated static func extractFirstURL(from output: String) -> URL? {
        guard let regex = try? NSRegularExpression(pattern: "https?://[^\\s\"'<>]+"),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range, in: output) else {
            return nil
        }
        return URL(string: String(output[range]))
    }

    nonisolated static func extractDeviceCode(from output: String) -> String? {
        let patterns = [
            "(?:code|Code)\\s*(?:is)?\\s*[:：]\\s*([A-Z0-9]{4,}-[A-Z0-9]{4,})",
            "(?:user[_\\s-]?code|device[_\\s-]?code)\\s*[:：]\\s*([A-Za-z0-9][A-Za-z0-9-]{4,})",
            "\\n\\s*([A-Z0-9]{4,}-[A-Z0-9]{4,})\\s*\\n",
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: output) else { continue }
            let code = String(output[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !code.isEmpty, code.count >= 6 { return code }
        }
        return nil
    }

    nonisolated static func sanitizeOutput(_ raw: String) -> String {
        let noANSI = raw.replacingOccurrences(
            of: "\\u001B\\[[0-9;]*[A-Za-z]",
            with: "",
            options: .regularExpression
        )
        let cleanedScalars = noANSI.unicodeScalars.filter { scalar in
            scalar.value == 0x09 || scalar.value == 0x0A || scalar.value >= 0x20
        }
        return String(String.UnicodeScalarView(cleanedScalars))
    }

    nonisolated static func outputRequestsInteractiveCode(_ output: String, provider: CLIProviderKind) -> Bool {
        let lower = output.lowercased()
        let commonHints = [
            "paste authentication code",
            "enter authentication code",
            "verification code",
            "one-time code",
            "paste code here",
            "enter code:",
            "enter the code",
            "paste the code",
            "authorization code",
            "enter your code",
            "input code",
            "paste code",
        ]
        if commonHints.contains(where: { lower.contains($0) }) {
            return true
        }
        switch provider {
        case .claude:
            let claudeHints = [
                "paste this into claude code",
                "paste into claude code",
                "authentication code",
                "if prompted, paste",
            ]
            return claudeHints.contains(where: { lower.contains($0) })
        case .codex:
            let codexHints = [
                "enter this code",
                "paste this code",
                "enter code at",
            ]
            return codexHints.contains(where: { lower.contains($0) })
        case .gemini:
            return false
        }
    }

    nonisolated static func normalizeInteractiveCode(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        for prefix in ["code:", "code "] {
            if lowered.hasPrefix(prefix) {
                let rest = String(trimmed.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !rest.isEmpty {
                    trimmed = rest
                    break
                }
            }
        }
        return trimmed
    }
}
