import Foundation

/// Shared set of directory names excluded from codebase indexing, file watching,
/// and other workspace scanning operations.
public enum ExcludedDirectories {
    /// The canonical list of directories to skip during file enumeration.
    public static let defaultSet: Set<String> = [
        // VCS
        ".git", ".svn", ".hg",
        // Build artifacts
        ".build", "build", "Build", "DerivedData",
        // JS/TS bundler output
        "node_modules", "dist", "out", ".output", ".next", ".nuxt",
        // Caches
        ".cache", ".swiftpm", ".gradle",
        // Python
        "__pycache__", ".pytest_cache", ".mypy_cache",
        "venv", ".venv", "env", ".env",
        ".tox", ".eggs", "*.egg-info",
        "site-packages",
        // Ruby
        "bundle", ".bundle",
        // PHP
        "vendor",
        // Rust
        "target",
        // Go
        "go_modules",
        // Java/Kotlin
        ".m2", ".mvn",
        // .NET
        "packages", "bin", "obj",
        // iOS/macOS
        "Pods", "Carthage",
        // IDE
        ".idea", ".vscode", ".vs",
        // Docker
        ".docker",
        // Terraform
        ".terraform", ".terragrunt-cache",
        // Misc
        "coverage", ".nyc_output",
        ".parcel-cache", ".turbo",
        "bower_components",
        ".pnpm-store",
    ]

    /// Ripgrep `--glob` exclusion arguments for the default set.
    public static var ripgrepGlobArgs: [String] {
        defaultSet.sorted().flatMap { ["--glob", "!\($0)"] }
    }
}
