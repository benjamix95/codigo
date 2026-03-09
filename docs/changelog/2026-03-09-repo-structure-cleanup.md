# Changelog - 2026-03-09 - Repo structure cleanup

## Obiettivo
- Ridurre il disordine del root repository.
- Riallineare i file del pannello Code Review alla struttura modulare reale.
- Correggere drift tra documentazione, script e layout corrente del progetto.

## Modifiche eseguite
- Spostati i file Swift del pannello review fuori dal root e dentro:
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Views/Chat/`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/`
- Aggiornati i path dei file referenziati in `Solo Code.xcodeproj/project.pbxproj`.
- Rimosso il duplicato root-level `scopo_app.md`, mantenendo la versione canonica in `docs/SCOPO_APP.md`.
- Rafforzato `.gitignore` per:
  - `.xcodebuild/`
  - `.xcodebuild-test-*/`
  - `build/`
  - `*.xcworkspace/xcuserdata/`
  - `firebase-debug.log`
  - `.tmp_*`
- Rimossa dal versionamento la state utente workspace-specific `xcuserstate`.
- Riallineato `README.md` ai percorsi e script reali del repository.
- Corretto `scripts/release.sh`:
  - usa `scripts/build-app.sh`
  - crea lo zip a partire dal bundle reale in `dist/`
- Corretto `scripts/check_english_only.sh` per usare i path correnti di app, engine e test.

## Rischio e contenimento
- Nessun rename simbolico.
- Nessuna modifica al comportamento delle view.
- Nessun refactor dei moduli applicativi.
- Cambiamenti confinati a struttura file, documentazione, ignore rules e script release.

## Verifica prevista
- `xcodebuild -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -showBuildSettings`
- `./scripts/release.sh --help`
- ispezione di `git diff --stat`
