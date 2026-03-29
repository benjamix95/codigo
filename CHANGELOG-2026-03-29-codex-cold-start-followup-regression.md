# Changelog - 2026-03-29 - Codex cold-start follow-up regression

- Aggiunto un test integrato sul loop multi-round del provider tool-enabled per il caso `MCP registry freddo -> shell discovery bloccata -> follow-up prompt corretto -> risposta finale`.
- Introdotto un helper di test che cattura i prompt round-by-round per verificare direttamente il contenuto del secondo prompt.
- La regressione verifica che il follow-up:
  - contenga il dettaglio `Workspace discovery via shell is disabled`
  - mantenga la guidance `MCP registry warm-up`
  - non ricada più nel messaggio `No MCP tools currently available`
