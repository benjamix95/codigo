# P1 - i provider cloud potevano degradare query umane a grep/search generico e la UI non mostrava sempre "Semantic Search"

## Bug Fix Record
- Categoria: A
- Bug: i provider cloud potevano emettere `grep`, `search` o `mcp_call -> coderide_grep` per query umane; inoltre la UI doveva preservare esplicitamente `coderide_semantic_search` come `Semantic Search`.
- Sintomo:
  - query umane lato cloud finivano su ricerca generica invece che su semantic
  - nella timeline/tool trace l'operazione poteva apparire come ricerca generica o tool MCP generico
- Impatto:
  - mancato uso obbligatorio del semantic search per tutti i provider
  - percezione UI errata del tool realmente usato
- Gravita: alta
- Steps to reproduce:
  1. Simulare una suggestion cloud `grep` o `mcp_call` con query naturale tipo `where is authentication handled`.
  2. Osservare che senza enforcement il provider poteva eseguire il tool di testo invece di `semantic_search`.
  3. Verificare la UI su payload `coderide_semantic_search`.
- Risultato attuale: semantic search non era enforced end-to-end per tutti i provider e la UI poteva non esplicitarlo chiaramente.
- Risultato atteso: per query umane, tutti i provider devono convergere su `semantic_search` o `coderide_semantic_search`; la UI deve mostrare chiaramente `Semantic Search`.
- Causa probabile:
  - enforcement mancante nel provider execution path
  - mapper eventi troppo permissivo verso `search`
  - copertura UI non sufficiente sul caso `coderide_semantic_search`
- Scope consentito:
  - `ToolEnabledLLMProvider`
  - `ProviderToolEventMapper`
  - normalizzazione/presentazione UI search
  - test provider/app
- Non-scope:
  - ranking search
  - benchmark persistence
  - motore embeddings
- Moduli confinanti da verificare:
  - tool inference + enforcement provider-side
  - event mapper semantic vs instant grep
  - EventNormalizer / ChatTurnInline presentation
- Test da aggiungere o aggiornare:
  - enforcement `grep -> semantic_search`
  - enforcement `mcp_call(coderide_grep) -> coderide_semantic_search`
  - mapper `search` naturale -> semantic
  - UI presentation/title per `coderide_semantic_search`
- Strategia di fix minimo:
  - introdurre enforcement provider-wide per query umane
  - rimappare `search` generico naturale a semantic nel mapper
  - aggiungere regression UI mirate
- Verifica post-fix:
  - `CoderEngineTests/ToolEnabledLLMProviderPolicyAckTests`
  - `CoderEngineTests/ProviderToolEventMapperTests`
  - `SoloCodeAppTests/ChatTurnInlineToolGroupRowPresentationTests`
  - `SoloCodeAppTests/EventNormalizerLiveStateTests`
- Commit previsto: `fix(search): enforce semantic search for cloud providers`
