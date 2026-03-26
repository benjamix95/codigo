import Foundation

/// Scrive workflow GitHub Actions + script shell locale, solo se file `@solocode-managed` o assenti.
public enum WorkspaceLocalCIProvisioner: Sendable {
    public static let workflowRelativePath = ".github/workflows/solocode-auto-ci.yml"
    public static let shellScriptRelativePath = "scripts/solocode-run-local-ci.sh"

    /// Provisiona CI per ogni root del workspace (tipicamente cartelle del contesto attivo).
    public static func provision(roots: [URL]) {
        let fm = FileManager.default
        for root in roots {
            let standardized = root.standardizedFileURL
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: standardized.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            // Progetto SoloCode (o fork con pipeline custom): non sovrascrivere con scaffold generico.
            if fm.fileExists(atPath: standardized.appendingPathComponent("scripts/solocode-validate").path) {
                continue
            }
            let stacks = LocalCIWorkspaceDetector.stacks(for: standardized)
            guard !stacks.isEmpty else { continue }

            let label = standardized.lastPathComponent
            let yaml = LocalCIWorkflowYAML.document(for: stacks, projectLabel: label)
            let shell = LocalCIShellScript.script(for: stacks)

            try? writeAtomically(
                yaml,
                under: standardized,
                relativePath: workflowRelativePath,
                fileManager: fm
            )
            try? writeAtomically(
                shell,
                under: standardized,
                relativePath: shellScriptRelativePath,
                fileManager: fm,
                chmodX: true
            )
        }
    }

    private static func writeAtomically(
        _ content: String,
        under root: URL,
        relativePath: String,
        fileManager: FileManager,
        chmodX: Bool = false
    ) throws {
        let dest = root.appendingPathComponent(relativePath, isDirectory: false)
        let parent = dest.parentDirectory

        if fileManager.fileExists(atPath: dest.path) {
            let existing = try String(contentsOf: dest, encoding: .utf8)
            if !existing.contains("@solocode-managed") {
                return
            }
        }

        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        try content.write(to: dest, atomically: true, encoding: .utf8)
        if chmodX {
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
        }
    }
}

private extension URL {
    var parentDirectory: URL {
        deletingLastPathComponent()
    }
}
