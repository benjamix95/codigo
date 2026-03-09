import Foundation

struct CodeSizeStage: ValidationStage {
    let id: ValidationStageID = .codeSize
    private let maxLines = 300

    func run(
        context: ValidationContext,
        profile: ValidationProfile,
        descriptor: ProjectValidationDescriptor
    ) async -> ValidationStageResult {
        do {
            let offending = try currentOffenders(context: context, descriptor: descriptor)
            if offending.isEmpty {
                return ValidationStageResult(stage: id, status: .passed, summary: "Tutti i file toccati rispettano il limite \(maxLines) LOC.")
            }
            return ValidationStageResult(stage: id, status: .failed, summary: offending.joined(separator: " | "))
        } catch {
            return ValidationStageResult(stage: id, status: .failed, summary: "Impossibile verificare il limite file size: \(error.localizedDescription)")
        }
    }

    private func currentOffenders(
        context: ValidationContext,
        descriptor: ProjectValidationDescriptor
    ) throws -> [String] {
        try ChangeScopeAnalyzer.normalize(context.touchedFiles).compactMap { file in
            guard isTrackedCodeFile(file, descriptor: descriptor) else { return nil }
            let fileURL = context.workspaceRoot.appendingPathComponent(file)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
            let newLines = try countLines(fileURL)
            guard newLines > maxLines else { return nil }
            let oldLines = try previousLineCount(for: file, workspaceRoot: context.workspaceRoot)
            if oldLines == nil {
                return "\(file) supera \(maxLines) righe come file nuovo (\(newLines))."
            }
            if let oldLines, oldLines <= maxLines || newLines > oldLines {
                return "\(file) supera \(maxLines) righe (\(oldLines)->\(newLines))."
            }
            return nil
        }
    }

    private func isTrackedCodeFile(_ path: String, descriptor: ProjectValidationDescriptor) -> Bool {
        if descriptor.excludedCodePaths.contains(where: { glob in pathMatches(path: path, glob: glob) }) {
            return false
        }
        return descriptor.codeFileGlobs.contains { glob in pathMatches(path: path, glob: glob) }
    }

    private func pathMatches(path: String, glob: String) -> Bool {
        let normalizedGlob = NSRegularExpression.escapedPattern(for: glob)
            .replacingOccurrences(of: "\\*\\*", with: ".*")
            .replacingOccurrences(of: "\\*", with: "[^/]*")
        let regex = try? NSRegularExpression(pattern: "^\(normalizedGlob)$")
        let range = NSRange(path.startIndex..<path.endIndex, in: path)
        return regex?.firstMatch(in: path, range: range) != nil
    }

    private func countLines(_ url: URL) throws -> Int {
        try String(contentsOf: url, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).count
    }

    private func previousLineCount(for file: String, workspaceRoot: URL) throws -> Int? {
        let result = try? ProcessRunner.runCollectingSync(
            executable: "/usr/bin/git",
            arguments: ["show", "HEAD:\(file)"],
            workingDirectory: workspaceRoot
        )
        guard let result, result.terminationStatus == 0 else { return nil }
        return result.output.split(separator: "\n", omittingEmptySubsequences: false).count
    }
}
