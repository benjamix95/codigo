import Foundation

func reviewCoreLibraryPathForCodeReviewTests(from sourceFile: StaticString) -> String {
    let repoRoot = resolveRepoRoot(from: sourceFile)
    let targetDebug = repoRoot
        .appendingPathComponent("Native/target/debug/libsolocode_rust_core.dylib")
        .path
    if FileManager.default.fileExists(atPath: targetDebug) {
        return targetDebug
    }
    return repoRoot
        .appendingPathComponent("Native/RustCore/build/lib/libsolocode_rust_core.dylib")
        .path
}

/// Walk up from the source file until we find a directory that contains `Native/`.
/// This works regardless of how deeply nested the test file is under the repo root.
private func resolveRepoRoot(from sourceFile: StaticString) -> URL {
    var candidate = URL(fileURLWithPath: "\(sourceFile)").deletingLastPathComponent()
    for _ in 0..<10 {
        let nativeDir = candidate.appendingPathComponent("Native")
        if FileManager.default.fileExists(atPath: nativeDir.path) {
            return candidate
        }
        let parent = candidate.deletingLastPathComponent()
        if parent == candidate { break }
        candidate = parent
    }
    // Fallback: original 4-level assumption (Tests/CoderEngineTests/CodeReview/file.swift)
    let sourceURL = URL(fileURLWithPath: "\(sourceFile)")
    return sourceURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
