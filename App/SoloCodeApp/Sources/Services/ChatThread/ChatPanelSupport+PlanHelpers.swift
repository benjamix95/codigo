import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Trace / File Mutation Helpers

func traceEventsContainSuccessfulCodeEdits(_ traceEvents: [ToolTraceEvent]) -> Bool {
    traceEvents.contains(where: isSuccessfulFileMutationEvent(_:))
}

func touchedFilePathsFromTraceEvents(
    _ traceEvents: [ToolTraceEvent],
    maxCount: Int = 50
) -> [String] {
    let files = traceEvents.compactMap { event -> String? in
        guard isSuccessfulFileMutationEvent(event) else {
            return nil
        }
        let rawPath = (
            ToolTraceFileChangeMapper.from(event: event)?.path
                ?? event.payload["file"]
                ?? event.payload["path"]
                ?? event.payload["file_path"]
                ?? event.payload["relative_path"]
                ?? event.payload["target_path"]
                ?? ""
        )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawPath.isEmpty else { return nil }
        return normalizeTouchedFilePath(rawPath)
    }

    guard maxCount > 0 else { return [] }
    return Array(Set(files)).sorted().prefix(maxCount).map { $0 }
}

func normalizedTodoTitle(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
}

func isSuccessfulMutationEventStatus(_ rawStatus: String?, isRunning: Bool) -> Bool {
    let normalized = (rawStatus ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    if normalized.isEmpty {
        return !isRunning
    }
    return normalized == "completed"
        || normalized == "success"
        || normalized == "ok"
        || normalized == "done"
}

func isSuccessfulFileMutationEvent(_ event: ToolTraceEvent) -> Bool {
    guard ToolTraceFileChangeMapper.isFileChangeEvent(event) else { return false }
    return isSuccessfulMutationEventStatus(event.payload["status"], isRunning: event.isRunning)
}

func normalizeTouchedFilePath(_ rawPath: String) -> String {
    if let range = rawPath.range(of: "Sources/") { return String(rawPath[range.lowerBound...]) }
    if let range = rawPath.range(of: "Tests/") { return String(rawPath[range.lowerBound...]) }
    if let range = rawPath.range(of: "CoderEngine/") { return String(rawPath[range.lowerBound...]) }
    return (rawPath as NSString).lastPathComponent
}

// MARK: - Plan Flow Helpers

func canExecutePlanBuild(phase: PlanFlowPhase, choice: String, allowIdleRebuild: Bool = false) -> Bool {
    let trimmed = choice.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    if allowIdleRebuild, phase == .idle {
        guard PlanOptionsParser.hasRequiredTodoHeader(trimmed) else { return false }
        return !PlanOptionsParser.extractTodosFromOptionText(trimmed).isEmpty
    }
    return phase == .proposalReady || phase == .readyToBuild
}

func normalizeBuildFinalResponse(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return text }
    let lines = trimmed.components(separatedBy: .newlines)
    let headerScan = lines.prefix(8).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
    let hasEarlyOptionHeader = headerScan.contains {
        $0.hasPrefix("## option")
    }
    let hasStrictOptions = !PlanOptionsParser.parseStrict(from: trimmed).isEmpty
    let checklistItems = lines.reduce(into: 0) { partialResult, line in
        if line.range(of: #"^\s*-\s*\[\s*.\s*\]\s+"#, options: .regularExpression) != nil {
            partialResult += 1
        }
    }
    let hasTodoHeader = lines.contains {
        $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("## todo")
    }
    let looksLikePlanEcho = hasEarlyOptionHeader && hasStrictOptions && hasTodoHeader
        && checklistItems >= 1
    guard looksLikePlanEcho else { return text }
    var kept: [String] = []
    var skippingPlanBlock = false
    var inFence = false
    for line in lines {
        let l = line.trimmingCharacters(in: .whitespaces)
        if l.hasPrefix("```") {
            inFence.toggle()
            if !skippingPlanBlock {
                kept.append(line)
            }
            continue
        }
        if inFence {
            if !skippingPlanBlock {
                kept.append(line)
            }
            continue
        }
        let low = l.lowercased()
        if low.hasPrefix("## option") || low.hasPrefix("## todo") {
            skippingPlanBlock = true
            continue
        }
        if skippingPlanBlock && l.hasPrefix("##") {
            skippingPlanBlock = false
        }
        if !skippingPlanBlock {
            kept.append(line)
        }
    }
    let compact = kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    if compact.isEmpty {
        return text
    }
    return compact
}

func nextPlanFlowPhaseForOutput(
    fullText: String,
    current: PlanFlowPhase,
    coderMode: CoderMode,
    shouldRunPlanInline: Bool
) -> PlanFlowPhase {
    PlanOutputClassifier.classify(
        fullText: fullText,
        current: current,
        coderMode: coderMode,
        shouldRunPlanInline: shouldRunPlanInline
    ).nextPhase
}
