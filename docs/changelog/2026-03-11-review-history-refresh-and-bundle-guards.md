# 2026-03-11 — Review history refresh, bundle guards e isolamento Postgres test

## Modifiche
- differito al tick successivo del main queue i publish di `refreshGitContext()` e `refreshHistoricalFindings()` nel `CodeReviewPanelStore`, introducendo flag interni per evitare re-entry durante il render SwiftUI.
- ristretto il trigger automatico di `Findings History` a una chiave stabile (`workspace + selected session`) e rimosso il prefetch history dal root host del pannello review.
- aggiunto lo script repo-local `scripts/validate_app_bundle.sh` per verificare bundle app, framework embedded richiesti e link runtime verso `CoderEngine.framework`.
- collegato `validate_app_bundle.sh` a `scripts/run-app.sh` e `scripts/build-app.sh` per fallire subito su bundle incompleti invece di lanciare/esportare artefatti corrotti.
- aggiunte regressioni in `AppBundleProjectStructureTests` per il target app e in `ReviewPanelFindingsHistoryTests` per la stabilità della chiave di refresh storico.
- corretto l’harness dei test app di history persistence usando root directory Postgres UUID-based e porta dedicata, con cleanup dell’override env.

## Verifica
- build `Solo Code-Debug`: verde.
- `scripts/validate_app_bundle.sh <Solo Code.app>`: verde.
- `AppBundleProjectStructureTests`: verde.
- `ReviewPanelFindingsHistory*`: il bug `initdb ... data exists but is not empty` non si ripresenta più dopo l’isolamento della root Postgres; resta un failure locale noto di `IDELaunchServicesLauncher`/attach del test host macOS in Xcode.
