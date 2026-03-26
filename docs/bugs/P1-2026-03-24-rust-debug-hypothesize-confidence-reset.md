# P1 — debug_hypothesize update resetta confidence a 50 e cancella root_cause_type

## Bug Fix Record
- Categoria: B - Importante
- Bug: In `debug_tools.rs`, l'azione `update` di `debug_hypothesize` ha due problemi:
  1. Se l'utente aggiorna solo lo status senza specificare confidence, il valore viene resettato a 50 (default di `unwrap_or(50)`).
  2. La condizione logica per `root_cause_type` è invertita — se il parametro non è fornito, il campo viene svuotato.
- Sintomo: Aggiornando lo status di un'ipotesi, confidence e root_cause_type vengono silenziosamente persi.
- Impatto: Perdita di metadati sulle ipotesi di debug.
- Gravità: P1
- Scope consentito: `debug_tools.rs` linee 359, 427, 431-433.
- Strategia di fix minimo: Usare pattern `if let Some(new_confidence) = args.get("confidence")` per aggiornare solo se il campo è esplicitamente fornito. Stessa logica per `root_cause_type`.
- Commit previsto: `fix(mcp-rust): preserve hypothesis fields on partial update`
