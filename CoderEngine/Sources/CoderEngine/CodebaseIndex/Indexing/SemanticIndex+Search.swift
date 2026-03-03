import Foundation

// MARK: - SemanticIndex Search

extension SemanticIndex {
    // MARK: - Search

    /// Search code snippets by natural language and return ranked chunks.
    public func search(
        query: String,
        targetDirectories: [String] = [],
        numResults: Int = 25
    ) -> [SearchResult] {
        let queryTokens = tokenize(query)
        guard !queryTokens.isEmpty else {
            Self.logger.debug("search: empty query tokens for '\(query, privacy: .public)'")
            return []
        }

        if chunks.isEmpty {
            Self.logger.notice("search: index is empty (0 chunks), query='\(query, privacy: .public)'")
            return []
        }

        var scores: [String: Double] = [:]
        for token in Set(queryTokens) {
            guard let postingList = invertedIndex[token] else { continue }
            let df = Double(postingList.count)
            let n = Double(totalDocs)
            let idf = log((n - df + 0.5) / (df + 0.5) + 1.0)

            for chunkId in postingList {
                if !targetDirectories.isEmpty {
                    guard let chunk = chunks[chunkId],
                          targetDirectories.contains(where: { chunk.filePath.hasPrefix($0) }) else {
                        continue
                    }
                }

                let tf = Double(termFrequencies[chunkId]?[token] ?? 0)
                let dl = Double(docLengths[chunkId] ?? 1)
                let avgDl = max(avgDocLength, 1.0)
                let tfNorm = (tf * (k1 + 1)) / (tf + k1 * (1 - b + b * dl / avgDl))
                scores[chunkId, default: 0] += idf * tfNorm
            }
        }

        let queryLower = query.lowercased()
        let queryTokensLower = Set(queryTokens)
        let queryWordsLower = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }

        for (chunkId, _) in scores {
            guard let chunk = chunks[chunkId] else { continue }
            var bonus = 0.0

            for sym in chunk.symbolNames {
                let symLower = sym.lowercased()
                if symLower == queryLower {
                    bonus += 10.0
                } else if symLower.contains(queryLower) {
                    bonus += 5.0
                }
                for token in queryTokensLower where token.count >= 3 && symLower.contains(token) {
                    bonus += 1.5
                }
            }

            let scopeLower = chunk.scope.lowercased()
            for token in queryTokensLower where scopeLower.contains(token) {
                bonus += 1.0
            }

            let fileNameLower = (chunk.filePath as NSString).lastPathComponent.lowercased()
            let fileNameNoExt = (fileNameLower as NSString).deletingPathExtension
            for word in queryWordsLower where word.count >= 3 {
                if fileNameNoExt == word {
                    bonus += 4.0
                } else if fileNameNoExt.contains(word) {
                    bonus += 2.0
                }
            }

            let dirPath = (chunk.filePath as NSString).deletingLastPathComponent.lowercased()
            for word in queryWordsLower where word.count >= 3 && dirPath.contains(word) {
                bonus += 0.8
            }

            switch chunk.kind {
            case "class", "struct", "protocol", "enum", "interface":
                bonus += 1.0
            case "function", "method":
                bonus += 0.5
            case "property", "constant":
                bonus += 0.2
            default:
                break
            }

            let contentLower = chunk.content.lowercased()
            if contentLower.contains("///") || contentLower.contains("/**") || contentLower.contains("# ") {
                bonus += 0.3
            }

            scores[chunkId] = (scores[chunkId] ?? 0) + bonus
        }

        let ranked = scores
            .sorted { $0.value > $1.value }
            .prefix(numResults)
            .compactMap { (chunkId, score) -> SearchResult? in
                guard let chunk = chunks[chunkId] else { return nil }
                return SearchResult(chunk: chunk, score: score)
            }

        return Array(ranked)
    }

    /// Current index statistics.
    public func status() -> IndexStatus {
        IndexStatus(
            totalChunks: chunks.count,
            totalTokens: invertedIndex.count,
            totalFiles: fileToChunks.count,
            avgDocLength: avgDocLength,
            simHash: currentSimHash,
            hasMerkleTree: merkleRoot != nil
        )
    }

    // MARK: - Tokenization

    func tokenize(_ text: String) -> [String] {
        Self.tokenizeStatic(text)
    }

    nonisolated static func tokenizeStatic(_ text: String) -> [String] {
        var tokens: [String] = []

        let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }

        for word in words {
            let lower = word.lowercased()
            tokens.append(lower)

            // Porter stemming — normalizes inflected forms (authenticating → authent)
            let stemmed = PorterStemmer.stem(lower)
            if stemmed != lower && stemmed.count >= 2 {
                tokens.append(stemmed)
            }

            let camelSplit = splitCamelCase(word)
                .map { $0.lowercased() }
                .filter { $0.count >= 2 }
            if camelSplit.count > 1 {
                tokens.append(contentsOf: camelSplit)
                // Stem each camelCase part too
                for part in camelSplit {
                    let partStemmed = PorterStemmer.stem(part)
                    if partStemmed != part && partStemmed.count >= 2 {
                        tokens.append(partStemmed)
                    }
                }
            }
        }

        let filtered = tokens.filter { !stopWords.contains($0) }
        var expanded = filtered
        for token in filtered where expanded.count < 3000 {
            if let syns = synonymMap[token] {
                expanded.append(contentsOf: syns.prefix(2))
            }
        }

        return expanded
    }

    private static func splitCamelCase(_ word: String) -> [String] {
        var parts: [String] = []
        var current = ""
        for char in word {
            if char.isUppercase && !current.isEmpty {
                parts.append(current)
                current = String(char)
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }

    private static let stopWords: Set<String> = [
        "the", "is", "at", "in", "of", "to", "for", "and", "or", "not",
        "this", "that", "with", "from", "by", "on", "an", "be", "as",
        "it", "if", "do", "does", "did", "has", "have", "had", "was",
        "were", "are", "am", "been", "being", "where", "when", "how",
        "what", "which", "who", "whom", "whose", "why",
        "var", "let", "val", "const", "int", "string", "bool", "void",
        "return", "import", "public", "private", "internal", "static",
    ]

    private static let synonymMap: [String: [String]] = [
        // --- Authentication & Security ---
        "auth": ["authentication", "login", "signin", "credential"],
        "authentication": ["auth", "login", "signin"],
        "authorize": ["auth", "authentication", "permission"],
        "authorization": ["auth", "authorize", "permission"],
        "login": ["auth", "signin", "authenticate"],
        "signin": ["login", "auth", "authenticate"],
        "signup": ["register", "createaccount", "onboard"],
        "register": ["signup", "enroll", "createaccount"],
        "logout": ["signout", "deauthenticate", "session"],
        "password": ["credential", "secret", "passphrase"],
        "token": ["jwt", "session", "credential", "bearer"],
        "session": ["token", "cookie", "auth"],
        "permission": ["role", "access", "authorize", "acl"],
        "encrypt": ["cipher", "hash", "secure", "protect"],
        "decrypt": ["decipher", "decode", "unlock"],

        // --- Data Persistence ---
        "save": ["persist", "store", "write", "serialize"],
        "persist": ["save", "store", "write"],
        "load": ["fetch", "read", "deserialize", "parse"],
        "fetch": ["load", "get", "retrieve", "request"],
        "read": ["load", "get", "fetch", "parse"],
        "write": ["save", "persist", "store", "output"],
        "serialize": ["encode", "marshal", "stringify"],
        "deserialize": ["decode", "unmarshal", "parse"],
        "database": ["db", "storage", "persistence", "repository"],
        "db": ["database", "storage", "datastore"],
        "query": ["search", "find", "filter", "select"],
        "migration": ["schema", "upgrade", "evolve"],
        "transaction": ["commit", "rollback", "atomic"],

        // --- CRUD Operations ---
        "create": ["insert", "add", "new", "make"],
        "update": ["modify", "edit", "patch", "change"],
        "delete": ["remove", "destroy", "cleanup", "purge"],
        "remove": ["delete", "destroy", "cleanup"],
        "insert": ["add", "create", "append", "push"],
        "find": ["search", "query", "lookup", "locate"],
        "search": ["find", "query", "filter", "grep"],
        "filter": ["where", "predicate", "search", "select"],
        "sort": ["order", "rank", "arrange", "compare"],

        // --- Error Handling ---
        "error": ["exception", "failure", "fault", "crash"],
        "exception": ["error", "failure", "throw"],
        "crash": ["abort", "fatal", "panic", "terminate"],
        "retry": ["attempt", "recover", "backoff"],
        "fallback": ["default", "recover", "alternative"],
        "throw": ["raise", "emit", "error"],
        "catch": ["handle", "recover", "rescue"],
        "log": ["print", "debug", "trace", "output"],
        "debug": ["log", "trace", "inspect", "diagnose"],

        // --- Architecture & Patterns ---
        "handle": ["manage", "process", "dispatch"],
        "handler": ["controller", "manager", "processor"],
        "controller": ["handler", "presenter", "coordinator"],
        "service": ["provider", "manager", "helper"],
        "repository": ["store", "dao", "gateway", "datasource"],
        "factory": ["builder", "creator", "constructor"],
        "observer": ["listener", "subscriber", "watcher"],
        "delegate": ["callback", "handler", "protocol"],
        "middleware": ["interceptor", "filter", "plugin"],
        "singleton": ["shared", "instance", "global"],
        "protocol": ["interface", "contract", "trait"],
        "extension": ["category", "mixin", "augment"],

        // --- Configuration ---
        "config": ["configuration", "settings", "preferences"],
        "configuration": ["config", "settings", "options"],
        "environment": ["env", "config", "context"],
        "env": ["environment", "config", "variable"],

        // --- Testing ---
        "test": ["spec", "assert", "expect", "verify"],
        "mock": ["stub", "fake", "double", "spy"],
        "fixture": ["testdata", "sample", "seed"],
        "assert": ["expect", "verify", "check"],

        // --- Networking ---
        "network": ["http", "api", "request", "response"],
        "api": ["endpoint", "route", "network", "rest"],
        "request": ["call", "invoke", "fetch", "http"],
        "response": ["reply", "result", "output"],
        "websocket": ["socket", "realtime", "stream"],
        "upload": ["send", "transmit", "push"],
        "download": ["fetch", "pull", "receive"],
        "url": ["link", "endpoint", "uri", "path"],

        // --- UI & Presentation ---
        "view": ["screen", "page", "component", "layout"],
        "render": ["display", "draw", "show", "present"],
        "layout": ["arrange", "position", "frame", "stack"],
        "animate": ["transition", "motion", "effect"],
        "modal": ["dialog", "sheet", "popup", "alert"],
        "button": ["action", "tap", "control", "trigger"],
        "click": ["tap", "press", "trigger", "activate"],
        "input": ["field", "textfield", "form", "entry"],
        "list": ["table", "collection", "grid", "array"],
        "image": ["photo", "icon", "asset", "picture"],
        "color": ["theme", "palette", "tint", "style"],
        "font": ["typography", "text", "typeface"],

        // --- Data Modeling ---
        "data": ["model", "entity", "schema", "record"],
        "model": ["data", "entity", "schema", "struct"],
        "entity": ["model", "object", "record", "row"],
        "schema": ["model", "structure", "definition"],
        "enum": ["type", "case", "variant", "option"],

        // --- Navigation ---
        "navigate": ["route", "redirect", "go", "push"],
        "route": ["navigate", "path", "endpoint", "url"],
        "push": ["navigate", "present", "show"],
        "pop": ["dismiss", "back", "close"],
        "tab": ["segment", "page", "section"],

        // --- Caching & Performance ---
        "cache": ["memo", "memoize", "buffer", "store"],
        "validate": ["check", "verify", "assert", "ensure"],
        "optimize": ["performance", "speed", "improve"],
        "lazy": ["deferred", "ondemand", "delayed"],
        "async": ["concurrent", "parallel", "await"],
        "sync": ["synchronous", "blocking", "serial"],
        "queue": ["dispatch", "channel", "buffer"],
        "thread": ["concurrent", "parallel", "worker"],

        // --- User & Account ---
        "user": ["account", "profile", "member"],
        "submit": ["send", "post", "confirm", "complete"],
        "notification": ["alert", "push", "message", "toast"],
        "email": ["mail", "message", "send"],
        "file": ["document", "resource", "asset"],
        "settings": ["preferences", "config", "options"],
        "onboard": ["welcome", "setup", "tutorial"],
    ]
}
