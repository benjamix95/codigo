# P2 — review audit impact tools were still isolated in a dedicated bug audit file

## Categoria
- Categoria B — importante ma non bloccante

## Bug
- Il perimetro audit review manteneva ancora `CodeReviewAuditService+Impact.swift` come file Swift non-UI separato per tre audit bug già appartenenti allo stesso cluster funzionale del bug audit.

## Sintomo
- Gli audit `bugTestImpact`, `bugDependencyDrift` e `bugDiffSemantics` erano separati dal resto del bug audit, senza un boundary tecnico distinto.

## Impatto
- Debito Swift legacy review più alto del necessario.
- Ownership del bug audit spezzata tra file troppo granulari.

## Gravità
- Media.

## Steps to reproduce
1. Aprire `Engine/CoderEngine/Sources/CodeReview/Audit`.
2. Verificare la presenza di `CodeReviewAuditService+Impact.swift`.
3. Osservare che il file contiene solo tool bug audit già richiamati dallo stesso servizio principale.

## Risultato attuale
- Gli audit di impact vivevano in un file dedicato Swift non-UI.

## Risultato atteso
- Gli audit bug correlati devono vivere nello stesso modulo bug-side, lasciando meno frammenti Swift legacy.

## Causa probabile
- Il cutover è avanzato per tranche piccole e questo gruppo di tool è rimasto come residuo separato.

## Scope consentito
- `Engine/CoderEngine/Sources/CodeReview/Audit/CodeReviewAuditService+Bug.swift`
- `Engine/CoderEngine/Sources/CodeReview/Audit/CodeReviewAuditService+Impact.swift`
- test audit review correlati
- progetto Xcode
- docs cutover review

## Non-scope
- audit security
- review core Rust
- panel UI

## Moduli confinanti da verificare
- `CodeReviewAuditAdvancedTests`
- build `CoderEngineTests-Debug`
- boundary guard review

## Test da aggiungere o aggiornare
- regressione sul lockfile drift che deve produrre finding di regressione

## Strategia di fix minimo
- Spostare i tre audit impact in `CodeReviewAuditService+Bug.swift`.
- Eliminare il file dedicato dal target.
- Validare solo il perimetro audit coinvolto.

## Verifica post-fix
- `validate_rust_cutover_boundary.sh`
- `xcodebuild build-for-testing` su `CoderEngineTests-Debug`
- subset verde di `CodeReviewAuditAdvancedTests`

## Commit previsto
- `refactor(review): fold audit impact into bug audit`
