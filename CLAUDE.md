# Istruzioni per agenti (repository SoloCode)

## Runtime senza MCP CoderIDE

Se l’elenco strumenti della sessione **non** include tool `coderide_*`, né i controlli tipati del panel debug (`activate_debug_mode`, `debug_set_phase`, `coderide_debug_*`, ecc.):

- È **previsto** in **Claude Code**, in **Cursor senza MCP CoderIDE** collegato, o in altri agent headless.
- **Non** trattarlo come un bug del repository o come “strumenti mancanti” da segnalare come blocco infrastrutturale.
- **Non** attendere quei tool: prosegui con lettura file, ricerca nel repo, comandi shell, test e modifiche dirette, usando solo ciò che è effettivamente invocabile.
- Il flusso **MCP-first** sul panel debug (fasi, `debug_session`, …) si applica quando il **server MCP CoderIDE è connesso** (tipicamente dalla chat integrata in SoloCode).

Per il resto, rispetta `AGENTS.md` nella home dell’utente se presente, e le convenzioni del progetto.
