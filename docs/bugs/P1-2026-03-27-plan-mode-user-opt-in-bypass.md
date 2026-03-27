# P1 — Plan mode attivabile senza opt-in esplicito dell'utente

## Bug Fix Record
- Categoria: B — Importante ma non bloccante
- Bug: la chat poteva entrare in `plan mode` senza consenso esplicito dell'utente tramite toggle, tramite alias tool, keyword `/plan`, shortcut tastiera e auto-open del panel su eventi plan.
- Sintomo: il plan panel o il runtime plan si attivavano anche con toggle plan spento.
- Impatto: violazione del modello di consenso esplicito gia' adottato per debug e code review; rischio di cambiare workflow, prompt e provider senza richiesta esplicita dell'utente.
- Gravita': P1
- Steps to reproduce:
  1. Lasciare il toggle plan disattivato.
  2. Inviare un input con `/plan ...` oppure generare `activate_plan_mode` / `ask_user_question`.
  3. Osservare attivazione plan o apertura automatica del panel.
- Risultato attuale: keyword, alias e auto-open potevano far scattare il plan senza toggle utente.
- Risultato atteso: il plan si attiva solo se l'utente abilita manualmente il toggle plan; in assenza di toggle qualsiasi trigger automatico deve fallire chiuso.
- Causa probabile: confermata. Esistevano piu' path indipendenti che consideravano sufficiente un trigger testuale o un evento raw per forzare `planToggleEnabled`, routing plan o apertura del panel.
- Scope consentito:
  - policy prompt plan
  - alias canonical tool registry / normalizzazione tool
  - helper plan composer/shortcut
  - gate UI di auto-attivazione e auto-open panel
  - test di regressione correlati
- Non-scope:
  - redesign del plan panel
  - refactor del runtime plan
  - modifica dei flussi manuali basati sul toggle utente
- Moduli confinanti da verificare:
  - toggle plan manuale
  - flow automatici plan che aprono il panel solo dopo opt-in
  - mapping MCP `coderide_activate_plan_mode`
  - debug e code review opt-in gia' esistenti
- Test da aggiungere o aggiornare:
  - parser `/plan` non auto-attivante
  - shortcut tastiera plan disabilitate come trigger impliciti
  - auto-open plan panel bloccato senza toggle
  - alias `ask_user_question` non piu' rimappata a `activate_plan_mode`
- Strategia di fix minimo:
  - rimuovere alias/keyword di auto-attivazione
  - rendere `activate_plan_mode` fail-closed senza toggle
  - bloccare auto-open plan panel se il toggle non e' gia' attivo
  - mantenere invariati i flussi manuali basati sul toggle
- Verifica post-fix:
  - test unitari mirati su parser/composer plan
  - test mapper tool alias
  - test open-state del plan panel automatico/manuale
- Commit previsto:
  - `fix(plan): require explicit user toggle before entering plan mode`
