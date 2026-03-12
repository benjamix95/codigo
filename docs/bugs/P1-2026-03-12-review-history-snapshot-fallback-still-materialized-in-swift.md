# P1 - Il fallback history del review panel continuava a materializzare record storici in Swift

## Bug Fix Record
- Categoria: A
- Bug: il panel review conservava ancora un fallback legacy Swift che derivava `HistoricalFindingRecord` dagli snapshot review quando il DB storico era vuoto o incompleto.
- Sintomo: `fallbackHistoricalFindings()` usava il bridge Rust, ma se la shape finale non tornava disponibile ricadeva su mapping/status/timeline locali Swift.
- Impatto: rischio di drift tra history canonica Rust e storico panel, soprattutto su status patch, verdict di revalidation e resume queue.
- Gravita': alta, perche' tocca il boundary storico del dominio review.
- Steps to reproduce:
  1. Aprire il tab History senza storico persistito completo.
  2. Lasciare che il panel ricada sugli snapshot review in memoria.
  3. Seguire `CodeReviewPanelStore+RustHistoricalFindings.swift`.
- Risultato attuale: la derivazione storica finale dipendeva ancora da un fallback Swift locale.
- Risultato atteso: i record storici fallback devono essere sempre derivati da Rust; Swift deve solo orchestrare richiesta e pubblicazione.
- Causa probabile: la tranche precedente aveva migrato i reducer Rust, ma aveva lasciato un safety net locale per non rischiare regressioni lato panel.
- Scope consentito:
  - `Native/RustCore/src/review_history/*`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+RustHistoricalFindings.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+History.swift`
  - `Tests/SoloCodeAppTests/ReviewPanelFindingsHistoryRustFallbackTests.swift`
  - `Solo Code.xcodeproj/project.pbxproj`
  - `docs/bugs`, `docs/changelog`
- Non-scope:
  - UI SwiftUI del tab History
  - live board activity-driven
  - pipeline review runtime
- Moduli confinanti da verificare:
  - `review_history::snapshot`
  - `ReviewPanelFindingsHistoryTests`
  - `ReviewPanelFindingsHistoryLiveBoardTests`
- Test da aggiungere o aggiornare:
  - unit Rust su derivazione history da snapshot con patch applicata/validata
  - regressione app-side sul fallback storico da snapshot
- Strategia di fix minimo:
  - rimuovere il motore legacy Swift
  - usare solo derivazione Rust per snapshot fallback e shape finale
  - lasciare a Swift solo un fallback pass-through dei record gia' derivati da Rust se la shape finale non risponde
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml --quiet`
  - `cargo test --manifest-path Native/CoderideMCPServerRust/Cargo.toml --quiet`
  - `xcodebuild test -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryTests -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryRustFallbackTests`
  - in questo ambiente il build passa fino al lancio dei bundle test, poi si ferma per code-signature/system policy sui bundle `xctest`
- Commit previsto: `refactor(review-history): remove swift snapshot fallback shaping`
