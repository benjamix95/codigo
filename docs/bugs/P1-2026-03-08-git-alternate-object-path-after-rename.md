# P1 - Git alternate object path rotto dopo rename progetto

## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: dopo il rename della root locale da `solocode` a `SoloCode`, Git fallisce su repository annidati dentro `.xcodebuild-test-1/2` con errore `unable to normalize alternate object path`.
- Sintomo: `git status` sul repository principale e `git status` dentro i checkout SPM annidati falliscono su path come `/Users/benjaminstoica/SoloCode/.xcodebuild-test-1/SourcePackages/repositories/SwiftTerm-74b92343/objects`.
- Impatto: pannelli Git e comandi CLI si rompono quando Git attraversa i checkout Swift Package Manager versionati nei sandbox `.xcodebuild-test-*`.
- Gravità: alta lato workflow locale
- Steps to reproduce:
  1. Rinominare il progetto locale da `solocode` a `SoloCode`.
  2. Eseguire `git -C .xcodebuild-test-1/SourcePackages/checkouts/SwiftTerm status --short`.
  3. Eseguire `git status` nella root del repository.
- Risultato attuale: i checkout SPM usano file `objects/info/alternates` con path assoluti verso il vecchio root `solocode`, quindi HEAD diventa illeggibile e Git fallisce anche nel repository principale quando attraversa quei checkout.
- Risultato atteso: gli `alternates` devono puntare al nuovo root `SoloCode`, così i checkout SPM e il repository principale tornano ispezionabili da Git.
- Causa probabile: i sandbox `.xcodebuild-test-1/2` contengono checkout Git tracciati nel repository; i rispettivi file `objects/info/alternates` sono stati generati con path assoluti e non sono stati riallineati dopo il rename della cartella progetto.
- Scope consentito: file `objects/info/alternates` sotto `.xcodebuild-test-1/2/SourcePackages/checkouts/*/.git`, documentazione bug/changelog.
- Non-scope: pulizia completa dei sandbox `.xcodebuild-test-*`, rimozione dal versionamento dei build artifact, refactor del flusso Xcode/SPM.
- Moduli confinanti da verificare: root repo Git, checkout `SwiftTerm` in `.xcodebuild-test-1/2`, altri checkout SPM che usano alternates assoluti.
- Test da aggiungere o aggiornare: scenario manuale ripetibile con `git status` root e `git -C .../SwiftTerm status --short`.
- Strategia di fix minimo: sostituire il prefisso assoluto `/Users/benjaminstoica/SoloCode` con `/Users/benjaminstoica/SoloCode` nei file `objects/info/alternates` dei checkout SPM coinvolti.
- Verifica post-fix:
  1. `git -C .xcodebuild-test-1/SourcePackages/checkouts/SwiftTerm status --short`
  2. `git -C .xcodebuild-test-2/SourcePackages/checkouts/SwiftTerm status --short`
  3. `git status --short --branch`
  4. `rg -n '/Users/benjaminstoica/SoloCode/.xcodebuild-test-[12]/SourcePackages/repositories' .xcodebuild-test-1 .xcodebuild-test-2`
- Commit previsto: `fix(git): realign xcodebuild alternate object paths`
