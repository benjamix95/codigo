import Foundation

// MARK: - Project Template Service

/// Servizio per la creazione di progetti da template predefiniti.
actor ProjectTemplateService {
    /// Template per la creazione di un progetto.
    struct ProjectTemplate: Identifiable, Sendable {
        let id: String
        let name: String
        let description: String
        let category: TemplateCategory
        let files: [TemplateFile]
        let dependencies: [String]

        struct TemplateFile: Sendable {
            let relativePath: String
            let content: String
        }
    }

    /// Categoria di template.
    enum TemplateCategory: String, Sendable, CaseIterable {
        case swiftPackage = "Swift Package"
        case iosApp = "iOS App"
        case macosApp = "macOS App"
        case commandLine = "Command Line"
        case library = "Library"
    }

    /// Risultato della creazione di un progetto.
    struct CreationResult: Sendable {
        let projectPath: String
        let templateId: String
        let filesCreated: Int
        let error: String?

        var isSuccess: Bool { error == nil }
    }

    private let registry: TemplateRegistry

    init(registry: TemplateRegistry = TemplateRegistry()) {
        self.registry = registry
    }

    // MARK: - Creazione

    /// Crea un progetto da un template nella directory specificata.
    func createProject(
        templateId: String,
        projectName: String,
        destinationPath: String
    ) async -> CreationResult {
        guard let template = await registry.template(for: templateId) else {
            return CreationResult(
                projectPath: destinationPath,
                templateId: templateId,
                filesCreated: 0,
                error: "Template '\(templateId)' non trovato"
            )
        }

        let projectPath = (destinationPath as NSString).appendingPathComponent(projectName)
        let fm = FileManager.default

        // Crea directory progetto
        do {
            try fm.createDirectory(atPath: projectPath, withIntermediateDirectories: true)
        } catch {
            return CreationResult(
                projectPath: projectPath,
                templateId: templateId,
                filesCreated: 0,
                error: "Impossibile creare directory: \(error.localizedDescription)"
            )
        }

        // Genera i file dal template
        var filesCreated = 0
        for file in template.files {
            let content = file.content
                .replacingOccurrences(of: "{{PROJECT_NAME}}", with: projectName)
                .replacingOccurrences(of: "{{DATE}}", with: dateString())

            guard let safeRelativePath = safeRelativePath(file.relativePath) else {
                return CreationResult(
                    projectPath: projectPath,
                    templateId: templateId,
                    filesCreated: filesCreated,
                    error: "Percorso file non valido: \(file.relativePath)"
                )
            }

            let filePath = (projectPath as NSString).appendingPathComponent(safeRelativePath)
            let fileDir = (filePath as NSString).deletingLastPathComponent

            do {
                try fm.createDirectory(atPath: fileDir, withIntermediateDirectories: true)
                try content.write(toFile: filePath, atomically: true, encoding: .utf8)
                filesCreated += 1
            } catch {
                return CreationResult(
                    projectPath: projectPath,
                    templateId: templateId,
                    filesCreated: filesCreated,
                    error: "Errore scrittura \(file.relativePath): \(error.localizedDescription)"
                )
            }
        }

        // Inizializza git
        await initGit(at: projectPath)

        return CreationResult(
            projectPath: projectPath,
            templateId: templateId,
            filesCreated: filesCreated,
            error: nil
        )
    }

    /// Restituisce i template disponibili per categoria.
    func templates(category: TemplateCategory? = nil) async -> [ProjectTemplate] {
        await registry.allTemplates(category: category)
    }

    // MARK: - Privato

    private func initGit(at path: String) async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["init"]
        process.currentDirectoryURL = URL(fileURLWithPath: path)
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }

    private func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func safeRelativePath(_ path: String) -> String? {
        guard !path.isEmpty else { return nil }
        guard !(path as NSString).isAbsolutePath else { return nil }

        let normalized = (path as NSString).standardizingPath
        guard !normalized.isEmpty, normalized != "." else { return nil }
        guard !normalized.hasPrefix("../"), normalized != ".." else { return nil }

        return normalized
    }
}
