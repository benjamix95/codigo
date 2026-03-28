# Bug Fix Record — 2026-03-29 — File edit inline nascosti dentro i gruppi tool

- **Categoria:** B — Importante
- **Bug:** i file modificati nella timeline chat finivano dentro il gruppo collassabile dei tool, quindi scomparivano quando l'utente chiudeva la sezione.
- **Sintomo:** dopo avere collassato un gruppo con chevron, le modifiche applicate non restavano più visibili nella timeline del turno.
- **Impatto:** perdita di contesto operativo; l'utente non vede subito quali file sono stati toccati senza riaprire ogni gruppo.
- **Gravità:** P2
- **Steps to reproduce:**
  1. Avvia un turno che faccia letture/search e poi una o più modifiche file.
  2. Osserva la timeline inline della chat.
  3. Collassa il gruppo tool.
- **Risultato attuale:** i file editati restano dentro la sezione collassabile e scompaiono dalla vista.
- **Risultato atteso:** i file editati devono rimanere come righe standalone visibili nella UI, anche se i gruppi `exploration` o `terminal` vengono collassati.
- **Causa probabile:** `collapsedConsecutiveToolEvents()` raggruppava anche la categoria `.edit`, trattando i file change come tool group invece che come eventi visibili.
- **Scope consentito:** `App/SoloCodeApp/Sources/ChatView/Timeline/*`, test inline trace dedicati e documentazione del fix.
- **Non-scope:** pannello trace completo, ordini sequenza Rust/store, layout generale della chat.
- **Moduli confinanti da verificare:** `ChatTurnTimelineInterleaver`, `InlineToolTraceEventView`, `ChatTurnView`.
- **Test da aggiungere o aggiornare:** regressione su grouping inline che mantenga gli edit fuori dai gruppi, e rendering del titolo standalone per file change.
- **Strategia di fix minimo:** mantenere i gruppi collassabili solo per `exploration` e `terminal`; lasciare gli edit come `.toolEvent` standalone e usare il titolo normalizzato del file change.
- **Verifica post-fix:** test mirati `ChatTimelineInlineToolGroupingTests` e `InlineToolTraceEventViewDisplayTests`; verifica manuale sulla timeline chat con mix read/edit.
- **Commit previsto:** `fix(chat): keep edited files visible outside tool groups`
