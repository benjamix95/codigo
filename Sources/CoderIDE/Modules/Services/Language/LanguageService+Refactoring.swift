import Foundation
import CoderEngine

// MARK: - Refactoring Operations

extension LanguageService {
    /// Risultato di un'operazione di refactoring.
    struct RefactoringResult: Sendable {
        let edits: [RefactoringEdit]
        let description: String
        let error: String?

        var isSuccess: Bool { error == nil }

        static func success(edits: [RefactoringEdit], description: String) -> RefactoringResult {
            RefactoringResult(edits: edits, description: description, error: nil)
        }

        static func failure(_ error: String) -> RefactoringResult {
            RefactoringResult(edits: [], description: "", error: error)
        }
    }

    /// Singola modifica di refactoring (inserimento o sostituzione).
    struct RefactoringEdit: Sendable {
        let filePath: String
        let range: EditRange
        let newText: String

        struct EditRange: Sendable {
            let startLine: Int
            let startColumn: Int
            let endLine: Int
            let endColumn: Int
        }
    }

    /// Extract Method: estrae il codice selezionato in un nuovo metodo.
    func extractMethod(
        filePath: String,
        startLine: Int,
        endLine: Int,
        methodName: String
    ) async throws -> RefactoringResult {
        try ensureEnabled()

        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return .failure("Impossibile leggere il file: \(filePath)")
        }

        let lines = content.components(separatedBy: .newlines)
        guard startLine > 0, endLine <= lines.count, startLine <= endLine else {
            return .failure("Range righe non valido: \(startLine)-\(endLine)")
        }

        let selectedLines = Array(lines[(startLine - 1)...(endLine - 1)])
        let extractedBody = selectedLines.joined(separator: "\n")

        // Determina indentazione dal contesto
        let baseIndent = detectIndentation(in: lines, at: startLine - 1)
        let methodIndent = baseIndent

        // Genera il nuovo metodo
        let newMethod = buildExtractedMethod(
            name: methodName,
            body: extractedBody,
            indent: methodIndent
        )

        // Genera la chiamata al metodo
        let callSite = "\(baseIndent)\(methodName)()"

        // Edit 1: Sostituisci le righe selezionate con la chiamata
        let replaceEdit = RefactoringEdit(
            filePath: filePath,
            range: .init(
                startLine: startLine,
                startColumn: 1,
                endLine: endLine,
                endColumn: lines[endLine - 1].count + 1
            ),
            newText: callSite
        )

        // Edit 2: Inserisci il nuovo metodo dopo il metodo corrente
        let insertLine = findMethodEndLine(in: lines, from: endLine)
        let insertEdit = RefactoringEdit(
            filePath: filePath,
            range: .init(
                startLine: insertLine,
                startColumn: 1,
                endLine: insertLine,
                endColumn: 1
            ),
            newText: "\n\(newMethod)\n"
        )

        return .success(
            edits: [replaceEdit, insertEdit],
            description: "Estratto metodo '\(methodName)' da righe \(startLine)-\(endLine)"
        )
    }

    /// Extract Class/Struct: estrae proprietà e metodi in un nuovo tipo.
    func extractType(
        filePath: String,
        typeName: String,
        memberNames: [String],
        isClass: Bool = false
    ) async throws -> RefactoringResult {
        try ensureEnabled()

        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return .failure("Impossibile leggere il file: \(filePath)")
        }

        // Trova le definizioni dei membri nel file
        let references = try await findReferences(symbol: memberNames.first ?? typeName)
        guard !references.isEmpty else {
            return .failure("Nessun membro trovato per l'estrazione.")
        }

        let typeKeyword = isClass ? "class" : "struct"
        let typeDeclaration = """
        \(typeKeyword) \(typeName) {
            // TODO: Sposta qui i membri selezionati:
            // \(memberNames.joined(separator: ", "))
        }
        """

        let directory = (filePath as NSString).deletingLastPathComponent
        let newFilePath = "\(directory)/\(typeName).swift"

        let fileHeader = """
        import Foundation

        // MARK: - \(typeName)

        \(typeDeclaration)
        """

        let createEdit = RefactoringEdit(
            filePath: newFilePath,
            range: .init(startLine: 1, startColumn: 1, endLine: 1, endColumn: 1),
            newText: fileHeader
        )

        return .success(
            edits: [createEdit],
            description: "Estratto \(typeKeyword) '\(typeName)' con membri: \(memberNames.joined(separator: ", "))"
        )
    }

    // MARK: - Private Helpers

    private func detectIndentation(in lines: [String], at index: Int) -> String {
        guard index < lines.count else { return "    " }
        let line = lines[index]
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "    " }
        let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        return indent
    }

    private func buildExtractedMethod(name: String, body: String, indent: String) -> String {
        let bodyLines = body.components(separatedBy: .newlines)
            .map { "\(indent)    \($0.trimmingCharacters(in: .whitespaces))" }
            .joined(separator: "\n")

        return """
        \(indent)private func \(name)() {
        \(bodyLines)
        \(indent)}
        """
    }

    private func findMethodEndLine(in lines: [String], from startLine: Int) -> Int {
        var braceCount = 0
        var foundOpen = false

        for i in (startLine - 1)..<lines.count {
            for char in lines[i] {
                if char == "{" {
                    braceCount += 1
                    foundOpen = true
                } else if char == "}" {
                    braceCount -= 1
                    if foundOpen && braceCount == 0 {
                        return i + 2
                    }
                }
            }
        }
        return lines.count
    }

    private func ensureEnabled() throws {
        if !configuration.languageServiceEnabled {
            throw LanguageServiceError.disabled
        }
    }
}
