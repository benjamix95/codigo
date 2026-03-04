import Foundation

extension SourceKitLSPAdapter {
    func resolveRequestContext(symbol: String, fileHint: String?) async throws -> LSPContext {
        if let localContext = try resolveFileHintContext(symbol: symbol, fileHint: fileHint) {
            return localContext
        }
        if let workspaceContext = try await fetchWorkspaceSymbolAnchors(symbol: symbol, limit: 1).first {
            return workspaceContext
        }
        throw LanguageServiceError.unsupported("SourceKit-LSP cannot resolve symbol context for '\(symbol)'")
    }

    func fetchWorkspaceSymbolAnchors(symbol: String, limit: Int) async throws -> [LSPContext] {
        let request = SourceKitLSPRequest(
            method: "workspace/symbol",
            paramsJSON: try encoder.encode(LSPWorkspaceSymbolParams(query: symbol)),
            workspaceRootPath: FileManager.default.currentDirectoryPath,
            openDocuments: []
        )
        let data = try await run(request: request, operation: "workspace-symbol")
        let symbols: [LSPWorkspaceSymbolItem]
        if isNullPayload(data) {
            symbols = []
        } else {
            do {
                symbols = try decoder.decode([LSPWorkspaceSymbolItem].self, from: data)
            } catch {
                throw LanguageServiceError.unsupported("Unsupported SourceKit-LSP workspace-symbol payload")
            }
        }

        let exact = symbols.filter { $0.name == symbol }
        let candidates = exact.isEmpty ? symbols.filter { $0.name.localizedCaseInsensitiveContains(symbol) } : exact
        return candidates.prefix(limit).compactMap { item in
            guard let filePath = path(fromURI: item.location.uri) else { return nil }
            let text = (try? String(contentsOfFile: filePath, encoding: .utf8)) ?? ""
            return LSPContext(
                filePath: filePath,
                uri: item.location.uri,
                fileText: text,
                languageId: languageID(forPath: filePath),
                position: item.location.range.start,
                workspaceRootPath: URL(fileURLWithPath: filePath).deletingLastPathComponent().path,
                range: item.location.range
            )
        }
    }

    func resolveFileHintContext(symbol: String, fileHint: String?) throws -> LSPContext? {
        guard let rawFile = fileHint?.trimmingCharacters(in: .whitespacesAndNewlines), !rawFile.isEmpty else {
            return nil
        }

        let fileURL = URL(fileURLWithPath: rawFile)
        let text: String
        do {
            text = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            throw LanguageServiceError.unsupported("Cannot open file for SourceKit-LSP: \(rawFile)")
        }

        guard let position = symbolPosition(symbol: symbol, in: text) else {
            throw LanguageServiceError.unsupported("Symbol '\(symbol)' not found in fileHint: \(rawFile)")
        }

        return LSPContext(
            filePath: fileURL.path,
            uri: fileURL.absoluteString,
            fileText: text,
            languageId: languageID(forPath: fileURL.path),
            position: position,
            workspaceRootPath: fileURL.deletingLastPathComponent().path,
            range: LSPRange(start: position, end: position)
        )
    }

    func symbolPosition(symbol: String, in text: String) -> LSPPosition? {
        let nsText = text as NSString
        let range = nsText.range(of: symbol)
        guard range.location != NSNotFound else { return nil }

        let prefix = nsText.substring(to: range.location)
        let lines = prefix.components(separatedBy: "\n")
        let line = max(0, lines.count - 1)
        let column = ((lines.last ?? "") as NSString).length
        return LSPPosition(line: line, character: column)
    }

    func languageID(forPath path: String) -> String {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "swift":
            return "swift"
        case "m", "mm":
            return "objective-c"
        case "c", "h":
            return "c"
        case "cpp", "cc", "cxx", "hpp":
            return "cpp"
        default:
            return "plaintext"
        }
    }

    func path(fromURI uri: String) -> String? {
        guard let url = URL(string: uri), url.isFileURL else { return nil }
        return url.path
    }

    func isNullPayload(_ data: Data) -> Bool {
        String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "null"
    }
}

struct LSPContext: Sendable {
    let filePath: String
    let uri: String
    let fileText: String
    let languageId: String
    let position: LSPPosition
    let workspaceRootPath: String
    let range: LSPRange
}
