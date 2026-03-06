import CoderEngine
import Foundation

@MainActor
final class EditorSymbolsStore: ObservableObject {
    @Published private(set) var outlineByPath: [String: [EditorSymbolItem]] = [:]
    @Published private(set) var references: [EditorNavigationTarget] = []

    func outline(for path: String) -> [EditorSymbolItem] {
        outlineByPath[path] ?? []
    }

    func loadOutline(for absolutePath: String, workspaceStore: WorkspaceStore) async {
        guard let relative = EditorPathResolver.relativePath(
            for: absolutePath,
            roots: workspaceStore.activeWorkspacePaths.map(\.path)
        ) else {
            outlineByPath[absolutePath] = []
            return
        }
        let symbols = await workspaceStore.codebaseIndex.symbolsInFile(relative)
        outlineByPath[absolutePath] = symbols.map {
            EditorSymbolItem(
                id: $0.id,
                name: $0.name,
                detail: $0.signature,
                line: $0.line,
                column: max(1, $0.column),
                iconName: $0.kind.sfSymbol
            )
        }
    }

    func hover(
        request: MonacoRequestContext,
        workspaceStore: WorkspaceStore
    ) async -> MonacoHoverPayload {
        do {
            let result = try await workspaceStore.languageService.hover(
                symbol: request.word,
                fileHint: request.path
            )
            return MonacoHoverPayload(contents: result?.contents)
        } catch {
            return MonacoHoverPayload(contents: nil)
        }
    }

    func definitions(
        request: MonacoRequestContext,
        workspaceStore: WorkspaceStore
    ) async -> MonacoDefinitionPayload {
        do {
            let items = try await workspaceStore.languageService.goToDefinition(
                symbol: request.word,
                fileHint: request.path
            )
            return MonacoDefinitionPayload(locations: items.map {
                .init(
                    filePath: $0.filePath,
                    line: $0.line,
                    column: max(1, $0.column ?? 1),
                    symbolName: $0.symbolName,
                    source: $0.source.rawValue
                )
            })
        } catch {
            return MonacoDefinitionPayload(locations: [])
        }
    }

    func loadReferences(
        request: MonacoRequestContext,
        workspaceStore: WorkspaceStore
    ) async -> MonacoDefinitionPayload {
        do {
            let items = try await workspaceStore.languageService.findReferences(symbol: request.word)
            let mapped = items.map {
                EditorNavigationTarget(
                    filePath: $0.filePath,
                    line: $0.line,
                    column: max(1, $0.column ?? 1),
                    symbolName: $0.symbolName,
                    source: $0.source.rawValue
                )
            }
            references = mapped
            return MonacoDefinitionPayload(locations: mapped.map {
                .init(
                    filePath: $0.filePath,
                    line: $0.line,
                    column: $0.column,
                    symbolName: $0.symbolName,
                    source: $0.source
                )
            })
        } catch {
            references = []
            return MonacoDefinitionPayload(locations: [])
        }
    }

    func rename(
        request: MonacoRequestContext,
        workspaceStore: WorkspaceStore
    ) async -> MonacoRenamePayload {
        guard let newName = request.newName, !newName.isEmpty else {
            return MonacoRenamePayload(edits: [])
        }
        do {
            let plan = try await workspaceStore.languageService.rename(
                oldName: request.word,
                newName: newName
            )
            return MonacoRenamePayload(
                edits: plan.references.compactMap {
                    let column = max(1, $0.column ?? inferColumn(for: $0, symbolName: request.word))
                    return MonacoRenamePayload.Edit(
                        filePath: $0.filePath,
                        line: $0.line,
                        column: column,
                        endColumn: column + max(1, request.word.count),
                        text: newName
                    )
                }
            )
        } catch {
            return MonacoRenamePayload(edits: [])
        }
    }

    private func inferColumn(for location: LanguageLocation, symbolName: String) -> Int {
        guard
            let content = try? String(contentsOfFile: location.filePath, encoding: .utf8),
            location.line > 0
        else { return 1 }
        let lines = content.components(separatedBy: .newlines)
        guard location.line - 1 < lines.count else { return 1 }
        let line = lines[location.line - 1]
        guard let range = line.range(of: symbolName) else { return 1 }
        return line.distance(from: line.startIndex, to: range.lowerBound) + 1
    }
}
