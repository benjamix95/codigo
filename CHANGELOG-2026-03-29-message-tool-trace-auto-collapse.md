# Changelog - 2026-03-29 - Message tool trace auto-collapse

## Cosa cambia
- Corretto il meccanismo di invalidazione della cache derivata in `MessageToolTraceView`.
- Il token osservato dalla view ora include un digest dell'intera lista eventi, invece di dipendere solo dal primo e dall'ultimo evento.
- Questo permette di rilevare anche i merge di completamento (`tool_finish`) che aggiornano un evento intermedio del trace.

## Bug risolto
- La sezione tool/terminale poteva restare nello stato espanso o comunque non aggiornarsi a fine esecuzione quando il completamento avveniva su un evento non finale della lista.

## Test
- Aggiunto un test di regressione che verifica il cambio di `eventsChangeToken` quando un evento intermedio passa da `started` a `completed`.

## Perimetro
- Nessuna modifica al layout della card.
- Nessuna modifica al `ToolTraceStore`.
- Nessuna modifica al reducer della timeline.
