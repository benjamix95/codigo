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
        // Esportazioni locali (report, PDF, ecc.)
        "output",
        // JS/TS bundler output & package trees
        "node_modules", "dist", "out", ".output", ".next", ".nuxt",
        "jspm_packages", "bower_components",
        ".turbo", ".parcel-cache", ".pnpm-store", ".vite", ".svelte-kit",
        // Caches
        ".cache", ".swiftpm", ".gradle",
        // Python
        "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache",
        "venv", ".venv", "env", "ENV",
        ".conda",
        ".tox", ".nox", ".hypothesis", ".eggs",
        "site-packages",
        // Ruby / Bundler (anche `vendor/bundle` → componente `bundle`)
        "vendor", "bundle", ".bundle",
        // Rust / JVM build output (Maven/sbt usano anch’essi `target`)
        "target",
        // Java/Kotlin tooling
        ".m2", ".mvn",
        // .NET
        "packages", "bin", "obj",
        // Elixir / Erlang
        "_build", "deps",
        // Haskell
        "dist-newstyle",
        // Zig
        "zig-cache", "zig-out",
        // R (renv)
        "renv",
        // iOS/macOS
        "Pods", "Carthage",
        // IDE
        ".idea", ".vscode", ".vs", ".metals", ".bloop", ".elixir_ls",
        // Docker
        ".docker",
        // Terraform
        ".terraform", ".terragrunt-cache",
        // Coverage
        "coverage", ".nyc_output", "htmlcov",
        // CMake local dirs (nomi più comuni)
        "cmake-build-debug", "cmake-build-release", "cmake-build-relwithdebinfo",
        "cmake-build-minsizerel",
    ]

    /// Ripgrep `--glob` exclusion arguments for the default set.
    public static var ripgrepGlobArgs: [String] {
        defaultSet.sorted().flatMap { ["--glob", "!\($0)"] }
    }
}
