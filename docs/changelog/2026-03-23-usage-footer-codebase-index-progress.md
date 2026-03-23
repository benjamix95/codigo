# 2026-03-23 Usage footer codebase index progress

## Summary
- Aggiunta nel footer la visualizzazione della percentuale di avanzamento dell'index della codebase, usando lo stato già esposto da `WorkspaceStore.indexProgress`.
- La UI del footer resta confinata al layer `UsageFooterView` e non modifica il motore di indexing.

## Changes
- `App/SoloCodeApp/Sources/Tasking/Views/Usage/UsageFooterView+Sections.swift`
  - composizione della sezione footer per mostrare il progresso durante l'indexing.
- `App/SoloCodeApp/Sources/Tasking/Views/Usage/UsageFooterView+UsageRows.swift`
  - rendering del testo percentuale e fallback quando il progresso non è disponibile.
- `Tests/SoloCodeAppTests`
  - regressione mirata per il testo/visibilita della percentuale nel footer.

## Validation
- Review subagent completata: nessun bug confermato sulla feature; raccomandata copertura del ramo divider, poi aggiunta in questa patch.
- Comando eseguito: `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -only-testing:SoloCodeAppTests/UsageFooterContextProgressTests`
- Esito attuale: la build della feature arriva oltre i file toccati, ma la suite del target `SoloCodeAppTests` fallisce per errori preesistenti fuori scope nel branch, con messaggi `'nil' is not compatible with expected argument type 'String'` in test del gruppo plan panel (ad esempio `PlanPanelPreviewContentTests.swift`).
- Per questo motivo la patch non e' stata staged o committata in automatico.

## Notes
- Il calcolo della percentuale non e' introdotto in questa modifica: viene riusato il contratto esistente di `IndexingProgress.percentText`.
- Se emergono bug collaterali, registrarli in `docs/bugs` con priorita e file coinvolti.