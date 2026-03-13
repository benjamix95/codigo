# P1 - Un file review cancellato nel diff veniva ancora contato come legacy live dal boundary guard

## Bug Fix Record
- Categoria: A
- Bug: il boundary audit contava ancora i `candidate_files` espliciti anche quando il file era gia' stato rimosso dal workspace.
- Sintomo: una tranche review che cancellava un file Swift non-UI nel prefisso review continuava a fallire il budget gate come se il backlog non fosse sceso.
- Impatto: false negative sulla validation del cutover review; le tranche basate su delete o consolidamento file risultavano bloccate anche quando riducevano davvero il debito.
- Gravità: P1
- Steps to reproduce:
  1. Eliminare un file Swift non-UI dal prefisso review.
  2. Passare quel path nel set `--files` della validation.
  3. Osservare che il guard lo conta ancora nel report corrente del dominio review.
- Risultato attuale: il candidate file cancellato veniva trattato come se fosse ancora presente nel workspace live.
- Risultato atteso: il report corrente deve ignorare i candidate non piu' esistenti; solo il baseline `HEAD` deve poter includere file mancanti rispetto al workspace.
- Causa probabile: il boundary audit usava i `candidate_files` forniti dalla shell senza verificare l'esistenza locale, e il baseline era costruito con un workspace temporaneo che falsava il confronto.
- Scope consentito:
  - `Native/AppCoreProtocol`
  - `Native/AppCoreRust`
  - `scripts/validate_rust_cutover_boundary.sh`
- Non-scope:
  - logica del panel review
  - allowlist UI
  - pipeline di build/test oltre il boundary gate
- Moduli confinanti da verificare:
  - `rust_cutover_guard`
  - baseline `HEAD` nel wrapper shell
  - regressioni `app_core_boundary.rs`
- Test da aggiungere o aggiornare:
  - candidate file mancanti ignorati nel report corrente
  - baseline con `include_missing_candidate_files` attivo
- Strategia di fix minimo:
  - ignorare nel report corrente i candidate che non esistono piu' nel workspace
  - introdurre un flag esplicito solo per il baseline `HEAD`
  - ricalcolare il baseline usando il workspace reale invece di uno temporaneo vuoto
- Verifica post-fix:
  - `cargo test --manifest-path Native/AppCoreRust/Cargo.toml`
  - `scripts/solocode-validate --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+PipelineJobState.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+RustHistoryLiveState.swift,"Solo Code.xcodeproj/project.pbxproj",scripts/validate_rust_cutover_boundary.sh,Native/AppCoreProtocol/src/app_core.rs,Native/AppCoreRust/src/boundary/audit.rs,Native/AppCoreRust/src/bin/rust_cutover_guard.rs,Native/AppCoreRust/tests/app_core_boundary.rs`
- Commit previsto: `fix(cutover): count deleted review files only in baseline`

## Fix applicato
- aggiunto `include_missing_candidate_files` al boundary audit
- il report corrente ignora i candidate non presenti nel workspace
- il baseline review usa il workspace reale e abilita il flag solo per la fotografia di `HEAD`

## Esito
- la tranche review che rimuove `CodeReviewPanelStore+RustHistoryLiveState.swift` viene ora contabilizzata correttamente
- backlog panel review ridotto da `33` a `32`
