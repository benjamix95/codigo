import Foundation

enum CodexMCPHealthState: Equatable {
    case idle
    case checking
    case healthy(profileCount: Int)
    case degraded(profileCount: Int, failingCount: Int)
    case error(String)
}

@MainActor
final class CodexMCPHealthStore: ObservableObject {
    static let shared = CodexMCPHealthStore()

    @Published private(set) var state: CodexMCPHealthState = .idle
    @Published private(set) var lastCheckedAt: Date?

    func refresh() {
        state = .checking
        Task.detached(priority: .utility) {
            let report = Self.collectReport()
            await MainActor.run {
                self.state = report.state
                self.lastCheckedAt = Date()
            }
        }
    }

    func repairProfiles() {
        state = .checking
        Task.detached(priority: .userInitiated) {
            let profiles = Self.codexProfileDirectories()
            for profile in profiles {
                CLIProfileProvisioner.selfHealCodexProfile(at: profile)
            }
            let report = Self.collectReport()
            await MainActor.run {
                self.state = report.state
                self.lastCheckedAt = Date()
            }
        }
    }

    var statusLabel: String {
        switch state {
        case .idle:
            return "MCP status idle"
        case .checking:
            return "Checking MCP setup..."
        case .healthy(let count):
            if count == 0 {
                return "No Codex profiles yet"
            }
            return "MCP ready on \(count) profile\(count == 1 ? "" : "s")"
        case .degraded(let total, let failing):
            return "MCP missing/broken on \(failing)/\(total) profiles"
        case .error(let message):
            return "MCP check failed: \(message)"
        }
    }

    var isHealthy: Bool {
        if case .healthy = state { return true }
        return false
    }

    var canRepair: Bool {
        if case .degraded = state { return true }
        return false
    }

    nonisolated private static func collectReport() -> (state: CodexMCPHealthState, issues: [String]) {
        let profiles = codexProfileDirectories()
        if profiles.isEmpty {
            return (.healthy(profileCount: 0), [])
        }

        var issues: [String] = []
        for profile in profiles {
            if let issue = validateProfile(profile) {
                issues.append("\(profile.lastPathComponent): \(issue)")
            }
        }
        if issues.isEmpty {
            return (.healthy(profileCount: profiles.count), [])
        }
        return (.degraded(profileCount: profiles.count, failingCount: issues.count), issues)
    }

    nonisolated private static func codexProfileDirectories() -> [URL] {
        let root = CLIProfileProvisioner.baseProfilesDir().appendingPathComponent("codex", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return entries.filter { url in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }
    }

    nonisolated private static func validateProfile(_ profileURL: URL) -> String? {
        let configURL = profileURL.appendingPathComponent("config.toml")
        guard let content = try? String(contentsOf: configURL, encoding: .utf8) else {
            return "config.toml missing"
        }
        guard content.contains("[mcp_servers.coderide]") else {
            return "coderide MCP section missing"
        }
        guard let command = parseCoderideCommand(from: content), !command.isEmpty else {
            return "coderide command missing"
        }
        guard FileManager.default.isExecutableFile(atPath: command) else {
            return "coderide command not executable"
        }
        return nil
    }

    nonisolated private static func parseCoderideCommand(from config: String) -> String? {
        let lines = config.components(separatedBy: .newlines)
        var inSection = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                inSection = trimmed == "[mcp_servers.coderide]"
                continue
            }
            guard inSection else { continue }
            guard trimmed.hasPrefix("command") else { continue }
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let raw = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.hasPrefix("\""), raw.hasSuffix("\""), raw.count >= 2 {
                return String(raw.dropFirst().dropLast())
            }
            return raw
        }
        return nil
    }
}
