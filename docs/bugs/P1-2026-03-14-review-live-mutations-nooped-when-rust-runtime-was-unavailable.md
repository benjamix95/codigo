# P1 — Review live mutations no-op quando il runtime Rust non è disponibile

## Categoria
- A — Critico

## Bug
- Le mutation live del dominio review (`dismiss` e `configure`) potevano non produrre alcun effetto osservabile quando `ReviewCoreBridge` non era caricato.

## Sintomo
- `CodeReviewPanelStore.dismissFinding(...)` lasciava finding ed eventi invariati.
- `ReviewSessionRegistry.updateConfig(...)` ritornava `false` e non aggiornava config/eventi.

## Impatto
- Il panel review poteva mostrare finding ancora `open` dopo un dismiss.
- Il `TaskActivityStore` poteva non ricevere snapshot aggiornati.
- Il registry live perdeva il contratto di mutazione locale in ambienti di test o fallback runtime.

## Gravità
- Alta: rompe stato condiviso e persistenza osservabile del flusso review.

## Steps to reproduce
1. Registrare una sessione review live.
2. Non caricare il runtime Rust review oppure forzare un path in cui `ReviewCoreBridge.call(...)` ritorna `nil`.
3. Eseguire `dismissFinding(...)` dal panel oppure `updateConfig(...)` dal registry.

## Risultato attuale
- Nessuna mutation persistita oppure snapshot non ingestato nel `TaskActivityStore`.

## Risultato atteso
- Il sistema deve applicare una mutation locale equivalente e pubblicare subito lo snapshot aggiornato.

## Causa probabile
- Il ramo live dipendeva dal mutator Rust senza un fallback Swift equivalente.
- Nel panel, il ramo di successo del registry usava ingest differita, lasciando una finestra in cui i test leggevano ancora lo stato vecchio.

## Scope consentito
- `Engine/CoderEngine/Sources/CodeReview/Session/ReviewSessionRegistry.swift`
- `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+CompletionFinalization.swift`
- `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+SnapshotMutation.swift`

## Non-scope
- Pipeline review completa
- Provider runtime
- MCP review handlers

## Moduli confinanti da verificare
- `ReviewSessionRegistryTests`
- `CodeReviewPanelLiveMutationRustTests`
- `CodeReviewPanelSessionScopingTests`

## Test di regressione
- `SoloCodeAppTests/CodeReviewPanelLiveMutationRustTests`
- `SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testPanelDismissFallbackUsesRustMutationAndMarksWontFix`
- `CoderEngineTests/ReviewSessionRegistryTests`

## Strategia di fix minimo
- Fallback locale nel registry per `apply_fix`, `dismiss`, `comment` e `configure`.
- Ingest immediato dello snapshot nel panel per il ramo live riuscito.
- Fallback locale nel panel closed-session per l’azione `dismiss`.

## Verifica post-fix
- Build-for-testing completa verde.
- Subset app review panel verde.
- Subset engine registry/provider verde.

## Commit previsto
- `fix(review): restore live mutation fallback when rust review core is unavailable`
