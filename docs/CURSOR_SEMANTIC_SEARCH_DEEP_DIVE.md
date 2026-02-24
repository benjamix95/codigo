# Deep Dive: Componenti della Semantic Search di Cursor

Approfondimento su Merkle tree, chunking AST e SimHash — con riferimenti e citazioni.

---

## 1. Merkle Tree

### Cos’è

Un **Merkle tree** (o hash tree) è una struttura ad albero in cui:
- ogni **foglia** è l’hash crittografico di un blocco di dati
- ogni **nodo interno** è l’hash della concatenazione degli hash dei figli
- la **radice** (root hash) è il commitment crittografico dell’intero dataset

> *"A hash tree allows efficient and secure verification of the contents of a large data structure. Demonstrating that a leaf node is part of a given binary hash tree requires computing a number of hashes proportional to the logarithm of the number of leaf nodes."*  
> — [Merkle tree, Wikipedia](https://en.wikipedia.org/wiki/Merkle_tree)

### Struttura

```
        [root hash]
       /           \
  [hash 0]      [hash 1]
  /     \        /     \
H(L1)  H(L2)   H(L3)  H(L4)   ← foglie = hash dei file
```

- **SHA-256** usato di solito per gli hash
- Alberi tipicamente binari, ma possibile usare più figli per nodo
- Concatenazione: `hash(parent) = H(hash(child0) + hash(child1))`

### Uso in Cursor

1. **Merkle tree locale:** per ogni file e cartella viene calcolato un hash
2. **Sync con il server:** confronto del root hash e dei branch per trovare differenze
3. **Propagazione:** se un file cambia, si ricalcolano solo hash dalla foglia fino alla radice
4. **Aggiornamenti incrementali:** ogni ~10 minuti solo i file modificati vengono inviati

> *"Small client-side edits change only the hashes of the edited file itself and the hashes of the parent directories up to the root of the codebase. Cursor compares those hashes to the server's version to see exactly where the two Merkle trees diverge."*  
> — [Securely indexing large codebases, Cursor Blog](https://cursor.com/blog/secure-codebase-indexing)

### Complessità

- **Update:** O(log n) per ricalcolare gli hash lungo il percorso foglia→radice
- **Verifica:** O(log n) hash per dimostrare che un blocco appartiene all’albero
- **Sync:** si percorrono solo i branch in cui gli hash differiscono

### Esempi di utilizzo

- Git, Bitcoin, Ethereum, IPFS
- Cassandra, Riak, Dynamo (anti-entropy)
- ZFS, BitTorrent, Certificate Transparency

### Citazioni chiave

| Fonte | Contenuto |
|-------|-----------|
| [Cursor Blog](https://cursor.com/blog/secure-codebase-indexing) | Merkle tree per change detection e sync incrementale |
| [Engineer's Codex](https://read.engineerscodex.com/p/how-cursor-indexes-codebases-fast) | Handshake, root hash, sync ogni 10 minuti |
| [Wikipedia](https://en.wikipedia.org/wiki/Merkle_tree) | Struttura e proprietà crittografiche |

---

## 2. Chunking basato su AST

### Problema

Lo split basato su caratteri o righe tende a tagliare codice a metà funzioni/classi e genera chunk poco significativi.

> *"When you split Python at 500 characters, you end up with chunks like: `def calculate_total(items): ... subtotal += item.price * item.qu` — Congratulations, you just cut a function in half. The embedding for this chunk has no idea what `qu` is."*  
> — [Building code-chunk: AST Aware Code Chunking, Supermemory](https://supermemory.ai/blog/building-code-chunk-ast-aware-code-chunking/)

### Idea: cAST (CMU)

1. **Chunk ai confini semantici** — funzioni, classi, metodi
2. **AST** — usare la struttura ad albero per trovare split naturali
3. **Split ricorsivo + merge** — spezzare nodi grandi, unire fratelli piccoli rispettando il limite di token

> *"Existing line-based chunking heuristics often break semantic structures, splitting functions or merging unrelated code. We propose chunking via Abstract Syntax Trees (cAST), a structure-aware method that recursively breaks large AST nodes into smaller chunks and merges sibling nodes while respecting size limits."*  
> — [cAST: Enhancing Code Retrieval-Augmented Generation, arXiv:2506.15655](https://arxiv.org/abs/2506.15655)

### Metriche (paper cAST)

- **Recall@5:** +4.3 punti su RepoEval
- **Pass@1:** +2.67 punti su SWE-bench

### Passi operativi (tree-sitter)

1. **Parsing:** tree-sitter costruisce l’AST per molti linguaggi
2. **Estrazione di entità:** funzioni, classi, metodi, interfacce, import
3. **Scope tree:** gerarchia (es. `UserService > getUser`)
4. **Greedy window assignment:** riempire finestre di nodi sintattici senza superare il limite
5. **Merge:** unire finestre adiacenti piccole
6. **Contextualized text:** arricchire ogni chunk con scope, firme, dipendenze

### Algoritmo (pseudocodice)

```
for each AST node:
  if node fits in current window:
    add to window
  else if node too big:
    yield current window
    recurse into children
  else:
    yield current window
    start new window with node
```

### Metriche di grandezza

- Non righe, ma **caratteri non-whitespace** (per ridurre l’impatto di commenti/vuoti)

### Contextualized text (esempio Supermemory)

```
# src/services/user.ts
# Scope: UserService
# Defines: async getUser(id: string): Promise<User>
# Uses: Database
# After: constructor

  async getUser(id: string): Promise<User> {
    return this.db.query('SELECT * FROM users WHERE id = ?', [id])
  }
```

### Citazioni chiave

| Fonte | Contenuto |
|-------|-----------|
| [cAST, arXiv:2506.15655](https://arxiv.org/abs/2506.15655) | Metodo, risultati, split ricorsivo |
| [Supermemory code-chunk](https://supermemory.ai/blog/building-code-chunk-ast-aware-code-chunking/) | Implementazione con tree-sitter, scope tree, contextualized text |
| [Engineer's Codex](https://read.engineerscodex.com/p/how-cursor-indexes-codebases-fast) | Chunk sintattici, AST, tree-sitter |

---

## 3. SimHash

### Cos’è

**SimHash** è un hash **locality-sensitive**: documenti simili producono hash simili. Creato da Moses Charikar; usato da Google per near-duplicate detection nel web crawling.

> *"SimHash is a technique for quickly estimating how similar two sets are. The algorithm is used by the Google Crawler to find near duplicate pages."*  
> — [SimHash, Wikipedia](https://en.wikipedia.org/wiki/SimHash)

### Differenza rispetto agli hash crittografici

| Hash crittografico (MD5, SHA) | SimHash |
|-------------------------------|---------|
| Un bit diverso → hash totalmente diverso | Input simili → hash simili |
| Uso: integrità, firma | Uso: similarità, near-duplicate detection |

### Algoritmo (schema)

1. **Tokenizzazione:** parole o k-shingles (es. 3 parole consecutive)
2. **Per ogni token:** hash con MurmurHash (o simile) → vettore f-dimensionale
3. **Voto per bit:** ogni bit “vota” +1 o -1 in base al valore dell’hash
4. **SimHash finale:** se la somma per la posizione i > 0 → bit i = 1, altrimenti 0

```
Per ogni token t:
  hash = murmurhash(t)
  per ogni bit i in 0..63:
    vector[i] += (hash[i] == 1) ? +1 : -1

simhash = 0
per ogni i: se vector[i] > 0 → simhash |= (1 << i)
```

### Hamming distance

Numero di bit diversi tra due SimHash:

```
hamming_distance(h1, h2) = popcount(h1 XOR h2)
```

- **0–3 bit diversi** (~95%+ similarità): contenuto quasi identico
- **4–8 bit diversi** (~85–95%): near-duplicate
- **9+ bit diversi** (<85%): contenuto diverso

> *"Near-duplicate documents produce fingerprints that differ in only a small number of bit positions."*  
> — [Google: Detecting near-duplicates for web crawling](https://static.googleusercontent.com/media/research.google.com/en//pubs/archive/33026.pdf)

### Uso in Cursor

1. **Derivazione dal Merkle tree:** simhash come “impronta” del codebase
2. **Vector DB:** cerca indici con simhash simili nello stesso team
3. **Soglia di similarità:** ~92% tra codebase dello stesso org
4. **Reuse:** nuovo utente può copiare l’indice del teammate invece di ricostruirlo

> *"The client computes the Merkle tree for a new codebase and derives a value called a similarity hash (simhash) from that tree... The server then uses it as a vector to search in a vector database composed of all the other current simhashes... If it does [match above threshold], we use that index as the initial index for the new codebase."*  
> — [Securely indexing large codebases, Cursor Blog](https://cursor.com/blog/secure-codebase-indexing)

### Esempi applicativi

- Web crawling e deduplica
- Spam detection
- FLoC (Google)
- Caching basato su contenuto

### Citazioni chiave

| Fonte | Contenuto |
|-------|-----------|
| [Cursor Blog](https://cursor.com/blog/secure-codebase-indexing) | Simhash per reuse indici, team, soglie |
| [Wikipedia SimHash](https://en.wikipedia.org/wiki/SimHash) | Definizione, Charikar, Google |
| [Naman Kumar blog](https://naman.so/blog/simhash-web-crawl-caching) | Algoritmo, vettori di voto, Hamming |
| [Google paper](https://static.googleusercontent.com/media/research.google.com/en//pubs/archive/33026.pdf) | Near-duplicate detection, metriche |

---

## Riepilogo pipeline Cursor (tutti i componenti insieme)

```
[Codebase locale]
       ↓
┌──────────────────────────────────────────────┐
│ 1. Chunking (AST/tree-sitter)                 │
│    - Split a confini semantici                │
│    - Chunk sintattici                         │
└──────────────────────────────────────────────┘
       ↓
┌──────────────────────────────────────────────┐
│ 2. Merkle Tree                                │
│    - Hash SHA-256 per file/cartella           │
│    - Sync incrementale ogni 10 min           │
│    - Simhash derivato per reuse               │
└──────────────────────────────────────────────┘
       ↓
┌──────────────────────────────────────────────┐
│ 3. Embeddings + Turbopuffer                  │
│    - Modello custom Cursor                    │
│    - Vector DB remoto                        │
│    - Path obfuscati, no storage permanente   │
└──────────────────────────────────────────────┘
       ↓
[Semantic Search] → [Agent]
```

---

## Fonti complete

- [Cursor: Improving agent with semantic search](https://cursor.com/blog/semsearch)
- [Cursor: Securely indexing large codebases](https://cursor.com/blog/secure-codebase-indexing)
- [Engineer's Codex: How Cursor Indexes Codebases Fast](https://read.engineerscodex.com/p/how-cursor-indexes-codebases-fast)
- [Supermemory: Building code-chunk, AST Aware Code Chunking](https://supermemory.ai/blog/building-code-chunk-ast-aware-code-chunking/)
- [cAST paper (arXiv:2506.15655)](https://arxiv.org/abs/2506.15655)
- [Wikipedia: Merkle tree](https://en.wikipedia.org/wiki/Merkle_tree)
- [Wikipedia: SimHash](https://en.wikipedia.org/wiki/SimHash)
- [Naman Kumar: Near-Duplicate Detection with Simhash](https://naman.so/blog/simhash-web-crawl-caching)
- [Google: Detecting near-duplicates for web crawling](https://static.googleusercontent.com/media/research.google.com/en//pubs/archive/33026.pdf)
