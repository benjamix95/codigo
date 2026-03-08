import Foundation
import os

// MARK: - CodebaseIndexTools

/// Integrates CodebaseIndex with MCP/UnifiedToolRuntime.
/// Exposes codebase index operations as LLM-invokable tools.
public actor CodebaseIndexTools {
    static let logger = Logger(subsystem: "com.codigo.CoderEngine", category: "CodebaseIndexTools")

    let index: CodebaseIndex

    public init(index: CodebaseIndex) {
        self.index = index
    }

    // MARK: - Tool Definitions (for LLM prompt injection)

    /// Returns the description of index tools for the LLM prompt.
    public static var toolDefinitionsPrompt: String {
        """
        ## Codebase Index Tools

        You have access to codebase-index powered tools. Use CoderIDE markers to invoke them:

        ### codebase_search
        Search symbols, types, and functions using the structured index.
        Much faster and more precise than grep for finding definitions.
        [CODERIDE:tool_call|id=<uuid>|name=codebase_search|query=<search_query>|kind=<class|struct|enum|protocol|function|method|property|test|all>|filePattern=<optional_glob>]

        ### find_symbol
        Find exact symbol definitions (class, function, struct, protocol).
        [CODERIDE:tool_call|id=<uuid>|name=find_symbol|query=<symbol_name>|kind=<optional_kind>]

        ### list_symbols
        List all symbols in a specific file (file outline).
        [CODERIDE:tool_call|id=<uuid>|name=list_symbols|path=<relative_file_path>]

        ### find_references
        Find all references to a symbol in the codebase (definitions + usages).
        [CODERIDE:tool_call|id=<uuid>|name=find_references|query=<symbol_name>]

        ### project_structure
        Show the project tree structure.
        [CODERIDE:tool_call|id=<uuid>|name=project_structure|maxDepth=<2|3|4>]

        ### file_outline
        Get a structured file outline (symbols with line numbers).
        [CODERIDE:tool_call|id=<uuid>|name=file_outline|path=<relative_file_path>]

        ### find_files
        Find files by name with fuzzy matching.
        [CODERIDE:tool_call|id=<uuid>|name=find_files|query=<filename_query>|extension=<optional_ext>]

        ### codebase_stats
        Codebase statistics: files, languages, sizes, symbols.
        [CODERIDE:tool_call|id=<uuid>|name=codebase_stats]

        ### dependency_graph
        Show a file's dependencies (imports) and reverse imports.
        [CODERIDE:tool_call|id=<uuid>|name=dependency_graph|path=<relative_file_path>]

        ### list_types
        List all types (class, struct, enum, protocol) in the codebase.
        [CODERIDE:tool_call|id=<uuid>|name=list_types]

        ### list_tests
        List all tests in the codebase.
        [CODERIDE:tool_call|id=<uuid>|name=list_tests]

        ### index_status
        Show codebase index status.
        [CODERIDE:tool_call|id=<uuid>|name=index_status]

        ### reindex
        Force workspace reindexing (incremental if already indexed).
        [CODERIDE:tool_call|id=<uuid>|name=reindex]
        """
    }

    /// Tool names handled by the index.
    public static let handledToolNames: Set<String> = [
        "codebase_search",
        "find_symbol",
        "list_symbols",
        "find_references",
        "project_structure",
        "file_outline",
        "find_files",
        "codebase_stats",
        "dependency_graph",
        "list_types",
        "list_tests",
        "index_status",
        "reindex",
    ]

    /// Returns whether a tool name is handled by the index.
    public static func handles(toolName: String) -> Bool {
        handledToolNames.contains(toolName)
    }
}
