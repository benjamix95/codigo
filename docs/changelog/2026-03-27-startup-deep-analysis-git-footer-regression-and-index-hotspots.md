# 2026-03-27 — Startup deep analysis: footer Git ripristinato, refresh Git staged, index bootstrap ancora piu' deferito

## Modifiche

- ripristinato il footer Git senza perdere il branch picker: `currentBranch`, `branches`, `status` e ahead/behind tornano disponibili anche fuori dal pannello Git;
- `GitPanelStore.refresh(...)` e' stato diviso in snapshot base veloce e snapshot dettagliato pesante;
- il badge Git nel footer usa subito `status.changedFiles` come fallback, senza aspettare `changedFiles`;
- i refresh Git espliciti (switch branch, task completato, refresh manuale, pannello aperto) continuano a caricare il dettaglio completo;
- i refresh passivi del footer non innescano piu' il path pesante dei file modificati;
- l'indicizzazione bootstrap del workspace parte con priorita' piu' bassa, delay iniziale piu' lungo e provisioning CI locale differito.

## Finding confermati

- il vero collo di bottiglia residuo allo startup resta `WorkspaceStore.indexActiveWorkspace() -> CodebaseIndex.indexWorkspace(...)`;
- la regressione Git non andava risolta togliendo dati al footer, ma separando `base snapshot` e `detail snapshot`;
- sidebar chat / explorer non compaiono come hotspot dominanti nel sample startup aggiornato, segno che i refactor di snapshot/cache hanno ridotto il lavoro in `body`.

## Verifica

- build macOS `Solo Code-Debug` completata con successo
- sample PID startup aggiornati raccolti in locale per confrontare:
  - path Git pesante
  - path indexing bootstrap
  - assenza di I/O explorer sync nel body tra gli hotspot evidenti
