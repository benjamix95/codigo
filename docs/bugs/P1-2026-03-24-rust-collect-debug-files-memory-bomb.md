# P1 — collect_debug_files legge ogni file nel workspace in memoria

## Bug Fix Record
- Categoria: B - Importante
- Bug: `collect_debug_files` in `debug_tools.rs:1176` legge OGNI file nel workspace (inclusi binari, `.git/`, `node_modules/`, build artifacts) per verificare se contiene marker di debug.
- Sintomo: Memory spike enorme e performance catastrofiche su workspace grandi. Potenziale OOM.
- Impatto: Server MCP bloccato o crashato durante `debug_clean` senza path specifico.
- Gravità: P1
- Strategia di fix minimo: Filtrare per estensione file (solo sorgenti), escludere directory note (`.git`, `node_modules`, `build`, `target`), usare `grep`/`rg` al posto di lettura completa in memoria.
- Commit previsto: `fix(mcp-rust): filter debug file collection to source files only`
