import Foundation

enum PromptToolsPolicy {
    static let toolUsage = """
    Policy tools:
    - Usa tool quando servono evidenze o modifiche reali.
    - Dopo ogni tool batch, integra i risultati e continua verso la soluzione.
    - Non ciclare sugli stessi tool senza nuova informazione.
    - Se un tool fallisce, spiega causa probabile e fallback applicato.
    - Rispetta budget round/tool e limita retry a errori transienti.
    - Preferisci tool strutturati (`read_range`, `list_dir`, `git_diff`, `search_symbols`,
      `run_tests`, `build_project`, `read_json`, `write_json`, `workspace_stats`,
      `dependency_audit`, `tail_log`, `mcp_list_tools`, `mcp_call`, `mcp_health`).
    """
}
