# 2026-03-08 - Git alternate object path fix dopo rename progetto

- Documentato il bug in [P1-2026-03-08-git-alternate-object-path-after-rename.md](/Users/benjaminstoica/SoloCode/docs/bugs/P1-2026-03-08-git-alternate-object-path-after-rename.md).
- Riallineati i file `objects/info/alternates` nei checkout SPM annidati in `.xcodebuild-test-1/2` dal vecchio root `/Users/benjaminstoica/SoloCode` al nuovo `/Users/benjaminstoica/SoloCode`.
- Verificato il ripristino di `git status` sia nei checkout `SwiftTerm` coinvolti sia nella root del repository.
- Segnalato come debito strutturale separato il fatto che i sandbox `.xcodebuild-test-*` e i loro checkout/build artifact risultano versionati nel repository.
