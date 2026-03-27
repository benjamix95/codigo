# Debug User Opt-In Enforcement — 2026-03-27

## Bug Fix Record
- Categoria: A
- Bug: l'agente poteva attivare la UX debug della chat senza opt-in esplicito dell'utente.
- Sintomo:
  - eventi `activate_debug_mode` potevano aprire il debug panel
  - alcuni percorsi runtime forzavano `coderMode = .debug` e `showDebugPanel = true`
  - potevano comparire activity o segnali con lessico debug anche senza toggle utente attivo
- Impatto:
  - violazione del controllo utente sulla modalità debug
  - ingresso non autorizzato nel workflow debug
  - rumore UI con terminologia debug quando la sessione era in realtà agent normale
- Gravità: alta
- Steps to reproduce:
  1. lasciare il toggle debug disattivato
  2. far emettere al runtime `activate_debug_mode` o altri eventi debug
  3. osservare apertura del panel, cambio modalità o activity debug
- Risultato attuale:
  - il runtime poteva auto-entrare in debug anche senza toggle utente
- Risultato atteso:
  - solo il toggle utente abilita davvero la modalità debug
  - senza toggle attivo, nessun auto-open, nessun auto-switch in `.debug`, nessuna projection/debug activity visibile
- Causa probabile:
  - assenza di un gate centralizzato sull'opt-in utente
  - routing/debug projection trattati come sempre validi lato UI
  - policy prompt ancora permissiva su `activate_debug_mode`
- Scope consentito:
  - lifecycle chat/debug
  - routing e projection eventi debug
  - policy prompt
  - test di regressione
- Non-scope:
  - refactor della pipeline debug
  - cambi ai tool MCP canonical
  - redesign del toggle UI
- Moduli confinanti da verificare:
  - `ChatPanelView+LifecycleModifiers`
  - `ChatPanelView+PartP_DebugRouting`
  - `ChatPanelView+PartI_RuntimeHelpers`
  - `ChatPanelView+DebugPipelineIntents`
  - `EventNormalizerDebug`
- Test da aggiungere o aggiornare:
  - helper opt-in debug
  - policy prompt sul divieto di auto-activation
- Strategia di fix minimo:
  - introdurre helper centrale `DebugUserOptInPolicy`
  - usare il gate in auto-activation, projection routing, mode sync e pipeline debug
  - sopprimere l'activity user-facing di `activate_debug_mode`
- Verifica post-fix:
  - `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/DebugUserOptInPolicyTests -only-testing:CoderEngineTests/SystemPromptsTests`
- Commit previsto:
  - fix(debug): require user toggle before any debug UI activation

## Bugs trovati

### P1 — Auto-attivazione debug senza consenso utente
- il runtime poteva aprire il panel debug o entrare in `.debug` su eventi agent-driven.
- Fix: gate hard su `debugToggleEnabled` per activation, routing ed esecuzione pipeline.

### P1 — Lessico debug visibile senza opt-in
- activity ed eventi potevano esporre etichette debug anche con toggle spento.
- Fix: soppressione delle task activity debug quando il toggle è off e rimozione dell'activity di `activate_debug_mode`.

### P2 — Policy prompt troppo permissiva
- il prompt di sistema continuava a presentare `activate_debug_mode` come auto-attivazione possibile.
- Fix: policy aggiornata per vietare l'auto-activation finché il toggle non è già stato attivato manualmente dall'utente.
