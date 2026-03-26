# ARCH — Timeout inconsistenti tra CLI runner e inline execution

## Analisi architetturale

### Descrizione
I subagent possono essere eseguiti in due modi:
1. **CLI runner** (`SubagentCLIRunner`): lancia un processo esterno (codex/claude/gemini CLI)
2. **Inline** (`ToolEnabledLLMProvider+SubagentExecution`): esegue il subagent nello stesso processo

### Problema
I timeout sono completamente diversi tra i due path:

| Ruolo | CLI timeout | Inline timeout |
|-------|-------------|----------------|
| explorer | 95s | 300s (hardcoded) |
| reviewer | 95s | 300s (hardcoded) |
| bugHunter | **3600s** | **300s** (hardcoded) |
| coder | 110s | 300s (hardcoded) |
| debugger | 110s | 300s (hardcoded) |

Il bugHunter inline viene ucciso a 5 minuti invece che a 60.

### Raccomandazione
Unificare la configurazione dei timeout in un unico punto (`SubagentRole` o `SubagentCLIConfig`) e usarlo sia per CLI che per inline execution.
