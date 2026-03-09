import Foundation

public enum ChangeScopeAnalyzer {
    public static func resolveFiles(
        context: ValidationContext,
        descriptor: ProjectValidationDescriptor
    ) async throws -> [String] {
        let explicit = normalize(context.touchedFiles)
        if !explicit.isEmpty {
            return explicit
        }
        if context.stagedOnly {
            return try await stagedFiles(workspaceRoot: context.workspaceRoot)
        }
        if let patchText = context.patchText {
            return normalize(filesFromPatch(patchText))
        }
        return []
    }

    public static func filesFromPatch(_ patchText: String) -> [String] {
        patchText
            .split(separator: "\n")
            .compactMap { line -> String? in
                guard line.hasPrefix("+++ b/") else { return nil }
                return String(line.dropFirst(6))
            }
    }

    public static func normalize(_ files: [String]) -> [String] {
        Array(Set(files.map {
            let slashes = $0.replacingOccurrences(of: "\\", with: "/")
            let trimmed = slashes.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.hasPrefix("./") ? String(trimmed.dropFirst(2)) : trimmed
        }.filter { !$0.isEmpty })).sorted()
    }

    private static func stagedFiles(workspaceRoot: URL) async throws -> [String] {
        let command = ["/usr/bin/git", "diff", "--cached", "--name-only", "--diff-filter=ACMR"]
        let result = try await ValidationCommandExecutor.run(
            executable: command[0],
            arguments: Array(command.dropFirst()),
            workingDirectory: workspaceRoot
        )
        return normalize(result.output.split(separator: "\n").map(String.init))
    }
}
