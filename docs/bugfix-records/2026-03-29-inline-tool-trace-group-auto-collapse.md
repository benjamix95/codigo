# Bug Fix Record — 2026-03-29 — Gruppi trace inline non compressi a completamento

- **Categoria:** B — Importante
- **Bug:** i gruppi di trace inline con chevron (`Esplorazione effettuata`, `Terminale in background`, `Modifiche applicate`) restavano aperti anche dopo il completamento delle operazioni.
- **Sintomo:** la timeline del messaggio rimane lunga e rumorosa; quando un turno accumula più gruppi completati, la chat perde leggibilità.
- **Impatto:** degrado UX nella lettura della conversazione; aumenta il rumore visivo proprio a task concluso.
- **Gravità:** P2
- **Steps to reproduce:**
  1. Avvia un turno che generi almeno un gruppo di tool inline con più eventi.
  2. Attendi che il gruppo termini o che il messaggio esca dallo stato `isStreaming`.
  3. Osserva il gruppo nella timeline della chat.
- **Risultato attuale:** il gruppo resta espanso di default e occupa spazio anche a completamento avvenuto.
- **Risultato atteso:** il gruppo deve auto-collassarsi quando non ha più eventi effettivamente running; l’utente può comunque riaprirlo manualmente.
- **Causa probabile:** `InlineToolTraceGroupView` inizializzava `isExpanded = true` senza una policy di auto-presentation legata al ciclo running → completed del gruppo.
- **Scope consentito:** `App/SoloCodeApp/Sources/ChatView/Timeline/*`, test `Tests/SoloCodeAppTests/*` dedicati al trace inline, documentazione bug/changelog.
- **Non-scope:** layout della chat fuori dal trace inline, pannello trace completo, artifact card, refactor dei reducer timeline.
- **Moduli confinanti da verificare:** `ChatTurnView`, `ChatTurnTimelineInterleaver`, `InlineToolTraceEventView`.
- **Test da aggiungere o aggiornare:** regressione su stato iniziale dei gruppi completati, auto-collapse alla transizione running → completed, riapertura manuale dopo auto-collapse.
- **Strategia di fix minimo:** estrarre la policy di auto-collapse in un helper dedicato, inizializzare lo stato in base al gruppo effettivamente running e sincronizzarlo solo sulle transizioni di lifecycle del gruppo.
- **Verifica post-fix:** test mirati `InlineToolTraceGroupAutoPresentationTests` e `MessageToolTraceAutoPresentationTests`; verifica manuale del chevron su un turno con gruppi exploration/edit/terminal.
- **Commit previsto:** `fix(chat): auto-collapse completed inline tool groups`
