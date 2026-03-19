import Foundation

func reviewCoreLibraryPath(from sourceFile: StaticString) -> String {
    let sourceURL = URL(fileURLWithPath: "\(sourceFile)")
    let repoRoot = sourceURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
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
