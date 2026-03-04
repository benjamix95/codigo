import Foundation

actor SourceKitLSPAdapter: LanguageServiceAdapter {
    nonisolated let source: LanguageServiceSource = .sourceKitLSP
    let executablePath: String
    let executor: SourceKitLSPRequestExecuting
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    init(executablePath: String, executor: SourceKitLSPRequestExecuting = SourceKitLSPCLIExecutor()) {
        self.executablePath = executablePath
        self.executor = executor
    }

    func goToDefinition(symbol: String, fileHint: String?) async throws -> [LanguageLocation] {
        let context = try await resolveRequestContext(symbol: symbol, fileHint: fileHint)
        let params = LSPTextDocumentPositionParams(
            textDocument: LSPTextDocumentIdentifier(uri: context.uri),
            position: context.position
        )
        let request = try makeRequest(method: "textDocument/definition", params: params, context: context)
        let data = try await run(request: request, operation: "go-to-definition")
        let locations = try decodeDefinitionLocations(from: data)
        return locations.map { location in
            LanguageLocation(
                filePath: path(fromURI: location.uri) ?? location.uri,
                line: location.range.start.line + 1,
                column: location.range.start.character + 1,
                symbolName: symbol,
                source: source
            )
        }
    }

    func hover(symbol: String, fileHint: String?) async throws -> LanguageHoverResult? {
        let context = try await resolveRequestContext(symbol: symbol, fileHint: fileHint)
        let params = LSPTextDocumentPositionParams(
            textDocument: LSPTextDocumentIdentifier(uri: context.uri),
            position: context.position
        )
        let request = try makeRequest(method: "textDocument/hover", params: params, context: context)
        let data = try await run(request: request, operation: "hover")
        if isNullPayload(data) {
            return nil
        }
        let payload = try decoder.decode(LSPHoverResponse.self, from: data)
        let text = payload.contents.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return LanguageHoverResult(contents: text, source: source)
    }

    func findReferences(symbol: String, limit: Int) async throws -> [LanguageLocation] {
        let anchors = try await fetchWorkspaceSymbolAnchors(symbol: symbol, limit: min(max(1, limit), 20))
        guard !anchors.isEmpty else { return [] }

        var unique = Set<LanguageLocation>()
        for anchor in anchors {
            let params = LSPReferenceParams(
                textDocument: LSPTextDocumentIdentifier(uri: anchor.uri),
                position: anchor.range.start,
                context: LSPReferenceContext(includeDeclaration: true)
            )
            let request = try makeRequest(method: "textDocument/references", params: params, context: anchor)
            let data = try await run(request: request, operation: "find-references")
            let refs = try decodeLocationArray(from: data, operation: "find-references")
            for ref in refs {
                unique.insert(
                    LanguageLocation(
                        filePath: path(fromURI: ref.uri) ?? ref.uri,
                        line: ref.range.start.line + 1,
                        column: ref.range.start.character + 1,
                        symbolName: symbol,
                        source: source
                    )
                )
                if unique.count >= limit {
                    return Array(unique.prefix(limit))
                }
            }
        }
        return Array(unique.prefix(limit))
    }

    func rename(oldName: String, newName: String) async throws -> LanguageRenamePlan {
        let anchor = try await fetchWorkspaceSymbolAnchors(symbol: oldName, limit: 1).first
        guard let anchor else {
            return LanguageRenamePlan(oldName: oldName, newName: newName, references: [], source: source)
        }

        let params = LSPRenameParams(
            textDocument: LSPTextDocumentIdentifier(uri: anchor.uri),
            position: anchor.range.start,
            newName: newName
        )
        let request = try makeRequest(method: "textDocument/rename", params: params, context: anchor)
        let data = try await run(request: request, operation: "rename")
        if isNullPayload(data) {
            return LanguageRenamePlan(oldName: oldName, newName: newName, references: [], source: source)
        }
        let edit = try decoder.decode(LSPWorkspaceEdit.self, from: data)
        let refs = workspaceEditLocations(edit, symbolName: oldName)
        return LanguageRenamePlan(oldName: oldName, newName: newName, references: refs, source: source)
    }

    func run(request: SourceKitLSPRequest, operation: String) async throws -> Data {
        do {
            return try await executor.execute(executablePath: executablePath, request: request)
        } catch let error as LanguageServiceError {
            throw error
        } catch {
            throw LanguageServiceError.unsupported("SourceKit-LSP \(operation) failed: \(error.localizedDescription)")
        }
    }

    func makeRequest<P: Encodable>(method: String, params: P, context: LSPContext) throws -> SourceKitLSPRequest {
        SourceKitLSPRequest(
            method: method,
            paramsJSON: try encoder.encode(params),
            workspaceRootPath: context.workspaceRootPath,
            openDocuments: [SourceKitOpenDocument(filePath: context.filePath, languageId: context.languageId, text: context.fileText)]
        )
    }
}
