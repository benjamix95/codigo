import CoderEngine
import Foundation

enum LanguageServiceError: Error {
    case disabled
    case unsupported(String)
}

protocol LanguageServiceAdapter: Sendable {
    var source: LanguageServiceSource { get }
    func goToDefinition(symbol: String, fileHint: String?) async throws -> [LanguageLocation]
    func hover(symbol: String, fileHint: String?) async throws -> LanguageHoverResult?
    func findReferences(symbol: String, limit: Int) async throws -> [LanguageLocation]
    func rename(oldName: String, newName: String) async throws -> LanguageRenamePlan
}

actor LocalIndexLanguageAdapter: LanguageServiceAdapter {
    nonisolated let source: LanguageServiceSource = .localIndex
    private let index: CodebaseIndex

    init(index: CodebaseIndex) {
        self.index = index
    }

    func goToDefinition(symbol: String, fileHint: String?) async throws -> [LanguageLocation] {
        let exact = await index.findExactSymbol(name: symbol)
        let filtered = exact.filter { item in
            guard let fileHint, !fileHint.isEmpty else { return true }
            return item.filePath == fileHint || item.filePath.hasSuffix(fileHint)
        }
        let candidates = filtered.isEmpty ? exact : filtered
        let mapped = candidates.map {
            LanguageLocation(
                filePath: $0.filePath,
                line: $0.line,
                column: nil,
                symbolName: $0.name,
                source: source
            )
        }
        return LanguageServiceResultCanonicalizer.canonicalize(
            locations: mapped,
            symbolName: symbol
        )
    }

    func hover(symbol: String, fileHint: String?) async throws -> LanguageHoverResult? {
        let definitions = try await goToDefinition(symbol: symbol, fileHint: fileHint)
        guard let first = definitions.first else { return nil }
        let symbols = await index.symbolsInFile(first.filePath)
        guard let matched = symbols.first(where: { $0.name == symbol }) ?? symbols.first else {
            return nil
        }
        let text = [matched.signature, matched.documentation ?? ""]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
        return LanguageServiceResultCanonicalizer.canonicalize(
            hover: text.isEmpty ? nil : LanguageHoverResult(contents: text, source: source),
            source: source
        )
    }

    func findReferences(symbol: String, limit: Int) async throws -> [LanguageLocation] {
        let refs = await index.findReferences(symbolName: symbol, limit: limit)
        let mapped = refs.map {
            LanguageLocation(
                filePath: $0.filePath,
                line: $0.line,
                column: nil,
                symbolName: symbol,
                source: source
            )
        }
        return LanguageServiceResultCanonicalizer.canonicalize(
            locations: mapped,
            symbolName: symbol,
            source: source,
            limit: limit
        )
    }

    func rename(oldName: String, newName: String) async throws -> LanguageRenamePlan {
        let refs = try await findReferences(symbol: oldName, limit: 10_000)
        return LanguageServiceResultCanonicalizer.canonicalize(
            renamePlan: LanguageRenamePlan(
                oldName: oldName,
                newName: newName,
                references: refs,
                source: source
            ),
            requestedOldName: oldName,
            requestedNewName: newName,
            source: source
        )
    }
}
