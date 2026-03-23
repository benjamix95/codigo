# P2 - Placeholder operativi e rumore MCP dei subagent interferivano con la chat task-first

## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: il main chat trattava ancora alcuni placeholder runtime come todo auto-completabili e considerava i subagent MCP come lavoro soggetto al gate `todo_first_required`.
- Sintomo:
  - dopo un batch subagent il runtime poteva completare o promuovere un placeholder operativo invece di un task reale
  - alcuni `coderide_subagent_*` potevano produrre un falso errore `todo_first_required`
  - il feed lineare restava esposto a regressioni sul filtro di `policy_ack`
- Impatto: UI task-first meno affidabile; il sistema poteva dare priorita' a task interni o bloccare tool dei subagent che non dovrebbero essere trattati come lavoro utente.
- Gravita': P2
- Steps to reproduce:
  1. Avviare un turn agent con placeholder runtime o subagent MCP prima della checklist esplicita.
  2. Far terminare un batch subagent con almeno un todo reale e un placeholder operativo in parallelo.
  3. Osservare auto-complete rumoroso o un gate `todo_first_required` su tool `coderide_subagent_*`.
- Risultato attuale: placeholder operativi e subagent MCP rientravano ancora in percorsi pensati per task reali.
- Risultato atteso:
  - i placeholder operativi non devono essere auto-completati come todo reali
  - i subagent MCP non devono essere considerati lavoro soggetto al gate `todo_first_required`
  - `policy_ack` deve restare nascosto nel feed lineare con copertura di regressione
- Causa probabile:
  - il filtro di auto-complete post-subagent non escludeva `isOperationalPlaceholder`
  - il gate `todoPlanStartPolicyViolation` trattava ancora i tool `subagent_*` come operazioni utente
  - mancava una regressione esplicita per il filtro di `policy_ack` nel feed MCP
- Scope consentito:
  - `App/SoloCodeApp/Sources/Services/ChatThread/ChatPanelSupport+Core.swift`
  - `Tests/SoloCodeAppTests/ChatTodoVisibilityTests.swift`
  - `Tests/SoloCodeAppTests/ChatPanelTodoFinalizationTests.swift`
  - documentazione bug/changelog collegata
- Non-scope:
  - persistenza completa dei todo placeholder
  - reasoning stream Rust
  - timeline invalidation dei plan/todo live mutation
  - parsing provider CLI/Rust
- Moduli confinanti da verificare:
  - `todoIDsToAutoCompleteAfterSubagentBatch`
  - `todoPlanStartPolicyViolation`
  - filtro feed lineare per eventi MCP
- Test da aggiungere o aggiornare:
  - `ChatPanelTodoFinalizationTests`
  - `ChatTodoVisibilityTests`
- Strategia di fix minimo:
  - escludere `isOperationalPlaceholder` dall'auto-complete post-subagent
  - esentare i tool `subagent_*` dal gate todo-first
  - mantenere una regressione che garantisca che `policy_ack` resti nascosto nel feed lineare
- Verifica post-fix:
  - `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatPanelTodoFinalizationTests -only-testing:SoloCodeAppTests/ChatTodoVisibilityTests CODE_SIGNING_ALLOWED=NO` -> OK
- Commit previsto:
  - `fix(chat): ignore placeholder todos and subagent policy noise`
