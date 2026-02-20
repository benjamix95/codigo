import Foundation

/// Contesto del workspace inviato al Coder
public struct WorkspaceContext: Sendable {
    /// Path radice (primo path, per compatibilità e working dir CLI)
    public var workspacePath: URL {
        workspacePaths.first ?? URL(fileURLWithPath: "/tmp")
    }
    
    /// Tutti i path del contesto (workspace o ad-hoc)
    public let workspacePaths: [URL]
    
    /// true = workspace nominato, false = cartelle ad-hoc
    public let isNamedWorkspace: Bool
    
    /// Nome workspace quando isNamedWorkspace
    public let workspaceName: String?
    
    /// Path da escludere (relativi o assoluti)
    public let excludedPaths: [String]

    /// Se non nil, solo i path matching sono inclusi nel contesto (scoped per partizione)
    public let includedPaths: [String]?

    /// File attualmente aperti con contenuto
    public let openFiles: [OpenFile]
    
    /// Selezione/cursore nel file attivo
    public let activeSelection: String?
    
    /// Path del file attivo
    public let activeFilePath: String?

    /// Root attiva in workspace multi-cartella (preferenza risoluzione file)
    public let activeRootPath: String?
    
    public init(
        workspacePaths: [URL],
        isNamedWorkspace: Bool = false,
        workspaceName: String? = nil,
        excludedPaths: [String] = [],
        includedPaths: [String]? = nil,
        openFiles: [OpenFile] = [],
        activeSelection: String? = nil,
        activeFilePath: String? = nil,
        activeRootPath: String? = nil
    ) {
        self.workspacePaths = workspacePaths.isEmpty ? [URL(fileURLWithPath: "/tmp")] : workspacePaths
        self.isNamedWorkspace = isNamedWorkspace
        self.workspaceName = workspaceName
        self.excludedPaths = excludedPaths
        self.includedPaths = includedPaths
        self.openFiles = openFiles
        self.activeSelection = activeSelection
        self.activeFilePath = activeFilePath
        self.activeRootPath = activeRootPath
    }
    
    /// Inizializzatore legacy (singolo path)
    public init(
        workspacePath: URL,
        excludedPaths: [String] = [],
        includedPaths: [String]? = nil,
        openFiles: [OpenFile] = [],
        activeSelection: String? = nil,
        activeFilePath: String? = nil,
        activeRootPath: String? = nil
    ) {
        self.workspacePaths = [workspacePath]
        self.isNamedWorkspace = false
        self.workspaceName = nil
        self.excludedPaths = excludedPaths
        self.includedPaths = includedPaths
        self.openFiles = openFiles
        self.activeSelection = activeSelection
        self.activeFilePath = activeFilePath
        self.activeRootPath = activeRootPath
    }

    
    /// Costruisce il prompt di contesto da inviare all'LLM
    public func contextPrompt() -> String {
        var parts: [String] = []
        
        if isNamedWorkspace, let name = workspaceName {
            parts.append("\n**Workspace:** \(name)")
            parts.append("\n**Path:** \(workspacePaths.map { $0.path }.joined(separator: ", "))")
        } else if !workspacePaths.isEmpty {
            parts.append("\n**Cartelle progetto:** \(workspacePaths.map { $0.path }.joined(separator: ", "))")
        }
        
        if !excludedPaths.isEmpty {
            parts.append("\n**Esclusi:** \(excludedPaths.joined(separator: ", "))")
        }
        if let included = includedPaths, !included.isEmpty {
            parts.append("\n**Scope partizione:** \(included.count) file (\(included.prefix(5).joined(separator: ", "))\(included.count > 5 ? "..." : ""))")
        }
        
        for path in workspacePaths.prefix(1) {
            let rootFiles = WorkspaceScanner.listRootFiles(workspacePath: path, excludedPaths: excludedPaths)
            if !rootFiles.isEmpty {
                parts.append("\n**File nella root:** \(rootFiles.joined(separator: ", "))")
            }
        }
        
        if let activePath = activeFilePath {
            parts.append("\n**File attivo:** \(activePath)")
        }
        if let activeRootPath {
            parts.append("\n**Root attiva:** \(activeRootPath)")
        }
        
        let filesToShow: [OpenFile]
        if let included = includedPaths, !included.isEmpty {
            let inclSet = Set(included)
            filesToShow = openFiles.filter { inclSet.contains($0.path) }
        } else {
            filesToShow = openFiles
        }
        if !filesToShow.isEmpty {
            parts.append("\n## File aperti")
            for file in filesToShow {
                parts.append("\n### \(file.path)")
                parts.append("```")
                parts.append(file.content)
                parts.append("```")
            }
        }
        
        if let selection = activeSelection, !selection.isEmpty {
            parts.append("\n## Selezione attiva")
            parts.append("```")
            parts.append(selection)
            parts.append("```")
        }

        let rulesBlock = CoderRulesFile.rulesPrompt(workspacePath: workspacePaths.first?.path)
        if !rulesBlock.isEmpty {
            parts.append("\n\(rulesBlock)")
        }
        
        if parts.isEmpty && activeFilePath == nil {
            return ""
        }
        return "\n\n" + parts.joined(separator: "\n")
    }
}

/// File aperto nell'editor
public struct OpenFile: Sendable {
    public let path: String
    public let content: String
    
    public init(path: String, content: String) {
        self.path = path
        self.content = content
    }
}
