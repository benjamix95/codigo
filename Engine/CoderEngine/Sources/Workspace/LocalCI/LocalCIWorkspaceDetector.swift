import Foundation

/// Rileva uno o più stack nella root del repository (ordine stabile: tooling “pesante” prima).
public enum LocalCIWorkspaceDetector: Sendable {
    public static func stacks(for root: URL) -> [LocalCIStack] {
        let fm = FileManager.default
        let path = root.path
        var seen = Set<LocalCIStack>()
        var ordered: [LocalCIStack] = []

        func append(_ stack: LocalCIStack) {
            guard stack != .unknown, seen.insert(stack).inserted else { return }
            ordered.append(stack)
        }

        if exists(fm, path, "Cargo.toml") { append(.rust) }
        if exists(fm, path, "go.mod") { append(.go) }
        if exists(fm, path, "package.json") {
            if exists(fm, path, "pnpm-lock.yaml") {
                append(.nodePnpm)
            } else if exists(fm, path, "yarn.lock") {
                append(.nodeYarn)
            } else {
                append(.nodeNpm)
            }
        }
        if exists(fm, path, "Package.swift") {
            append(.swiftPackage)
        } else if hasXcodeProject(fm, at: path) {
            append(.swiftXcode)
        }
        if exists(fm, path, "pyproject.toml")
            || exists(fm, path, "setup.py")
            || exists(fm, path, "requirements.txt") {
            append(.python)
        }
        if exists(fm, path, "pom.xml") { append(.javaMaven) }
        if exists(fm, path, "build.gradle")
            || exists(fm, path, "build.gradle.kts") {
            append(.javaGradle)
        }
        if exists(fm, path, "Gemfile") { append(.rubyBundler) }

        return ordered
    }

    private static func exists(_ fm: FileManager, _ root: String, _ name: String) -> Bool {
        fm.fileExists(atPath: (root as NSString).appendingPathComponent(name))
    }

    private static func hasXcodeProject(_ fm: FileManager, at root: String) -> Bool {
        guard let names = try? fm.contentsOfDirectory(atPath: root) else { return false }
        return names.contains { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }
    }
}
