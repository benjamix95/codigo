import Foundation

/// Workspace context passed to the coder runtime.
public struct WorkspaceContext: Sendable {
    /// Root path (first path, used for compatibility and CLI working directory).
    public var workspacePath: URL {
        workspacePaths.first ?? URL(fileURLWithPath: "/tmp")
    }
    
    /// All paths in the current context (workspace or ad-hoc folders).
    public let workspacePaths: [URL]
    
    /// true = named workspace, false = ad-hoc folders.
    public let isNamedWorkspace: Bool
    
    /// Workspace name when `isNamedWorkspace` is true.
    public let workspaceName: String?
    
    /// Paths to exclude (relative or absolute).
    public let excludedPaths: [String]

    /// If non-nil, only matching paths are included in context (partition-scoped).
    public let includedPaths: [String]?

    /// Currently open files with content.
    public let openFiles: [OpenFile]
    
    /// Current selection/cursor snippet in active file.
    public let activeSelection: String?
    
    /// Active file path.
    public let activeFilePath: String?

    /// Active root for multi-folder workspaces (file resolution preference).
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
    
    /// Legacy initializer (single path).
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

    
    /// Builds the context prompt to send to the LLM.
    public func contextPrompt() -> String {
        var parts: [String] = []
        
        if isNamedWorkspace, let name = workspaceName {
            parts.append("\n**Workspace:** \(name)")
            parts.append("\n**Path:** \(workspacePaths.map { $0.path }.joined(separator: ", "))")
        } else if !workspacePaths.isEmpty {
            parts.append("\n**Project folders:** \(workspacePaths.map { $0.path }.joined(separator: ", "))")
        }
        
        if !excludedPaths.isEmpty {
            parts.append("\n**Excluded:** \(excludedPaths.joined(separator: ", "))")
        }
        if let included = includedPaths, !included.isEmpty {
            parts.append("\n**Partition scope:** \(included.count) files (\(included.prefix(5).joined(separator: ", "))\(included.count > 5 ? "..." : ""))")
        }
        
        for path in workspacePaths.prefix(1) {
            let rootFiles = WorkspaceScanner.listRootFiles(workspacePath: path, excludedPaths: excludedPaths)
            if !rootFiles.isEmpty {
                parts.append("\n**Files in root:** \(rootFiles.joined(separator: ", "))")
            }
        }
        
        if let activePath = activeFilePath {
            parts.append("\n**Active file:** \(activePath)")
        }
        if let activeRootPath {
            parts.append("\n**Active root:** \(activeRootPath)")
        }
        
        let filesToShow: [OpenFile]
        if let included = includedPaths, !included.isEmpty {
            let inclSet = Set(included)
            filesToShow = openFiles.filter { inclSet.contains($0.path) }
        } else {
            filesToShow = openFiles
        }
        if !filesToShow.isEmpty {
            parts.append("\n## Open files")
            for file in filesToShow {
                parts.append("\n### \(file.path)")
                parts.append("```")
                parts.append(file.content)
                parts.append("```")
            }
        }
        
        if let selection = activeSelection, !selection.isEmpty {
            parts.append("\n## Active selection")
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

/// File currently open in the editor.
public struct OpenFile: Sendable {
    public let path: String
    public let content: String
    
    public init(path: String, content: String) {
        self.path = path
        self.content = content
    }
}
