# P2 — review audit adapters were still isolated in a dedicated audit file

## Categoria
- Categoria B — importante ma non bloccante

## Bug
- Il perimetro `Engine/CoderEngine/Sources/CodeReview/Audit` manteneva ancora un file Swift non-UI dedicato solo agli adapter opzionali dell'audit review.

## Sintomo
- `CodeReviewAuditService+Adapters.swift` continuava a contenere helper di supporto e parsing che non aggiungevano un boundary separato reale.

## Impatto
- Il debito Swift legacy del dominio review rimaneva più alto del necessario.
- Il servizio audit era frammentato tra più file piccoli con ownership poco chiara.

## Gravità
- Media.

## Riproduzione
1. Leggere il perimetro `Engine/CoderEngine/Sources/CodeReview/Audit`.
2. Verificare la presenza del file `CodeReviewAuditService+Adapters.swift`.
3. Osservare che il file conteneva solo helper statici di supporto al servizio audit principale.

## Risultato attuale
- Gli helper adapter erano ancora separati in un file dedicato Swift non-UI.

## Risultato atteso
- Gli helper adapter devono vivere nel servizio audit principale o in un modulo Rust/adapter con boundary reale, senza file Swift legacy isolati inutilmente.

## Causa probabile
- Tranche precedenti avevano drenato il perimetro audit in modo incrementale, lasciando questo file residuale come estensione separata.

## Scope consentito
- `Engine/CoderEngine/Sources/CodeReview/Audit/CodeReviewAuditService.swift`
- `Engine/CoderEngine/Sources/CodeReview/Audit/CodeReviewAuditService+Adapters.swift`
- test audit correlati
- progetto Xcode
- docs review cutover

## Non-scope
- logica Rust del review core
- altri tool audit non toccati
- flussi MCP o panel UI

## Moduli confinanti da verificare
- `CodeReviewAuditAdvancedTests`
- build `CoderEngineTests-Debug`
- boundary guard review

## Test da aggiungere o aggiornare
- regressione su adapter mancante che deve tornare `available == false`
- regressione su parser hint che deve produrre finding security quando il matcher è presente

## Strategia di fix minimo
- Assorbire i tre helper adapter nel file `CodeReviewAuditService.swift`.
- Eliminare il file estensione dedicato dal target.
- Lasciare invariato il contratto pubblico del servizio audit.

## Verifica post-fix
- `validate_rust_cutover_boundary.sh`
- `xcodebuild build-for-testing` sul target `CoderEngineTests-Debug`
- subset verde di `CodeReviewAuditAdvancedTests`

## Commit previsto
- `refactor(review): fold audit adapters into audit service`
