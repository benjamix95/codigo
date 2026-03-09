# 2026-03-09 — validation pipeline e commit guard staged-only

## Modifiche
- aggiunto il sottosistema `Validation` in `Engine/CoderEngine/Sources/Validation`
- introdotta config versionata in `Config/validation/solocode-validation.json`
- aggiunti stage fail-fast per patch safety, code size, build, test mirati, security, regression, performance ed E2E
- integrato il patch workflow review con validation preview, summary sugli artifact e rollback post-apply
- esteso `ReviewPatchArtifact` con `validationRunId`, `validationStatus` e `validationSummary`
- trasformato il commit locale in staged-only con validation obbligatoria prima di `git commit`
- aggiunti `scripts/solocode-validate`, `.githooks/pre-commit`, `scripts/install-hooks.sh` e workflow GitHub Actions
- aggiunta baseline documentata dei file di codice oltre 300 righe

## Verifica prevista
- suite unit mirate per resolver, selector, patch safety, code size e orchestrator fail-fast
- test app per il guard staged-only del commit
- validazione locale e CI tramite `scripts/solocode-validate`

## Note
- il rollout iniziale resta sul perimetro `patch+commit`
- `ciFull` tiene i gate pesanti separati dal flusso locale sincrono
