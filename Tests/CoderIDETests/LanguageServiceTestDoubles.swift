import Foundation
@testable import CoderIDE

actor FailingLanguageAdapter: LanguageServiceAdapter {
    nonisolated let source: LanguageServiceSource = .sourceKitLSP

    func goToDefinition(symbol: String, fileHint: String?) async throws -> [LanguageLocation] {
        throw LanguageServiceError.unsupported("forced failure")
    }

    func hover(symbol: String, fileHint: String?) async throws -> LanguageHoverResult? {
        throw LanguageServiceError.unsupported("forced failure")
    }

    func findReferences(symbol: String, limit: Int) async throws -> [LanguageLocation] {
        throw LanguageServiceError.unsupported("forced failure")
    }

    func rename(oldName: String, newName: String) async throws -> LanguageRenamePlan {
        throw LanguageServiceError.unsupported("forced failure")
    }
}

actor SuccessfulLanguageAdapter: LanguageServiceAdapter {
    nonisolated let source: LanguageServiceSource = .sourceKitLSP

    func goToDefinition(symbol: String, fileHint: String?) async throws -> [LanguageLocation] {
        [
            LanguageLocation(
                filePath: "/tmp/Fake.swift",
                line: 10,
                column: 4,
                symbolName: symbol,
                source: .sourceKitLSP
            )
        ]
    }

    func hover(symbol: String, fileHint: String?) async throws -> LanguageHoverResult? {
        LanguageHoverResult(contents: "SourceKit hover", source: .sourceKitLSP)
    }

    func findReferences(symbol: String, limit: Int) async throws -> [LanguageLocation] {
        [
            LanguageLocation(
                filePath: "/tmp/Fake.swift",
                line: 12,
                column: 2,
                symbolName: symbol,
                source: .sourceKitLSP
            )
        ]
    }

    func rename(oldName: String, newName: String) async throws -> LanguageRenamePlan {
        LanguageRenamePlan(oldName: oldName, newName: newName, references: [], source: .sourceKitLSP)
    }
}

actor EmptyLanguageAdapter: LanguageServiceAdapter {
    nonisolated let source: LanguageServiceSource = .sourceKitLSP

    func goToDefinition(symbol: String, fileHint: String?) async throws -> [LanguageLocation] {
        []
    }

    func hover(symbol: String, fileHint: String?) async throws -> LanguageHoverResult? {
        nil
    }

    func findReferences(symbol: String, limit: Int) async throws -> [LanguageLocation] {
        []
    }

    func rename(oldName: String, newName: String) async throws -> LanguageRenamePlan {
        LanguageRenamePlan(oldName: oldName, newName: newName, references: [], source: .sourceKitLSP)
    }
}
