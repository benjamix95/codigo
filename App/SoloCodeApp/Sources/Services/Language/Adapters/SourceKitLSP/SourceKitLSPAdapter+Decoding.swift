import Foundation

extension SourceKitLSPAdapter {
    func decodeLocationArray(from data: Data, operation: String) throws -> [LSPLocation] {
        if isNullPayload(data) {
            return []
        }
        do {
            return try decoder.decode([LSPLocation].self, from: data)
        } catch {
            throw LanguageServiceError.unsupported("Unsupported SourceKit-LSP \(operation) payload")
        }
    }

    func decodeDefinitionLocations(from data: Data) throws -> [LSPLocation] {
        if let single = try? decoder.decode(LSPLocation.self, from: data) {
            return [single]
        }
        if let many = try? decoder.decode([LSPLocation].self, from: data) {
            return many
        }
        if let links = try? decoder.decode([LSPLocationLink].self, from: data) {
            return links.map { LSPLocation(uri: $0.targetUri, range: $0.targetSelectionRange) }
        }
        throw LanguageServiceError.unsupported("Unsupported SourceKit-LSP definition payload")
    }

    func workspaceEditLocations(_ edit: LSPWorkspaceEdit, symbolName: String) -> [LanguageLocation] {
        var locations: Set<LanguageLocation> = []

        for (uri, edits) in edit.changes ?? [:] {
            for textEdit in edits {
                locations.insert(makeLocation(uri: uri, range: textEdit.range, symbolName: symbolName))
            }
        }

        for change in edit.documentChanges ?? [] {
            guard let uri = change.textDocument?.uri else { continue }
            for textEdit in change.edits ?? [] {
                locations.insert(makeLocation(uri: uri, range: textEdit.range, symbolName: symbolName))
            }
        }

        return Array(locations)
    }

    func makeLocation(uri: String, range: LSPRange, symbolName: String) -> LanguageLocation {
        LanguageLocation(
            filePath: path(fromURI: uri) ?? uri,
            line: range.start.line + 1,
            column: range.start.character + 1,
            symbolName: symbolName,
            source: source
        )
    }
}
