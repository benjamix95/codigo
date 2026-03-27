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

    /// When true, `contextPrompt()` returns "" — used for lightweight tasks (e.g. prompt optimization)
    /// that don't need workspace context, rules, or policy.
    public let skipContextEnrichment: Bool

    /// When set, base providers use this as the ONLY system prompt (no taskCompletionStrict)
    /// and disable tools. Used for prompt optimization so the model rewrites text instead of executing.
    public let systemPromptOverride: String?

    /// When true and `systemPromptOverride` is nil, use `SystemPrompts.debugSessionAgentBase` instead of `taskCompletionStrict`.
    public let preferDebuggerPromptProfile: Bool

    /// Source of truth for instruction policy text/hash for this context.
    public let instructionPolicyBundle: InstructionPolicyBundle

    public init(
        workspacePaths: [URL],
        isNamedWorkspace: Bool = false,
        workspaceName: String? = nil,
        excludedPaths: [String] = [],
        includedPaths: [String]? = nil,
        openFiles: [OpenFile] = [],
        activeSelection: String? = nil,
        activeFilePath: String? = nil,
        activeRootPath: String? = nil,
        skipContextEnrichment: Bool = false,
        systemPromptOverride: String? = nil,
        preferDebuggerPromptProfile: Bool = false,
        instructionPolicyBundle: InstructionPolicyBundle? = nil
    ) {
        let resolvedWorkspacePaths = workspacePaths.isEmpty ? [URL(fileURLWithPath: "/tmp")] : workspacePaths
        let resolvedPolicyBundle = instructionPolicyBundle
            ?? Self.resolveInstructionPolicyBundle(
                workspacePaths: resolvedWorkspacePaths,
                skipContextEnrichment: skipContextEnrichment
            )
        self.workspacePaths = resolvedWorkspacePaths
        self.isNamedWorkspace = isNamedWorkspace
        self.workspaceName = workspaceName
        self.excludedPaths = excludedPaths
        self.includedPaths = includedPaths
        self.openFiles = openFiles
        self.activeSelection = activeSelection
        self.activeFilePath = activeFilePath
        self.activeRootPath = activeRootPath
        self.skipContextEnrichment = skipContextEnrichment
        self.systemPromptOverride = systemPromptOverride
        self.preferDebuggerPromptProfile = preferDebuggerPromptProfile
        self.instructionPolicyBundle = resolvedPolicyBundle
    }
    
    /// Legacy initializer (single path).
    public init(
        workspacePath: URL,
        excludedPaths: [String] = [],
        includedPaths: [String]? = nil,
        openFiles: [OpenFile] = [],
        activeSelection: String? = nil,
        activeFilePath: String? = nil,
        activeRootPath: String? = nil,
        skipContextEnrichment: Bool = false,
        systemPromptOverride: String? = nil,
        preferDebuggerPromptProfile: Bool = false,
        instructionPolicyBundle: InstructionPolicyBundle? = nil
    ) {
        let resolvedWorkspacePaths = [workspacePath]
        let resolvedPolicyBundle = instructionPolicyBundle
            ?? Self.resolveInstructionPolicyBundle(
                workspacePaths: resolvedWorkspacePaths,
                skipContextEnrichment: skipContextEnrichment
            )
        self.workspacePaths = resolvedWorkspacePaths
        self.isNamedWorkspace = false
        self.workspaceName = nil
        self.excludedPaths = excludedPaths
        self.includedPaths = includedPaths
        self.openFiles = openFiles
        self.activeSelection = activeSelection
        self.activeFilePath = activeFilePath
        self.activeRootPath = activeRootPath
        self.skipContextEnrichment = skipContextEnrichment
        self.systemPromptOverride = systemPromptOverride
        self.preferDebuggerPromptProfile = preferDebuggerPromptProfile
        self.instructionPolicyBundle = resolvedPolicyBundle
    }

    /// Context for prompt optimization: uses only the optimizer system instruction,
    /// no taskCompletionStrict, no tools — so the model rewrites the prompt instead of executing it.
    public static func forPromptOptimizer(systemInstruction: String) -> WorkspaceContext {
        WorkspaceContext(
            workspacePaths: [URL(fileURLWithPath: "/tmp")],
            openFiles: [],
            skipContextEnrichment: true,
            systemPromptOverride: systemInstruction
        )
    }

    /// Minimal context for lightweight tasks (prompt optimization, etc.).
    /// `contextPrompt()` returns "" so no workspace metadata, rules, or policy are added.
    public static func minimal() -> WorkspaceContext {
        WorkspaceContext(
            workspacePaths: [URL(fileURLWithPath: "/tmp")],
            openFiles: [],
            skipContextEnrichment: true
        )
    }

    
    /// Builds the context prompt to send to the LLM.
    public func contextPrompt() -> String {
        if skipContextEnrichment { return "" }
        var parts: [String] = []
        
        if isNamedWorkspace, let name = workspaceName {
            parts.append("\n**Workspace:** \(name)")
            parts.append("\n**Path:** \(workspacePaths.map { $0.path }.joined(separator: ", "))")
        } else if !workspacePaths.isEmpty {
            parts.append("\n**Project folders:** \(workspacePaths.map { $0.path }.joined(separator: ", "))")
        }
        if let primaryPath = workspacePaths.first {
            parts.append("\n**Working directory (cwd for all tools):** \(primaryPath.path)")
            parts.append("All file paths should be relative to this directory. Do not search outside the workspace unless explicitly asked.")
        }
        
        if !excludedPaths.isEmpty {
            parts.append("\n**Excluded:** \(excludedPaths.joined(separator: ", "))")
        }
        if let included = includedPaths, !included.isEmpty {
            parts.append("\n**Partition scope:** \(included.count) files (\(included.prefix(5).joined(separator: ", "))\(included.count > 5 ? "..." : ""))")
        }
        
        for path in workspacePaths {
            let rootFiles = WorkspaceScanner.listRootFiles(workspacePath: path, excludedPaths: excludedPaths)
            if !rootFiles.isEmpty {
                let label = workspacePaths.count > 1
                    ? "\n**Files in root (\(path.lastPathComponent)):**"
                    : "\n**Files in root:**"
                parts.append("\(label) \(rootFiles.joined(separator: ", "))")
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

        let policyBlock = instructionPolicyBundle.policyText
        if !policyBlock.isEmpty {
            parts.append("\n\(policyBlock)")
        }
        
        if parts.isEmpty && activeFilePath == nil {
            return ""
        }
        return "\n\n" + parts.joined(separator: "\n")
    }

    private static func resolveInstructionPolicyBundle(
        workspacePaths: [URL],
        skipContextEnrichment: Bool
    ) -> InstructionPolicyBundle {
        guard !skipContextEnrichment else {
            return .empty
        }
        return InstructionPolicyBundle.load(workspacePaths: workspacePaths.map(\.path))
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
