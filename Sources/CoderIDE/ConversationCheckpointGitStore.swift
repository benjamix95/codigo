import Foundation

struct ConversationCheckpointGitStore {
    struct Snapshot: Equatable {
        let ref: String
        let gitRoot: String
    }

    enum GitStoreError: LocalizedError {
        case notGitRepository(String)
        case snapshotNotFound(String)
        case invalidGitRoot(String)
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .notGitRepository(let path):
                return "Checkpoint non disponibile: \(path) non e' una repository git."
            case .snapshotNotFound(let ref):
                return "Snapshot git non trovato: \(ref)."
            case .invalidGitRoot(let root):
                return "Root git non valida: \(root)."
            case .commandFailed(let message):
                return message
            }
        }
    }

    private let git = "/usr/bin/git"
    private let emptyTree = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

    func captureSnapshots(conversationId: UUID, workspacePaths: [String]) throws -> [ConversationCheckpointGitState] {
        let roots = try resolveGitRoots(from: workspacePaths)
        return try roots.map { root in
            let snapshot = try captureSnapshot(conversationId: conversationId, workingDirectory: root)
            return ConversationCheckpointGitState(gitRootPath: snapshot.gitRoot, gitSnapshotRef: snapshot.ref)
        }
    }

    func captureSnapshot(conversationId: UUID, workingDirectory: String) throws -> Snapshot {
        let gitRoot = try resolveGitRoot(workingDirectory: workingDirectory)
        let refName = checkpointRefName(conversationId: conversationId)
        let previousRef = try? runGit(["rev-parse", "--verify", refName], cwd: gitRoot).trimmingCharacters(in: .whitespacesAndNewlines)

        let indexPath = temporaryIndexPath()
        defer { try? FileManager.default.removeItem(atPath: indexPath) }
        _ = FileManager.default.createFile(atPath: indexPath, contents: Data())
        var env = ProcessInfo.processInfo.environment
        env["GIT_INDEX_FILE"] = indexPath

        if let prev = previousRef, !prev.isEmpty {
            _ = try runGit(["read-tree", prev], cwd: gitRoot, environment: env)
        } else {
            // New checkpoint lineage: start from HEAD tree if available, else empty tree.
            if (try? runGit(["rev-parse", "--verify", "HEAD^{tree}"], cwd: gitRoot, environment: env)) != nil {
                _ = try runGit(["read-tree", "HEAD"], cwd: gitRoot, environment: env)
            } else {
                _ = try runGit(["read-tree", emptyTree], cwd: gitRoot, environment: env)
            }
        }

        _ = try runGit(["add", "-A"], cwd: gitRoot, environment: env)
        let tree = try runGit(["write-tree"], cwd: gitRoot, environment: env).trimmingCharacters(in: .whitespacesAndNewlines)
        if tree.isEmpty {
            throw GitStoreError.commandFailed("Impossibile creare tree git per checkpoint.")
        }

        var commitArgs = ["commit-tree", tree]
        if let prev = previousRef, !prev.isEmpty {
            commitArgs.append(contentsOf: ["-p", prev])
        }
        commitArgs.append(contentsOf: ["-m", "checkpoint:\(conversationId.uuidString):\(Int(Date().timeIntervalSince1970))"])
        let commit = try runGit(commitArgs, cwd: gitRoot).trimmingCharacters(in: .whitespacesAndNewlines)
        if commit.isEmpty {
            throw GitStoreError.commandFailed("Impossibile creare commit snapshot.")
        }
        _ = try runGit(["update-ref", refName, commit], cwd: gitRoot)
        return Snapshot(ref: commit, gitRoot: gitRoot)
    }

    func restoreSnapshot(ref: String, gitRoot: String) throws {
        guard FileManager.default.fileExists(atPath: gitRoot) else {
            throw GitStoreError.invalidGitRoot(gitRoot)
        }
        do {
            _ = try runGit(["cat-file", "-e", "\(ref)^{commit}"], cwd: gitRoot)
        } catch {
            throw GitStoreError.snapshotNotFound(ref)
        }

        do {
            _ = try runGit(["restore", "--source", ref, "--worktree", ":/"], cwd: gitRoot)
        } catch {
            _ = try runGit(["checkout", ref, "--", "."], cwd: gitRoot)
        }

        let snapshotFiles = try snapshotFileSet(ref: ref, gitRoot: gitRoot)
        try deleteFilesNotInSnapshot(snapshotFiles, gitRoot: gitRoot)
    }

    func deleteSnapshotBranch(conversationId: UUID, gitRoot: String) throws {
        guard FileManager.default.fileExists(atPath: gitRoot) else { return }
        let refName = checkpointRefName(conversationId: conversationId)
        _ = try? runGit(["update-ref", "-d", refName], cwd: gitRoot)
    }

    private func resolveGitRoots(from workspacePaths: [String]) throws -> [String] {
        let roots = try workspacePaths.compactMap { path -> String? in
            guard !path.isEmpty else { return nil }
            return try resolveGitRoot(workingDirectory: path)
        }
        let unique = Array(Set(roots)).sorted()
        if unique.isEmpty {
            throw GitStoreError.notGitRepository(workspacePaths.first ?? "workspace")
        }
        return unique
    }

    private func resolveGitRoot(workingDirectory: String) throws -> String {
        do {
            return try runGit(["rev-parse", "--show-toplevel"], cwd: workingDirectory).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw GitStoreError.notGitRepository(workingDirectory)
        }
    }

    private func checkpointRefName(conversationId: UUID) -> String {
        "refs/codex-checkpoints/\(conversationId.uuidString.lowercased())"
    }

    private func temporaryIndexPath() -> String {
        let base = FileManager.default.temporaryDirectory.path
        return (base as NSString).appendingPathComponent("codex-checkpoint-index-\(UUID().uuidString)")
    }

    private func snapshotFileSet(ref: String, gitRoot: String) throws -> Set<String> {
        let out = try runGit(["ls-tree", "-r", "--name-only", ref], cwd: gitRoot)
        let files = out
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Set(files)
    }

    private func deleteFilesNotInSnapshot(_ snapshotFiles: Set<String>, gitRoot: String) throws {
        let rootURL = URL(fileURLWithPath: gitRoot, isDirectory: true)
        let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey],
            options: [],
            errorHandler: nil
        )

        while let url = enumerator?.nextObject() as? URL {
            if url.lastPathComponent == ".git" {
                enumerator?.skipDescendants()
                continue
            }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey])
            guard (values.isRegularFile == true) || (values.isSymbolicLink == true) else { continue }
            let rel = relativePath(url: url, base: rootURL)
            if !snapshotFiles.contains(rel) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func relativePath(url: URL, base: URL) -> String {
        let basePath = base.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path.hasPrefix(basePath + "/") {
            return String(path.dropFirst(basePath.count + 1))
        }
        return url.lastPathComponent
    }

    @discardableResult
    private func runGit(_ args: [String], cwd: String, environment: [String: String]? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: git)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()

        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            let cmd = "git " + args.joined(separator: " ")
            let tail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitStoreError.commandFailed("Comando fallito (\(cmd)): \(tail.isEmpty ? "errore sconosciuto" : tail)")
        }
        return stdout
    }
}
