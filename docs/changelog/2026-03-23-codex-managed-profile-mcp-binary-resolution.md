## 2026-03-23 - Codex managed profile MCP binary resolution

- Il resolver del binario `coderide-mcp-server-rust` ora considera anche i build artifact di sviluppo del repo, oltre all’override esplicito e al bundle sibling.
- Quando esistono più candidati eseguibili, viene scelto il più recente invece di lasciare path stale nel profilo Codex gestito.
- Questo evita profili `_default` con `coderide` configurato ma senza tool realmente caricabili.
