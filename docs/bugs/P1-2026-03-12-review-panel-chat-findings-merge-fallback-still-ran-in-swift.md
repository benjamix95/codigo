# P1 - Il sync dei finding strutturati dalla chat review ricadeva ancora sulla dedup Swift del panel

## Bug Fix Record
- Categoria: A
- Bug: il panel review usava il reducer Rust per il merge dei `review_findings`, ma in caso di bridge non disponibile ricadeva ancora su una deduplica locale Swift.
- Sintomo: il path chat -> Findings manteneva due semantiche di merge possibili, una canonica Rust e una secondaria nel panel store.
- Impatto: rischio di drift tra snapshot canonico review e panel chat su inserted count, dedup key e ordine finale dei finding.
- Gravita': alta, perche' tocca il boundary tra chat review e snapshot canonico.
- Steps to reproduce:
  1. Iniettare nel panel un blocco `review_findings`.
  2. Seguire `syncStructuredFindingsFromChatResponse(...)`.
  3. Osservare il fallback `mergeChatFindingsFallback(...)`.
- Risultato attuale: il panel poteva ancora deduplicare i finding in locale.
- Risultato atteso: il merge/dedup dei finding chat deve passare solo da Rust; Swift deve limitarsi a parse del blocco e ingest dello snapshot aggiornato.
- Causa probabile: il fallback locale era stato lasciato come safety net durante la tranche iniziale del bridge Rust.
- Scope consentito:
  - `Native/RustCore/src/review_chat.rs`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ChatFindings.swift`
  - `docs/bugs`, `docs/changelog`
- Non-scope:
  - parsing markdown del blocco `review_findings`
  - UI del tab Chat
  - mutazioni live session
- Moduli confinanti da verificare:
  - `review_chat`
  - `CodeReviewPanelSessionScopingTests`
- Test da aggiungere o aggiornare:
  - unit Rust su inserted count per nuovi finding chat
  - regressione app-side esistente sul sync chat findings
- Strategia di fix minimo:
  - rimuovere il fallback Swift
  - lasciare il sync dipendere esclusivamente dal payload Rust
  - mantenere invariato il parsing del blocco e l’ingest dello snapshot
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml --quiet`
  - la copertura app-side resta indirettamente coperta da `CodeReviewPanelSessionScopingTests`; nessun nuovo errore di build introdotto nel path panel
- Commit previsto: `refactor(review-chat): remove swift findings merge fallback`
