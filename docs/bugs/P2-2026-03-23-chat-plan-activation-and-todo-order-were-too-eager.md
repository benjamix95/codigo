# P2 - La chat attivava Plan troppo presto e mostrava il todo prima del primo testo assistant visibile

## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: il runtime chat poteva 1) emettere un falso errore di policy su `coderide_activate_plan_mode`, 2) promuovere subito la UI in `Plan`, 3) agganciare la todo card a uno stub assistant ancora vuoto.
- Sintomo:
  - compariva `[Policy error] Emit coderide_todo_write before using 'coderide_activate_plan_mode'.`
  - la chat entrava subito in modalita' `Plan`
  - la todo card poteva apparire prima del primo testo assistant visibile
- Impatto: UX contraddittoria e troppo aggressiva nel main chat `Agent`, con ordine percepito errato `plan/todo` rispetto alla risposta assistant.
- Gravita': P2
- Steps to reproduce:
  1. Usare `codex-cli` in `Agent` mode su una richiesta complessa/architetturale.
  2. Fare emettere `coderide_activate_plan_mode` all'inizio del turn.
  3. Osservare policy error, auto-switch a `Plan` e comparsa anticipata della todo card.
- Risultato attuale: `activate_plan_mode` veniva trattato come tool operativo soggetto a `todo_write`; il trigger `.flowStarted` apriva il plan panel; la todo card preferiva anche assistant message attivo ma ancora vuoto.
- Risultato atteso:
  - `activate_plan_mode` non deve generare `todo_first_required`
  - un'auto-attivazione plan non deve spostare subito la chat in `Plan`
  - la todo card deve comparire solo quando esiste un assistant message visibile
- Causa probabile:
  - il gate `todoPlanStartPolicyViolation` considerava anche `activate_plan_mode` come operazione normale
  - `handleAutoActivatePlanMode` chiamava `selectMode(.plan)` immediatamente
  - `resolveTodoCardAssistantMessageId` preferiva l'assistant message attivo anche se con `content` vuoto
- Scope consentito:
  - `App/SoloCodeApp/Sources/Services/ChatThread/ChatPanelSupport+Core.swift`
  - `App/SoloCodeApp/Sources/Services/ChatThread/ChatPanelSupport+UIHelpers.swift`
  - `App/SoloCodeApp/Sources/Services/Debug/ChatBindings/ChatPanelView+PartG_AutoActivation.swift`
  - `App/SoloCodeApp/Sources/ChatView/Timeline/Support/ChatPanelView+TodoCardSelection.swift`
  - test `ChatTodoVisibilityTests` e `PlanShortcutAndCommandTests`
- Non-scope:
  - prompt/model policy del provider oltre l'effetto UI locale
  - plan runtime vero e proprio (`plan_create`, `plan_request_user_input`, plan board)
  - task panel/todo store fuori dall'aggancio della card chat
- Moduli confinanti da verificare:
  - policy `todo_first_required` / `plan_after_todo_required`
  - auto-open del plan panel
  - selezione assistant message per todo card
- Test da aggiungere o aggiornare:
  - `ChatTodoVisibilityTests`
  - `PlanShortcutAndCommandTests`
- Strategia di fix minimo:
  - esentare `activate_plan_mode` / `activate_debug_mode` dal gate todo-first
  - non chiamare piu' `selectMode(.plan)` sull'auto-activation
  - non auto-aprire il plan panel su `.flowStarted`
  - non associare la todo card a un assistant stub senza contenuto visibile
- Verifica post-fix:
  - `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatTodoVisibilityTests -only-testing:SoloCodeAppTests/PlanShortcutAndCommandTests CODE_SIGNING_ALLOWED=NO` -> OK
- Commit previsto:
  - `fix(chat): delay todo card and stop eager plan activation`
