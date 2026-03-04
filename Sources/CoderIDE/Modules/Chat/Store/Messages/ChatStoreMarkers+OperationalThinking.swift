import Foundation

extension ChatStore {
    /// Extracts the last "operational" line from content during streaming (e.g. "Planning next moves", "Explored lints").
    /// Used to show LLM thinking like Cursor does.
    static func extractLastOperationalThinkingLine(from content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lines = trimmed.components(separatedBy: .newlines)
        let operationalPrefixes = [
            "Planning", "Explored", "Inspecting", "Ran ", "Reading", "Analyzing",
            "Implementing", "Updating", "Creating", "Generating", "Processing",
            "Setting", "Preparing", "Starting", "Initializing", "Bootstrapping",
            "Writing", "Searching",
        ]
        for line in lines.reversed() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard trimmedLine.count > 3, trimmedLine.count < 150 else { continue }
            let lowercasedLine = trimmedLine.lowercased()
            for prefix in operationalPrefixes {
                if lowercasedLine.hasPrefix(prefix.lowercased()) {
                    return trimmedLine
                }
            }
        }
        return nil
    }
}
