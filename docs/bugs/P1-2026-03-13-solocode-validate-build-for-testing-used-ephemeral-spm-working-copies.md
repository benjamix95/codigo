# P1 - `solocode-validate` usava working copy SwiftPM effimere e instabili in `build-for-testing`

## Bug Fix Record
- Categoria: A
- Bug: `scripts/solocode-validate` eseguiva `xcodebuild build-for-testing` con `DerivedData` temporaneo ma senza un clone dir SwiftPM stabile, costringendo xcodebuild a rigenerare working copy fragili a ogni run.
- Sintomo: il validator falliva in `buildForTesting` con errori casuali di checkout (`unable to write new index file`, `unable to read tree`, `not a git repository`).
- Impatto: impossibilita' di ottenere un verde affidabile del guard, anche con codice corretto e package cache sane.
- Gravita': alta, perche' blocca il commit guard obbligatorio del repository.
- Steps to reproduce:
  1. Eseguire `./scripts/solocode-validate --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --staged`.
  2. Lasciare che il validator entri in `buildForTesting`.
  3. Osservare failure random nella fase di creazione delle working copy SwiftPM.
- Risultato attuale: `buildForTesting` ricreava working copy SwiftPM in un contesto temporaneo non stabile.
- Risultato atteso: il validator deve risolvere pacchetti una volta in un clone dir stabile e riusarlo per `build-for-testing`.
- Causa probabile: uso di `DerivedData` effimero senza `-clonedSourcePackagesDirPath` e senza `resolvePackageDependencies` seriale preliminare.
- Scope consentito:
  - `scripts/solocode-validate`
  - documentazione `docs/bugs`, `docs/changelog`
- Non-scope:
  - package manifest del progetto
  - logica di business app/engine
- Moduli confinanti da verificare:
  - `buildForTesting` nel validator
  - esecuzione `xcodebuild test-without-building` successiva
- Test da aggiungere o aggiornare:
  - nessun nuovo test; la verifica e' il validator verde
- Strategia di fix minimo:
  - introdurre clone dir SwiftPM stabile nel validator
  - eseguire `xcodebuild -resolvePackageDependencies` prima di `build-for-testing`
  - riusare lo stesso clone dir per il build
- Verifica post-fix:
  - `./scripts/solocode-validate --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --staged`
- Commit previsto: `fix(validation): stabilize xcode build-for-testing package resolution`
