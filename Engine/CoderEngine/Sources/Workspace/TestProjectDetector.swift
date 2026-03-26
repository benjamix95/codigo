import Foundation

/// Detected project type for test execution
public enum ProjectType: String, Sendable {
    case swift
    case node
    case python
    case rust
    case go
    case java
    case ruby
    case unknown
}

/// Rileva il tipo di progetto nel workspace per determinare il comando di test appropriato
public enum TestProjectDetector: Sendable {
    /// Rileva il tipo di progetto nella root del workspace
    public static func detect(workspacePath: URL) -> ProjectType {
        let fm = FileManager.default
        let root = workspacePath.path

        if fm.fileExists(atPath: (workspacePath.appendingPathComponent("Cargo.toml").path)) {
            return .rust
        }
        if fm.fileExists(atPath: (workspacePath.appendingPathComponent("go.mod").path)) {
            return .go
        }
        if fm.fileExists(atPath: (workspacePath.appendingPathComponent("package.json").path)) {
            return .node
        }
        if fm.fileExists(atPath: (workspacePath.appendingPathComponent("Package.swift").path)) {
            return .swift
        }
        if hasXcodeProject(fm, at: root) {
            return .swift
        }
        if fm.fileExists(atPath: (workspacePath.appendingPathComponent("pyproject.toml").path))
            || fm.fileExists(atPath: (workspacePath.appendingPathComponent("setup.py").path))
            || fm.fileExists(atPath: (workspacePath.appendingPathComponent("requirements.txt").path)) {
            return .python
        }
        if fm.fileExists(atPath: (workspacePath.appendingPathComponent("pom.xml").path))
            || fm.fileExists(atPath: (workspacePath.appendingPathComponent("build.gradle").path))
            || fm.fileExists(atPath: (workspacePath.appendingPathComponent("build.gradle.kts").path)) {
            return .java
        }
        if fm.fileExists(atPath: (workspacePath.appendingPathComponent("Gemfile").path)) {
            return .ruby
        }
        return .unknown
    }

    private static func hasXcodeProject(_ fm: FileManager, at root: String) -> Bool {
        guard let names = try? fm.contentsOfDirectory(atPath: root) else { return false }
        return names.contains { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }
    }

    /// Returns the command to run for tests, or nil if project type is not recognized
    public static func testCommand(workspacePath: URL) -> (executable: String, arguments: [String])? {
        switch detect(workspacePath: workspacePath) {
        case .swift:
            let fm = FileManager.default
            if fm.fileExists(atPath: workspacePath.appendingPathComponent("Package.swift").path) {
                return (PathFinder.find(executable: "swift") ?? "/usr/bin/swift", ["test"])
            }
            guard let names = try? fm.contentsOfDirectory(atPath: workspacePath.path),
                  let proj = names.first(where: { $0.hasSuffix(".xcodeproj") }) else {
                return (PathFinder.find(executable: "swift") ?? "/usr/bin/swift", ["test"])
            }
            let projPath = workspacePath.appendingPathComponent(proj).path
            let scheme = (proj as NSString).deletingPathExtension
            let xcb = PathFinder.find(executable: "xcodebuild") ?? "/usr/bin/xcodebuild"
            return (
                xcb,
                ["-project", projPath, "-scheme", scheme, "-destination", "platform=macOS", "build"]
            )
        case .node:
            return (PathFinder.find(executable: "npm") ?? "/usr/bin/npm", ["test"])
        case .python:
            if let pytest = PathFinder.find(executable: "pytest") {
                return (pytest, [])
            }
            return (PathFinder.find(executable: "python3") ?? "/usr/bin/python3", ["-m", "pytest"])
        case .rust:
            return (PathFinder.find(executable: "cargo") ?? "/usr/bin/cargo", ["test"])
        case .go:
            let go = PathFinder.find(executable: "go") ?? "/usr/bin/go"
            return (go, ["test", "./..."])
        case .java:
            let fm = FileManager.default
            if fm.fileExists(atPath: workspacePath.appendingPathComponent("pom.xml").path) {
                let mvn = PathFinder.find(executable: "mvn") ?? "/usr/bin/mvn"
                return (mvn, ["test"])
            }
            let gradlew = workspacePath.appendingPathComponent("gradlew").path
            if fm.fileExists(atPath: gradlew) {
                return (gradlew, ["test"])
            }
            return (PathFinder.find(executable: "gradle") ?? "/usr/bin/gradle", ["test"])
        case .ruby:
            let bundle = PathFinder.find(executable: "bundle") ?? "/usr/bin/bundle"
            return (bundle, ["exec", "rake", "test"])
        case .unknown:
            return nil
        }
    }
}
