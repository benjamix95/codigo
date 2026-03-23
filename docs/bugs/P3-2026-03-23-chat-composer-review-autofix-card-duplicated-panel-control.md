# P3 - Il chat composer duplicava il controllo Code Review/Autofix gia' presente nel review panel

## Bug Fix Record
- Categoria: C - Minore / cosmetico
- Bug: il chat composer mostrava una card `Code Review` con toggle `Autofix/Discovery` anche quando il review panel dedicato copre gia' quel controllo operativo.
- Sintomo: entrando in modalita' review nel composer compariva una card aggiuntiva sotto quick commands e review modes.
- Impatto: UX ridondante e ambigua; il composer suggeriva un controllo locale duplicato rispetto al panel review indipendente.
- Gravita': P3
- Steps to reproduce:
  1. Aprire la main chat.
  2. Passare in modalita' review.
  3. Guardare il blocco inferiore del composer sotto quick commands e chip `Standard / Security Audit / Bug Finder`.
- Risultato attuale: compare una card `Code Review` con stato `Autofix` o `Discovery`.
- Risultato atteso: il composer non deve mostrare quella card; i controlli review restano confinati al panel review dedicato.
- Causa probabile: il composer continuava a montare `codeReviewAutofixToggleRow` tramite wiring locale (`showCodeReviewAutofixToggle` + binding `codeReviewAutofixEnabled`) ereditato dalla modalita' review.
- Scope consentito:
  - `App/SoloCodeApp/Sources/ChatView/Composer/ChatComposerView.swift`
  - `App/SoloCodeApp/Sources/ChatView/Composer/ChatComposerView+Commands.swift`
  - `App/SoloCodeApp/Sources/Services/ChatInteraction/ChatBindings/ChatPanelView+PartH_TaskActivity.swift`
  - test del composer in `Tests/SoloCodeAppTests/ComposerRuntimeTimerTests.swift`
  - documentazione bug/changelog
- Non-scope:
  - panel Code Review dedicato
  - logica runtime `codeReviewAnalysisOnly`
  - quick commands review e chip modalita' review del composer
  - file locali `MessageToolTrace*` fuori scope
- Moduli confinanti da verificare:
  - quick commands review nel composer
  - review mode chips nel composer
  - wiring generale del composer runtime
- Test da aggiungere o aggiornare:
  - smoke/regression test del composer che verifica assenza della card review legacy dal rendering del composer
- Strategia di fix minimo:
  - rimuovere il render della card `codeReviewAutofixToggleRow`
  - eliminare il wiring dedicato dal `ChatComposerView`
  - lasciare invariati panel review, quick commands e modalita' review
- Verifica post-fix:
  - ricerca sorgente: nessun riferimento residuo a `showCodeReviewAutofixToggle`, `codeReviewAutofixEnabled`, `codeReviewAutofixToggleRow`
  - `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ComposerRuntimeTimerTests CODE_SIGNING_ALLOWED=NO`: OK
- Commit previsto:
  - `fix(chat): remove duplicated code review autofix card from composer`
