import Foundation

/// Stack tecnologico rilevato nella root del progetto (per scaffold CI locale / GitHub Actions).
public enum LocalCIStack: String, Sendable, Codable, CaseIterable {
    case rust
    case go
    case nodeNpm
    case nodePnpm
    case nodeYarn
    case swiftPackage
    case swiftXcode
    case python
    case javaMaven
    case javaGradle
    case rubyBundler
    case unknown
}
