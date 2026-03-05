import Foundation

private struct CodexConfigDocument {
    private(set) var lines: [String]

    init(content: String) {
        lines = content.isEmpty ? [] : content.components(separatedBy: .newlines)
        while lines.last == "" {
            lines.removeLast()
        }
    }

    mutating func upsertRootAssignment(key: String, renderedLines: [String]?) {
        let bounds = rootBounds()
        upsertAssignment(key: key, renderedLines: renderedLines, bounds: bounds)
    }

    mutating func upsertSectionAssignment(section: String, key: String, renderedLines: [String]?) {
        if let bodyBounds = sectionBodyBounds(named: section) {
            upsertAssignment(key: key, renderedLines: renderedLines, bounds: bodyBounds)
            return
        }

        guard let renderedLines else { return }
        trimTrailingBlankLines()
        if !lines.isEmpty {
            lines.append("")
        }
        lines.append("[\(section)]")
        lines.append(contentsOf: renderedLines)
    }

    func renderedContent() -> String {
        guard !lines.isEmpty else { return "" }
        return lines.joined(separator: "\n") + "\n"
    }

    private func rootBounds() -> Range<Int> {
        let firstSectionIndex = lines.firstIndex(where: Self.isSectionHeader) ?? lines.count
        return 0..<firstSectionIndex
    }

    private func sectionBodyBounds(named section: String) -> Range<Int>? {
        let header = "[\(section)]"
        guard let sectionStart = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == header }) else {
            return nil
        }

        let bodyStart = sectionStart + 1
        var bodyEnd = lines.count
        if bodyStart < lines.count {
            for index in bodyStart..<lines.count where Self.isSectionHeader(lines[index]) {
                bodyEnd = index
                break
            }
        }
        return bodyStart..<bodyEnd
    }

    private mutating func upsertAssignment(key: String, renderedLines: [String]?, bounds: Range<Int>) {
        if let range = assignmentRange(for: key, bounds: bounds) {
            lines.replaceSubrange(range, with: renderedLines ?? [])
            return
        }

        guard let renderedLines else { return }
        let insertIndex = max(bounds.lowerBound, min(bounds.upperBound, lines.count))
        lines.insert(contentsOf: renderedLines, at: insertIndex)
    }

    private func assignmentRange(for key: String, bounds: Range<Int>) -> Range<Int>? {
        guard bounds.lowerBound < bounds.upperBound else { return nil }

        var index = bounds.lowerBound
        while index < bounds.upperBound {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                index += 1
                continue
            }
            guard let equalIndex = trimmed.firstIndex(of: "=") else {
                index += 1
                continue
            }

            let candidateKey = String(trimmed[..<equalIndex]).trimmingCharacters(in: .whitespaces)
            guard candidateKey == key else {
                index += 1
                continue
            }

            let rawValue = String(trimmed[trimmed.index(after: equalIndex)...]).trimmingCharacters(in: .whitespaces)
            if rawValue.hasPrefix("\"\"\"") {
                return index..<multilineEndIndex(start: index, bounds: bounds, firstRawValue: rawValue)
            }
            return index..<(index + 1)
        }

        return nil
    }

    private func multilineEndIndex(start: Int, bounds: Range<Int>, firstRawValue: String) -> Int {
        let first = String(firstRawValue.dropFirst(3))
        if first.contains("\"\"\"") {
            return start + 1
        }

        var index = start + 1
        while index < bounds.upperBound {
            if lines[index].contains("\"\"\"") {
                return index + 1
            }
            index += 1
        }
        return index
    }

    private mutating func trimTrailingBlankLines() {
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
    }

    private static func isSectionHeader(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
    }
}

extension CodexConfigLoader {
    static func renderMergedContent(existingContent: String?, config: CodexConfig) -> String {
        var document = CodexConfigDocument(content: existingContent ?? "")
        let validPersonalities = Set(["friendly", "pragmatic"])
        let personality = validPersonalities.contains(config.personality ?? "") ? config.personality : nil

        document.upsertRootAssignment(key: "model", renderedLines: renderStringAssignment("model", config.model))
        document.upsertRootAssignment(
            key: "model_provider",
            renderedLines: renderStringAssignment("model_provider", config.modelProvider)
        )
        document.upsertRootAssignment(
            key: "model_reasoning_effort",
            renderedLines: renderStringAssignment("model_reasoning_effort", config.modelReasoningEffort)
        )
        document.upsertRootAssignment(
            key: "model_reasoning_summary",
            renderedLines: renderStringAssignment("model_reasoning_summary", config.modelReasoningSummary)
        )
        document.upsertRootAssignment(
            key: "model_verbosity",
            renderedLines: renderStringAssignment("model_verbosity", config.modelVerbosity)
        )
        document.upsertRootAssignment(
            key: "personality",
            renderedLines: renderStringAssignment("personality", personality)
        )
        document.upsertRootAssignment(
            key: "sandbox_mode",
            renderedLines: renderStringAssignment("sandbox_mode", config.sandboxMode)
        )
        document.upsertRootAssignment(key: "fast_mode", renderedLines: renderBoolAssignment("fast_mode", config.fastMode))
        document.upsertRootAssignment(
            key: "check_for_update_on_startup",
            renderedLines: renderBoolAssignment("check_for_update_on_startup", config.checkForUpdateOnStartup)
        )
        document.upsertRootAssignment(
            key: "developer_instructions",
            renderedLines: renderMultilineAssignment("developer_instructions", config.developerInstructions)
        )

        document.upsertSectionAssignment(
            section: "sandbox_workspace_write",
            key: "network_access",
            renderedLines: renderBoolAssignment("network_access", config.networkAccess)
        )
        document.upsertSectionAssignment(
            section: "sandbox_workspace_write",
            key: "additional_write_roots",
            renderedLines: renderArrayAssignment("additional_write_roots", config.additionalWriteRoots)
        )

        return document.renderedContent()
    }

    private static func renderStringAssignment(_ key: String, _ value: String?) -> [String]? {
        guard let value, !value.isEmpty else { return nil }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return ["\(key) = \"\(escaped)\""]
    }

    private static func renderBoolAssignment(_ key: String, _ value: Bool?) -> [String]? {
        guard let value else { return nil }
        return ["\(key) = \(value)"]
    }

    private static func renderArrayAssignment(_ key: String, _ values: [String]) -> [String]? {
        guard !values.isEmpty else { return nil }
        let renderedValues = values.map { value in
            let escaped = value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return ["\(key) = [\(renderedValues.joined(separator: ", "))]"]
    }

    private static func renderMultilineAssignment(_ key: String, _ value: String?) -> [String]? {
        guard let value, !value.isEmpty else { return nil }
        let escaped = value.replacingOccurrences(of: "\"\"\"", with: "\\\"\\\"\\\"")
        return [
            "\(key) = \"\"\"",
            escaped,
            "\"\"\"",
        ]
    }
}
