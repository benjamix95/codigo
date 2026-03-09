# P0 — Review candidate verification puo' promuovere falsi positivi

## Bug Fix Record
- Categoria: A
- Bug: `ReviewCandidateVerificationService` puo' promuovere un candidate a `verified` con controlli troppo deboli rispetto al significato del termine.
- Sintomo: finding o issue possono risultare `verified` anche se il sistema non dimostra davvero reachability, exploitability o causalita' del problema.
- Impatto: alto rischio di falsi positivi marchiati come verificati, con conseguente falsa sicurezza operativa e rumore nella review.
- Gravita': P0
- Steps to reproduce:
  1. Creare un candidate con `lineNumber` assente o debole.
  2. Inserire nel file una stringa che faccia match con `candidate.evidence`.
  3. Far passare il candidate nel verifier.
- Risultato attuale: il verifier puo' promuovere il finding tramite `file_evidence_search` o `semantic_risk_match` lessicale.
- Risultato atteso: la promozione a `verified` deve richiedere un livello di prova piu' forte, spiegabile e testato.
- Causa probabile: il verifier nasce come sanity check locale, ma il nome `verified` comunica una garanzia piu' forte del controllo implementato.
- Scope consentito: `Engine/CoderEngine/Sources/CodeReview/Verification/ReviewCandidateVerificationService.swift`, parser dei task review e test correlati.
- Non-scope: refactor generale della pipeline review o dell'UX findings.
- Moduli confinanti da verificare: `ReviewPipelineCoordinator+CandidateVerification`, `CodeReviewFinding` persistence/decoding, output MCP `review_findings`.
- Test da aggiungere o aggiornare:
  - test di regressione su candidate senza `lineNumber`
  - test che impedisca promozione su sola co-occorrenza testuale
  - test su `verificationMethod` e `verificationReport`
- Strategia di fix minimo:
  - bloccare la promozione a `verified` quando la prova e' solo testuale/lessicale
  - separare stati tipo `triaged`, `suspected`, `verified`
  - rafforzare il report di verifica con motivazione esplicita
- Verifica post-fix:
  - suite del verifier
  - smoke su `review_findings`
  - controllo che i candidate deboli non passino piu' come `verified`
- Commit previsto: `fix(review): tighten candidate verification promotion`
