import Darwin
import Foundation

extension RustSearchFFIClient {
    static func candidateLibraryPaths() -> [String] {
        var candidates: [String] = []
        let env = ProcessInfo.processInfo.environment
        let libName = "libsolocode_rust_core.dylib"
        let subdir = "solocode_rust"

        for key in ["SOLOCODE_REVIEW_CORE_LIBRARY_PATH", "SOLOCODE_RUST_SEARCH_LIBRARY_PATH"] {
            guard let path = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !path.isEmpty else { continue }
            candidates.append(path)
        }

        if let executableDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            candidates.append(executableDir.appendingPathComponent("\(subdir)/\(libName)").path)
        }
        for relativePath in [
            "Contents/MacOS/\(subdir)/\(libName)",
            "Contents/Resources/\(subdir)/\(libName)",
        ] {
            candidates.append(Bundle.main.bundleURL.appendingPathComponent(relativePath).path)
        }

        if let builtProducts = env["BUILT_PRODUCTS_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !builtProducts.isEmpty {
            candidates.append("\(builtProducts)/\(subdir)/\(libName)")
        }
        if let srcRoot = env["SRCROOT"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !srcRoot.isEmpty {
            candidates.append("\(srcRoot)/Native/RustCore/build/lib/\(libName)")
            candidates.append("\(srcRoot)/Native/target/debug/\(libName)")
        }

        let cwd = FileManager.default.currentDirectoryPath
        candidates.append("\(cwd)/Native/target/debug/\(libName)")
        candidates.append("\(cwd)/Native/RustCore/build/lib/\(libName)")

        if let workspace = env["SOLOCODE_WORKSPACE_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !workspace.isEmpty {
            candidates.append("\(workspace)/Native/target/debug/\(libName)")
            candidates.append("\(workspace)/Native/RustCore/build/lib/\(libName)")
        }

        if shouldScanDerivedDataForRustReviewCoreFallback(
            environment: env,
            bundleURL: Bundle.main.bundleURL
        ) {
            scanDerivedDataForDylib(libName, subdir: subdir, into: &candidates)
        }

        var cursor = Bundle.main.bundleURL
        for _ in 0..<4 {
            cursor.deleteLastPathComponent()
            candidates.append(cursor.appendingPathComponent("\(subdir)/\(libName)").path)
            candidates.append(cursor.appendingPathComponent(libName).path)
        }
        return Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates
    }

    static func scanDerivedDataForDylib(
        _ libName: String,
        subdir: String,
        into candidates: inout [String]
    ) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let derivedData = home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: derivedData,
            includingPropertiesForKeys: nil
        ) else { return }

        for entry in entries where entry.lastPathComponent.hasPrefix("Solo_Code-") {
            for config in ["Debug", "Release"] {
                let path = entry
                    .appendingPathComponent("Build/Products/\(config)/Solo Code.app/Contents/MacOS/\(subdir)/\(libName)")
                candidates.append(path.path)
            }
        }
    }

    static func currentDLError() -> String? {
        guard let error = dlerror() else { return nil }
        return String(cString: error)
    }
}
