import Foundation

/// Tipo di progetto rilevato per esecuzione test
public enum ProjectType: String, Sendable {
    case swift
    case node
    case python
    case rust
    case unknown
}

/// Rileva il tipo di progetto nel workspace per determinare il comando di test appropriato
public enum TestProjectDetector: Sendable {
    /// Rileva il tipo di progetto nella root del workspace
    public static func detect(workspacePath: URL) -> ProjectType {
        let fm = FileManager.default

        if fm.fileExists(atPath: (workspacePath.appendingPathComponent("Package.swift").path)) {
            return .swift
        }
        if fm.fileExists(atPath: (workspacePath.appendingPathComponent("package.json").path)) {
            return .node
        }
        if fm.fileExists(atPath: (workspacePath.appendingPathComponent("pyproject.toml").path))
            || fm.fileExists(atPath: (workspacePath.appendingPathComponent("setup.py").path))
            || fm.fileExists(atPath: (workspacePath.appendingPathComponent("requirements.txt").path)) {
            return .python
        }
        if fm.fileExists(atPath: (workspacePath.appendingPathComponent("Cargo.toml").path)) {
            return .rust
        }
        return .unknown
    }

    /// Restituisce il comando da eseguire per i test, o nil se tipo non riconosciuto
    public static func testCommand(workspacePath: URL) -> (executable: String, arguments: [String])? {
        switch detect(workspacePath: workspacePath) {
        case .swift:
            return (PathFinder.find(executable: "swift") ?? "/usr/bin/swift", ["test"])
        case .node:
            return (PathFinder.find(executable: "npm") ?? "/usr/bin/npm", ["test"])
        case .python:
            if let pytest = PathFinder.find(executable: "pytest") {
                return (pytest, [])
            }
            return (PathFinder.find(executable: "python3") ?? "/usr/bin/python3", ["-m", "pytest"])
        case .rust:
            return (PathFinder.find(executable: "cargo") ?? "/usr/bin/cargo", ["test"])
        case .unknown:
            return nil
        }
    }
}
