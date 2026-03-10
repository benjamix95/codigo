# P2 — Summary review con queue e security gate derivati da sorgenti diverse

## Bug Fix Record
- Categoria: B
- Bug: il summary del review panel usava queue ricostruite ma `securityGate` letto solo dall’envelope embedded nello snapshot.
- Sintomo: per snapshot senza `verifiedFindings` embedded il summary poteva risultare internamente contraddittorio.
- Impatto: stato UI ambiguo nel pannello review.
- Gravità: media
- Steps to reproduce:
  1. Generare uno snapshot review senza envelope embedded.
  2. Lasciare che il panel ricostruisca la projection dai finding correnti.
  3. Leggere il summary.
- Risultato attuale: `verified_queue`/`candidate_queue` e `security_gate_ready` potevano non rappresentare la stessa sorgente.
- Risultato atteso: projection e security gate devono derivare dallo stesso `VerifiedFindingsResolvedState`.
- Causa probabile: mix tra `resolvedVerifiedFindingsState(...)` e `snapshot.verifiedFindings`.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Views/Chat/ReviewPanelChatMessageFactory.swift`
  - `Tests/SoloCodeAppTests/ReviewPanelChatMessageFactoryTests.swift`
- Non-scope:
  - cambiamenti al checkpoint service
  - recupero shared/persisted sul main thread
- Moduli confinanti da verificare:
  - `ReviewPanelChatMessageFactoryTests`
  - rendering del summary review
- Test da aggiungere o aggiornare:
  - regressione su `security_gate_ready` coerente quando l’envelope viene ricostruita
- Strategia di fix minimo:
  - riusare lo stesso `ResolvedState` per projection e security gate
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelChatMessageFactoryTests`
- Commit previsto: `fix(review-panel): align summary security gate with resolved state`

## Evidenza
- il test nuovo verifica che uno snapshot senza envelope embedded mostri `security_gate_ready: true` quando la state reconstruction lo rende pronto
