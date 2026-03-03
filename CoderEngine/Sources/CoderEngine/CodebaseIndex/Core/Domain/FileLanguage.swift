import Foundation

// MARK: - FileLanguage

public enum FileLanguage: String, Sendable, Codable, CaseIterable {
    case swift
    case python
    case javascript
    case javascriptReact
    case typescript
    case typescriptReact
    case go
    case rust
    case java
    case kotlin
    case ruby
    case php
    case csharp
    case c
    case cpp
    case objectiveC
    case objectiveCPP
    case header
    case dart
    case elixir
    case scala
    case haskell
    case lua
    case r
    case zig
    case graphql
    case proto
    case html
    case css
    case markdown
    case toml
    case xml
    case plist
    case json
    case yaml
    case sql
    case shell
    case unknown

    static func from(extension ext: String) -> FileLanguage {
        switch ext.lowercased() {
        case "swift", "storyboard", "xib":
            return .swift
        case "m":
            return .objectiveC
        case "mm":
            return .objectiveCPP
        case "h", "hpp", "hxx":
            return .header
        case "c":
            return .c
        case "cpp", "cc", "cxx":
            return .cpp
        case "py", "pyw", "pyi":
            return .python
        case "js", "mjs", "cjs", "jsx":
            return .javascript
        case "ts", "mts", "cts", "tsx":
            return .typescript
        case "go":
            return .go
        case "rs":
            return .rust
        case "java":
            return .java
        case "kt", "kts":
            return .kotlin
        case "rb", "rake":
            return .ruby
        case "php":
            return .php
        case "cs":
            return .csharp
        case "dart":
            return .dart
        case "ex", "exs":
            return .elixir
        case "scala", "sc":
            return .scala
        case "hs":
            return .haskell
        case "lua":
            return .lua
        case "r":
            return .r
        case "zig":
            return .zig
        case "html", "htm":
            return .html
        case "css", "scss", "sass", "less":
            return .css
        case "json", "jsonc", "json5":
            return .json
        case "yml", "yaml":
            return .yaml
        case "toml":
            return .toml
        case "xml", "plist":
            return .xml
        case "md", "markdown", "rst":
            return .markdown
        case "sh", "bash", "zsh", "fish":
            return .shell
        case "sql":
            return .sql
        case "graphql", "gql":
            return .graphql
        case "proto":
            return .proto
        default:
            return .unknown
        }
    }
}

