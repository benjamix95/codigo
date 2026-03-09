# P1 - Repo structure drift, root pollution e artefatti generati nel workspace

## Categoria
- B

## Bug
- Il repository esponeva nel root file sorgente applicativi, documenti duplicati e artefatti locali di build/test, rendendo opaco il perimetro reale del progetto.

## Sintomo
- File Swift del pannello review lasciati in root.
- Documenti funzionali duplicati tra root e `docs/`.
- Presenza nel root di output locali come `.xcodebuild-test-*`, `.build`, `build`, `Codigo.app`, file temporanei e log.

## Impatto
- Onboarding più lento.
- Maggiore rischio di edit nel file sbagliato.
- Root poco leggibile e difficile da mantenere pulito nel tempo.
- Drift progressivo tra struttura reale del codice e workspace quotidiano.

## Gravità
- P1

## Steps to reproduce
1. Aprire il repository dal root.
2. Elencare i file top-level.
3. Osservare la presenza di sorgenti applicativi, duplicati documentali e output generati nello stesso livello.

## Risultato attuale
- Il root non distingue chiaramente tra codice canonico, documentazione e output locali.

## Risultato atteso
- Il root deve contenere solo entry-point strutturali del progetto.
- I file Swift applicativi devono vivere nei moduli `App/...` corretti.
- Gli output temporanei devono essere ignorati e rimovibili senza ambiguità.

## Causa probabile
- Crescita iterativa del progetto con file aggiunti rapidamente in root e artefatti locali non completamente coperti da `.gitignore`.

## Scope consentito
- `.gitignore`
- `README.md`
- `Solo Code.xcodeproj/project.pbxproj`
- File Swift root-level del pannello Code Review
- Documentazione `docs/bugs` e `docs/changelog`

## Non-scope
- Refactor dei simboli applicativi
- Riorganizzazione massiva dell’intero albero test
- Cambiamenti di comportamento UI o runtime

## Moduli confinanti da verificare
- `App/SoloCodeApp/Sources/Panels/CodeReview/Views/Chat`
- `App/SoloCodeApp/Sources/Panels/CodeReview/Store`
- setup Xcode nel `project.pbxproj`

## Test da aggiungere o aggiornare
- Nessun test automatico dedicato: intervento di struttura/documentazione.
- Verifica manuale: progetto Xcode ancora risolvibile, script di release coerente, root ripulito.

## Strategia di fix minimo
- Spostare i file Swift root-level nelle directory già esistenti del modulo Code Review.
- Aggiornare solo i path nel `project.pbxproj`.
- Eliminare il duplicato documentale root-level.
- Rafforzare `.gitignore` per gli output locali osservati.

## Verifica post-fix
- `git diff --stat`
- `xcodebuild -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -showBuildSettings`
- `./scripts/release.sh --help`

## Commit previsto
- `chore(repo): normalize code review file placement and root hygiene`
