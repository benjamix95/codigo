# P1 — Schema types tutti "string" e schema mancanti per review/security/bughunter tools

## Bug Fix Record
- Categoria: B - Importante
- Bug: Due problemi in `tool_schema.rs`:
  1. Tutte le proprietà degli schema sono tipate come `"string"` — proprietà numeriche (`start_line`, `confidence`, `timeout_ms`) e booleane (`dry_run`, `case_sensitive`) non hanno il tipo corretto.
  2. I tool `coderide_review_*`, `coderide_security_*`, `coderide_bughunter_*` e `coderide_audit_*` ricevono schema vuoto (fallback `object_schema(&[], &[])`).
- Sintomo: L'LLM chiamante non ha guida sui tipi reali dei parametri. Può inviare stringhe dove servono numeri, causando errori di parsing o comportamenti inaspettati.
- Impatto: Degradazione qualità dell'interazione LLM → tool, errori di tipo runtime.
- Gravità: P1
- Strategia di fix minimo:
  1. Aggiungere funzioni helper `integer_property`, `boolean_property` e usarle dove appropriato.
  2. Aggiungere schema specifici per review, security, bughunter e audit tools.
- Commit previsto: `fix(mcp-rust): add correct types and missing schemas for all tools`
