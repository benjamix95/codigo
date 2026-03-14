# P2 — review handler resolution was still isolated in a dedicated MCP file

## Categoria
- Categoria B — importante ma non bloccante

## Bug
- Il perimetro MCP review manteneva ancora `CodeReviewHandler+Resolution.swift` come file Swift non-UI separato per risoluzione sessione, validation e queueing dei comandi.

## Sintomo
- Le funzioni di session resolution e access validation vivevano lontane dai file handler che le usano direttamente.

## Impatto
- Debito Swift legacy review più alto del necessario.
- Ownership del boundary MCP review dispersa.

## Gravità
- Media.

## Steps to reproduce
1. Aprire `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview`.
2. Verificare la presenza di `CodeReviewHandler+Resolution.swift`.
3. Osservare che il file contiene solo helper condivisi da `+Start`, `+PatchWorkflow` e `RustHandlerSupport`.

## Risultato attuale
- Gli helper di risoluzione MCP review erano ancora in un file dedicato residuale.

## Risultato atteso
- Gli helper devono vivere accanto ai rispettivi handler o al supporto Rust che li usa.

## Causa probabile
- Il cutover handler-side aveva drenato prima il file principale, lasciando questo blocco helper come residuo.

## Scope consentito
- `CodeReviewHandler+Start.swift`
- `CodeReviewRustHandlerSupport.swift`
- `CodeReviewHandler+PatchWorkflow.swift`
- `CodeReviewHandler+Resolution.swift`
- test handler review correlati
- progetto Xcode
- docs cutover review

## Non-scope
- review core Rust
- servizi verified findings
- panel UI

## Moduli confinanti da verificare
- `CodeReviewHandlerTests+SessionResolution`
- `CodeReviewHandlerTests+PatchLifecycle`
- `MCPSharedCodeReviewCommandsTests`
- build `CoderEngineTests-Debug`

## Test da aggiungere o aggiornare
- nessun nuovo test necessario: il perimetro ha già suite handler dedicate

## Strategia di fix minimo
- Spostare backend/session-id validation in `CodeReviewHandler+Start.swift`.
- Spostare risoluzione sessione in `CodeReviewRustHandlerSupport.swift`.
- Spostare queueing e ownership validation in `CodeReviewHandler+PatchWorkflow.swift`.
- Eliminare il file resolution dedicato dal target.

## Verifica post-fix
- `validate_rust_cutover_boundary.sh`
- `xcodebuild build-for-testing` su `CoderEngineTests-Debug`
- subset verde delle suite handler review

## Commit previsto
- `refactor(review): fold handler resolution into mcp handlers`
