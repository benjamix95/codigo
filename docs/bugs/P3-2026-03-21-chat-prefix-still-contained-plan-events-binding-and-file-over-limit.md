# Bug Fix Record
- Categoria: C
- Bug: il prefisso `Chat` conteneva ancora `ChatPanelView+PartF_PlanEvents.swift`, unico residuo `TaskTrace` rimasto sotto `Chat`, e il file era anche oltre il limite massimo richiesto per file di codice.
- Sintomo: il debito residuo `Chat` includeva ancora il routing degli eventi plan step/create/questionnaire, con un file da `301` righe.
- Impatto: perimetro legacy ancora presente e violazione della regola di modularità sotto `300` righe.
- Gravità: bassa
- Steps to reproduce:
  1. Eseguire `rust_cutover_guard` sul prefisso `App/SoloCodeApp/Sources/Chat`.
  2. Verificare `ChatPanelView+PartF_PlanEvents.swift` tra i residui legacy.
  3. Eseguire `wc -l` sul file e osservare che supera il limite.
- Risultato attuale: file legacy in `Chat` e sopra soglia.
- Risultato atteso: file spostato in `Services/ChatTaskTrace/Bindings` e spezzato in due unita' sotto soglia.
- Causa probabile: il file era stato lasciato fuori dalla tranche precedente proprio per essere trattato con split dedicato.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Chat/Support/Extensions/TaskTrace/ChatPanelView+PartF_PlanEvents.swift`
  - `App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_PlanEvents.swift`
  - `App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_PlanEventHelpers.swift`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - altri file `TaskTrace`
  - `SendMessage`
  - logica Rust della main chat
- Moduli confinanti da verificare:
  - `PlanShortcutAndCommandTests`
  - `PlanPanelWorkspacePolicyTests`
  - `TodoStoreTests`
- Test da aggiungere o aggiornare:
  - nessun nuovo test logico; smoke suite dei consumer gia' esistenti
- Strategia di fix minimo:
  - spostare il file nel modulo `ChatTaskTrace`
  - estrarre gli helper privati in un file fratello
- Verifica post-fix:
  - `xcodebuild test` sui consumer plan/todo
  - `validate_rust_cutover_boundary.sh` sul diff della tranche
- Commit previsto: `refactor(chat): split and relocate plan event bindings`
