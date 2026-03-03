import Foundation

extension PlanOptionsParser {
    static func extractDisplaySummary(from fullPlan: String) -> (title: String, body: String) {
        let lines = fullPlan
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else {
            return ("Plan", "")
        }

        let titleIndex = lines.firstIndex(where: { $0.hasPrefix("#") }) ?? 0
        let titleLine = lines[titleIndex]
        let title = titleLine.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespacesAndNewlines)
        // Drop the title line itself to avoid it appearing in both title and body.
        var bodyLines = lines
        bodyLines.remove(at: titleIndex)
        let rawBody = bodyLines.prefix(20).joined(separator: "\n")
        let body = MermaidExtractor.stripMermaidBlocks(from: rawBody)
        return (title.isEmpty ? "Plan" : title, body)
    }

    static func extractFirstMermaidBlockForDisplay(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return MermaidExtractor.extractFirstMermaidBlock(from: text)
    }

    static func extractMermaidBlocksForDisplay(_ text: String) -> [String] {
        MermaidExtractor.extractMermaidBlocks(from: text)
    }

    static func extractPlanCauseSections(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let causeHeaders = [
            "cause",
            "root cause",
            "analysis",
            "approach",
            "rationale",
            "trade-off",
            "tradeoff",
            "constraints",
            "assumptions",
            // Technical plan headers
            "architecture",
            "design",
            "implementation",
            "technical",
            "system",
            "overview",
            "strategy",
            "plan",
            "summary",
            "scope",
            "dependencies",
            "risks",
            "migration",
            "refactor",
            "solution",
            "pipeline",
            "flow",
            "structure",
        ]
        let lines = trimmed.components(separatedBy: .newlines)
        var collected: [String] = []
        var current: [String] = []
        var collecting = false
        var inFence = false

        func flushCurrent() {
            let block = current
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !block.isEmpty {
                collected.append(block)
            }
            current.removeAll(keepingCapacity: true)
        }

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix("```") {
                inFence.toggle()
                if collecting {
                    current.append(line)
                }
                continue
            }
            if !inFence, trimmedLine.hasPrefix("#") {
                if collecting {
                    flushCurrent()
                    collecting = false
                }
                let title = trimmedLine
                    .drop(while: { $0 == "#" || $0 == " " || $0 == "\t" })
                    .lowercased()
                if causeHeaders.contains(where: { title.contains($0) }) {
                    collecting = true
                    current.append(line)
                }
                continue
            }
            if collecting {
                current.append(line)
            }
        }

        if collecting {
            flushCurrent()
        }
        return collected
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func extractFinalPlanBodyExcludingQuestionsOptionsTodos(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Prefer cause/technical sections when available, but don't discard other body content.
        let causeSections = extractPlanCauseSections(trimmed)

        let lines = trimmed.components(separatedBy: .newlines)
        var output: [String] = []
        var inFence = false
        var skippingSection = false

        func isSkippableHeader(_ line: String) -> Bool {
            let normalized = line
                .lowercased()
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: ":", with: "")
            guard normalized.hasPrefix("#") else { return false }
            let title = normalized.drop(while: { $0 == "#" || $0 == " " || $0 == "\t" })
            // Note: "approach" removed — it's valuable technical plan content.
            // Use word-boundary checks for "option" to avoid stripping headers
            // like "## Optional configuration" or "## Optimization strategy".
            return title.hasPrefix("questions")
                || title.hasPrefix("clarification")
                || title.hasPrefix("option ") || title == "options" || title.hasPrefix("options ")
                || title.hasPrefix("todo")
                || title.hasPrefix("to-do")
                || title == "task" || title == "tasks" || title.hasPrefix("tasks ")
                || title.hasPrefix("checklist")
                || title.hasPrefix("implementation step")
                || title.hasPrefix("execution step")
                || title.hasPrefix("next step")
                || title.hasPrefix("action item")
                || title.hasPrefix("work plan")
        }

        var skippingMermaid = false
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix("```") {
                if !inFence && trimmedLine.lowercased().hasPrefix("```mermaid") {
                    inFence = true
                    skippingMermaid = true
                    continue
                }
                inFence.toggle()
                if skippingMermaid && !inFence {
                    skippingMermaid = false
                    continue
                }
                if skippingSection {
                    continue
                }
                output.append(line)
                continue
            }

            if inFence {
                if !skippingSection && !skippingMermaid {
                    output.append(line)
                }
                continue
            }

            if trimmedLine.hasPrefix("#") {
                if isSkippableHeader(trimmedLine) {
                    skippingSection = true
                    continue
                }
                skippingSection = false
                output.append(line)
                continue
            }

            if skippingSection {
                continue
            }
            output.append(line)
        }

        let cleaned = output
            .joined(separator: "\n")
            .replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Use the filtered body when available; it already retains all
        // non-skippable sections (including cause/technical headers).
        // Only fall back to causeSections when the filtered body is empty,
        // which means all content lived under skippable headers and only
        // the cause extractor could rescue it.
        let combined: String
        if !cleaned.isEmpty {
            combined = cleaned
        } else if !causeSections.isEmpty {
            combined = causeSections
        } else {
            // Fallback: keep original text but remove mermaid fences to avoid duplication.
            let withoutMermaid = trimmed.replacingOccurrences(
                of: #"(?is)```mermaid\b\s*.*?```"#,
                with: "",
                options: .regularExpression
            )
            combined = withoutMermaid
        }

        return combined
            .replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
