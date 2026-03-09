# P1 — La surface MCP visibile al modello dipende dal warmup best-effort

## Bug Fix Record
- Categoria: B
- Bug: il set di tool MCP nativi esposto al modello dipende dal warmup best-effort e da un registry globale condiviso.
- Sintomo: due request o provider possono vedere una surface tool diversa a seconda del timing del warmup o dello stato del singleton registry.
- Impatto: non-determinismo all'inizio della request, differenze tra cio' che il modello vede e cio' che il runtime puo' comunque eseguire via fallback.
- Gravita': P1
- Steps to reproduce:
  1. Avviare provider/runtime con registry freddo.
  2. Eseguire una request prima o durante il warmup MCP.
  3. Confrontare i tool esposti al modello con quelli disponibili dopo il warmup completato.
- Risultato attuale: il runtime dispatch e' robusto, ma la surface tool esposta al modello non e' garantita stabile a inizio request.
- Risultato atteso: la tool surface per request deve essere deterministica o almeno snapshot-tizzata in modo esplicito.
- Causa probabile: warmup a timeout brevi, best-effort, registry singleton usato come sorgente condivisa per provider diversi.
- Scope consentito: `MCPSessionManager`, `MCPNativeToolRegistry`, `ToolSchemaCatalog`, warmup MCP provider.
- Non-scope: riscrittura completa del runtime MCP.
- Moduli confinanti da verificare: OpenAI/Anthropic tool schema generation, cache TTL MCP, event mapper.
- Test da aggiungere o aggiornare:
  - test su request con registry freddo vs caldo
  - test multi-provider con registry condiviso
  - test che blocchi divergenze tra tool surface e dispatch runtime
- Strategia di fix minimo:
  - snapshot della tool surface per request
  - warmup sincrono controllato o marker esplicito di tool non pronti
  - ridurre dipendenza dal singleton globale
- Verifica post-fix:
  - test warmup/determinismo
  - smoke su OpenAI/Anthropic catalog parity con registry freddo e caldo
- Commit previsto: `fix(mcp): stabilize tool surface during registry warmup`
