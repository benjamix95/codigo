## 2026-03-23 - Codex default profile auth sync

- Il profilo Codex gestito `_default` ora sincronizza `auth.json` dal profilo globale `~/.codex` quando la sorgente è valida e il target locale manca, è invalido o è più vecchio.
- Questo evita i `401 Unauthorized` nel main chat dopo il forcing di `CODEX_HOME` verso il profilo gestito dell'app.
- Aggiunto test di regressione che verifica la copia di `auth.json` nel profilo `_default`.
