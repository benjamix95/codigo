import SwiftUI

// MARK: - Package Manager Store

/// Store per la gestione delle dipendenze SPM del progetto.
@MainActor
final class PackageManagerStore: ObservableObject {
    /// Dipendenza SPM del progetto.
    struct PackageDependency: Identifiable, Sendable {
        let id: String
        let name: String
        let url: String
        let version: String
        let isLocal: Bool
    }

    /// Stato del Package Manager.
    enum PMState: Sendable {
        case idle
        case resolving
        case updating
        case error(String)
    }

    @Published var dependencies: [PackageDependency] = []
    @Published var state: PMState = .idle
    @Published var resolvedOutput: String = ""

    private var projectPath: String?

    func configure(projectPath: String) {
        self.projectPath = projectPath
    }

    // MARK: - Azioni

    /// Carica le dipendenze dal Package.resolved.
    func loadDependencies() {
        guard let path = projectPath else { return }
        state = .resolving

        Task {
            let deps = await parseDependencies(projectPath: path)
            dependencies = deps
            state = .idle
        }
    }

    /// Esegue swift package resolve.
    func resolve() {
        guard let path = projectPath else { return }
        state = .resolving
        resolvedOutput = ""

        Task {
            let result = await runSwiftPackage(
                arguments: ["resolve"],
                workingDirectory: path
            )
            resolvedOutput = result.output
            state = result.success ? .idle : .error(result.output)
            if result.success { loadDependencies() }
        }
    }

    /// Esegue swift package update.
    func update() {
        guard let path = projectPath else { return }
        state = .updating
        resolvedOutput = ""

        Task {
            let result = await runSwiftPackage(
                arguments: ["update"],
                workingDirectory: path
            )
            resolvedOutput = result.output
            state = result.success ? .idle : .error(result.output)
            if result.success { loadDependencies() }
        }
    }

    /// Pulisce la cache dei package.
    func cleanCache() {
        guard let path = projectPath else { return }

        Task {
            _ = await runSwiftPackage(
                arguments: ["purge-cache"],
                workingDirectory: path
            )
            _ = await runSwiftPackage(
                arguments: ["reset"],
                workingDirectory: path
            )
        }
    }

    // MARK: - Privato

    private struct CommandResult: Sendable {
        let success: Bool
        let output: String
    }

    private func runSwiftPackage(
        arguments: [String],
        workingDirectory: String
    ) async -> CommandResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
            process.arguments = ["package"] + arguments
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do { try process.run() } catch {
                continuation.resume(returning: CommandResult(
                    success: false, output: error.localizedDescription
                ))
                return
            }

            process.terminationHandler = { proc in
                let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: CommandResult(
                    success: proc.terminationStatus == 0,
                    output: out + (err.isEmpty ? "" : "\n" + err)
                ))
            }
        }
    }

    private func parseDependencies(projectPath: String) async -> [PackageDependency] {
        let resolvedPath = (projectPath as NSString)
            .appendingPathComponent("Package.resolved")

        guard let data = FileManager.default.contents(atPath: resolvedPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        // Package.resolved v2/v3 format
        let pins: [[String: Any]]
        if let v2 = json["pins"] as? [[String: Any]] {
            pins = v2
        } else if let obj = json["object"] as? [String: Any],
                  let p = obj["pins"] as? [[String: Any]] {
            pins = p
        } else {
            return []
        }

        return pins.compactMap { pin -> PackageDependency? in
            let identity = pin["identity"] as? String ?? ""
            let location = pin["location"] as? String
                ?? (pin["repositoryURL"] as? String ?? "")
            let state = pin["state"] as? [String: Any] ?? [:]
            let version = state["version"] as? String
                ?? state["revision"] as? String ?? "unknown"

            guard !identity.isEmpty else { return nil }

            return PackageDependency(
                id: identity,
                name: identity,
                url: location,
                version: version,
                isLocal: location.hasPrefix("/") || location.hasPrefix("file://")
            )
        }
    }
}
