import Foundation

public enum SensitiveDataRedactionService {
    private static let patterns: [String] = [
        #"AKIA[0-9A-Z]{16}"#,
        #"ghp_[A-Za-z0-9]{20,}"#,
        #"sk_live_[A-Za-z0-9]{16,}"#,
        #"(?i)(authorization:\s*bearer\s+)[A-Za-z0-9\-_\.]+"#,
        #"(?i)(token\s*=\s*)[^\s]+"#,
        #"(?i)(password\s*=\s*)[^\s]+"#,
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"#,
    ]

    public static func redact(_ raw: String) -> (value: String, wasRedacted: Bool) {
        var value = raw
        var changed = false
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            let replaced = regex.stringByReplacingMatches(
                in: value,
                options: [],
                range: range,
                withTemplate: "$1[REDACTED]"
            )
            if replaced != value {
                value = replaced
                changed = true
            }
        }
        return (value, changed)
    }
}
