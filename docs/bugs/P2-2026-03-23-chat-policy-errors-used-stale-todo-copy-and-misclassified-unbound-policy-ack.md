# P2 - La chat mostrava policy error fuorvianti per todo-first e policy_ack non associato

## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: la chat emetteva due errori policy fuorvianti durante i turni agent. Il gate todo-first chiedeva esplicitamente `coderide_todo_write` anche quando il flusso usa il tool canonico `todo_write`, e gli eventi `policy_ack` senza turno/stato associato venivano trattati come acknowledgment invalidi con messaggio `Expected hash ?`.
- Sintomo:
  - compariva `[Policy error] Emit coderide_todo_write before starting real execution with 'command_execution'.`
  - compariva `[Policy error] Invalid AGENTS/SKILL acknowledgment received. Expected hash ?.` anche quando mancava un binding valido del turno, non un hash davvero errato.
- Impatto: la UI riportava istruzioni stale e falsi errori policy, interrompendo il task con messaggi non azionabili.
- Gravita': P2
- Steps to reproduce:
  1. Avviare un turno agent con enforcement attivo.
  2. Lasciare partire un `command_execution` prima di una todo iniziale.
  3. Osservare che il messaggio richiede `coderide_todo_write` invece del tool canonico `todo_write`.
  4. Far arrivare un evento `policy_ack` quando il turno o lo stato di ack non sono ancora risolti.
  5. Osservare il falso errore `Expected hash ?`.
- Risultato attuale: il copy del gate todo-first era legato al vecchio naming `coderide_*`; `handleRawStreamEvent` trattava qualunque `policy_ack` non marcato come `acknowledged` come errore invalido, inclusi i casi senza stato.
- Risultato atteso:
  - il gate todo-first deve chiedere `todo_write`
  - un `policy_ack` privo di stato valido deve essere ignorato, non classificato come hash invalido
- Causa probabile:
  - copy UI rimasto allineato al vecchio naming MCP
  - path `policy_ack` nella streaming handler con fallback troppo aggressivo: `else` invece di distinguere `invalid` da stati non risolti
- Scope consentito:
  - `App/SoloCodeApp/Sources/Services/ChatThread/ChatPanelSupport+Core.swift`
  - `App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartP_PolicyEnforcement.swift`
  - `App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartP_Streaming2.swift`
  - `Tests/SoloCodeAppTests/ChatTodoVisibilityTests.swift`
  - `Tests/SoloCodeAppTests/ChatStreamFailureHandlingTests.swift`
- Non-scope:
  - runtime provider `ToolEnabledLLMProvider`
  - criteri di gating di `command_execution`
  - formato del marker `policy_ack`
- Moduli confinanti da verificare:
  - flush della coda bloccata da `policy_ack`
  - visibilita' degli errori policy in chat lineare
- Test da aggiungere o aggiornare:
  - `ChatTodoVisibilityTests`
  - `ChatStreamFailureHandlingTests`
- Strategia di fix minimo:
  - correggere il copy del dettaglio `todo_first_required`
  - introdurre una classificazione esplicita dello status `policy_ack` e segnalare l'errore solo per status `invalid`
- Verifica post-fix:
  - test unitari mirati sulle due regressioni
- Commit previsto:
  - `fix(chat): align policy errors with native todo and ack binding`
