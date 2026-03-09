# P1 — Il patch workflow review applica con garanzie deboli e spiegazione incompleta

## Bug Fix Record
- Categoria: A
- Bug: `review_preview_patch` mostra il diff ma non spiega in modo adeguato il finding; `review_apply_patch` non espone diff/rationale prima dell'applicazione e il workflow review usa garanzie piu' deboli del transaction engine.
- Sintomo: l'utente riceve preview/apply con contesto limitato e con un livello di verifica inferiore rispetto al motore patch piu' robusto presente nel repo.
- Impatto: ridotta spiegabilita', rischio di applicare patch con garanzie incomplete, mismatch tra aspettative e protezioni reali.
- Gravita': P1
- Steps to reproduce:
  1. Preparare una patch review da un finding verificato.
  2. Richiedere `review_preview_patch`.
  3. Richiedere `review_apply_patch`.
- Risultato attuale:
  - preview: diff presente, rationale insufficiente
  - apply: nessun diff/rationale in risposta
  - verify: `git apply --check` come controllo principale nel path review
- Risultato atteso:
  - preview con diff e spiegazione del finding che la patch risolve
  - apply solo dopo gate piu' forti e con esito chiaramente motivato
- Causa probabile: patch workflow review separato e piu' leggero rispetto a `PatchApplyTransaction`.
- Scope consentito: `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview/CodeReviewHandler+PatchWorkflow.swift`, `App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService.swift`, integrazione con transaction engine.
- Non-scope: redesign completo dell'UX code review o nuove feature PR.
- Moduli confinanti da verificare: `PatchApplyTransaction`, `PatchRiskScorer`, `BlastRadiusChecker`, `CodeReviewFinding`/patch artifacts.
- Test da aggiungere o aggiornare:
  - test handler patch workflow
  - test su `review_preview_patch` con rationale obbligatorio
  - test su `review_apply_patch` con gating forte e failure path
- Strategia di fix minimo:
  - esporre `finding.message`, severita' e motivo della patch nella preview
  - allineare `review_apply_patch` ai gate del transaction engine o riusare il transaction engine
  - impedire apply senza uno stato di verify coerente
- Verifica post-fix:
  - test patch workflow review
  - smoke su preview/apply/verify
  - controllo rollback e quality gate
- Commit previsto: `fix(review): harden patch apply workflow and explainability`
