# P0 — ReviewPipelineRustCallbackResult silent decode failure

## Bug Fix Record

- **Categoria:** A — Critico
- **Bug:** `ReviewPipelineRustCallbackResult` usava il decoder auto-generato di Swift (`Codable`), che richiede la presenza di TUTTI i campi non-optional nel JSON. Le risposte Rust non includono campi assenti (es. `files`, `patches`), causando fallimento silenzioso della decodifica.
- **Sintomo:** I test `testRunAuditStageUsesRustReductionForCandidatesAndAuditSnapshot` falliscono con `candidates` vuoto, `promotedFindings` vuoto e `audit == nil`, nonostante il Rust dylib sia caricato correttamente e le audit tools producano findings validi.
- **Impatto:** Tutte le callback Rust del review pipeline (audit stage, task candidates, tests reduction, patch preparation) falliscono silenziosamente. L'intero pipeline di code review runtime è degradato: i risultati degli audit tool vengono scartati, nessun candidate viene promosso, e l'audit snapshot è sempre nil.
- **Gravità:** P0 — il review pipeline runtime è funzionalmente non operativo.
- **Steps to reproduce:**
  1. Eseguire `testRunAuditStageUsesRustReductionForCandidatesAndAuditSnapshot`
  2. Il test crea un workspace temporaneo con `Service.swift` contenente command injection
  3. Chiama `adapter.runAuditStage(files:sessionId:)`
  4. L'audit rileva la vulnerabilità, ma la decodifica della risposta Rust fallisce
- **Risultato attuale:** `result.candidates.isEmpty == true`, `result.promotedFindings.isEmpty == true`, `result.audit == nil`
- **Risultato atteso:** `result.candidates` non vuoto, `result.promotedFindings` non vuoto, `result.audit?.toolCoverage[securityDataflow] == true`
- **Causa probabile (confermata):** Il decoder auto-generato di `Codable` in Swift richiede che ogni proprietà non-optional sia presente nel JSON. Il Rust serializza solo i campi rilevanti per ciascun tipo di callback (es. `reduce_audit_stage` non include `files` e `patches`). Il `JSONDecoder` lancia un errore per chiavi mancanti, che `ReviewCoreBridge.call` cattura silenziosamente restituendo `nil`.
- **Scope consentito:** `ReviewPipelineRustModels.swift` — solo il tipo `ReviewPipelineRustCallbackResult`
- **Non-scope:** Logica Rust, altri modelli Swift, audit tools
- **Moduli confinanti da verificare:** Tutti i consumer di `ReviewPipelineRustCallbackResult` nel pipeline (audit, fix, tests, patches)
- **Test da aggiungere o aggiornare:** Il test pre-esistente `testRunAuditStageUsesRustReductionForCandidatesAndAuditSnapshot` ora serve da regression test.
- **Strategia di fix minimo:** Aggiungere `init(from decoder:)` custom con `decodeIfPresent(...) ?? []` per tutti gli array non-optional, identico al pattern già usato in `ReviewPipelineRustStep`.
- **Verifica post-fix:** Tutti i 10 test di `ReviewPipelineCoordinatorTests` passano (0 failure).
- **Commit previsto:** `fix(review): add custom decoder for ReviewPipelineRustCallbackResult to handle missing JSON keys`
