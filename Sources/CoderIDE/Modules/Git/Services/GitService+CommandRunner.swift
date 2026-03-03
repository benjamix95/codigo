import Foundation

extension GitService {
    private func isGhInstalled() -> Bool {
        (try? runCommand(executable: "/usr/bin/env", args: ["which", "gh"], cwd: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ?? false
    }

    private func isGhAuthenticated(gitRoot: String) -> Bool {
        (try? runCommand(executable: "/usr/bin/env", args: ["gh", "auth", "status"], cwd: gitRoot)) != nil
    }

    @discardableResult
    private func runGit(_ args: [String], gitRoot: String) throws -> String {
        try runCommand(executable: gitPath, args: args, cwd: gitRoot)
    }

    @discardableResult
    private func runCommand(executable: String, args: [String], cwd: String?) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        if let cwd, !cwd.isEmpty {
            p.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        p.waitUntilExit()

        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if p.terminationStatus != 0 {
            let cmd = ([executable] + args).joined(separator: " ")
            throw GitServiceError.commandFailed("Command failed (\(cmd)): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return stdout
    }
}
