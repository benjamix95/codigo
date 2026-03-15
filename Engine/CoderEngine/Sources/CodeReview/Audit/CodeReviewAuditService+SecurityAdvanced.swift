import Foundation

extension CodeReviewAuditService {
    static func runSecurityDataflowAudit(
        scopeFiles: [String],
        workspacePath: URL
    ) -> (findings: [CodeReviewFinding], coverageAvailable: Bool, summary: String, adapters: [String], metadata: [String: String]) {
        let sourceTokens = ["request.", "params[", "query[", "input", "readline(", "stdin", "urlqueryitem", "body["]
        let sinkTokens = ["process(", "shell: true", "innerhtml", "sqlite", "raw(", "openurl(", "write(to:"]
        var findings: [CodeReviewFinding] = []

        for file in scopeFiles {
            guard !isAuditSourceFile(file),
                  let lines = loadLines(for: file, workspacePath: workspacePath) else { continue }
            for index in lines.indices {
                let windowStart = max(0, index - 5)
                let windowEnd = min(lines.count - 1, index + 5)
                let window = lines[windowStart...windowEnd].joined(separator: "\n").lowercased()
                let hasSource = sourceTokens.contains(where: { window.contains($0) })
                let hasSink = sinkTokens.contains(where: { window.contains($0) })
                guard hasSource && hasSink else { continue }
                findings.append(
                    makeFinding(
                        severity: .critical,
                        category: .security,
                        origin: .securityAuditor,
                        filePath: file,
                        lineNumber: index + 1,
                        message: "Possibile flusso input non validato verso sink sensibile.",
                        suggestedFix: "Inserisci validazione/sanitizzazione esplicita tra source e sink o sostituisci il sink con un'alternativa sicura.",
                        confidence: 0.86,
                        evidence: lines[index].trimmingCharacters(in: .whitespacesAndNewlines),
                        sourceTool: ReviewAuditToolName.securityDataflow,
                        blocking: true
                    )
                )
            }
        }

        return (
            findings,
            !scopeFiles.isEmpty,
            findings.isEmpty ? "Nessun source->sink sospetto rilevato." : "Rilevati \(findings.count) flow sospetti source->sink.",
            [],
            ["signal_type": "semantic", "verification_hint": "Conferma che source e sink appartengano allo stesso flow runtime", "promotion_gate": "strict_verified", "behavioral_impact": "potential_remote_exploit"]
        )
    }

    static func runSecurityAuthzAudit(
        scopeFiles: [String],
        workspacePath: URL
    ) -> (findings: [CodeReviewFinding], coverageAvailable: Bool, summary: String, adapters: [String], metadata: [String: String]) {
        let routeTokens = ["app.get", "app.post", "router.", "@get", "@post", "navigationdestination", "handle("]
        let authTokens = ["authorize", "auth", "permission", "role", "isadmin", "guard let user", "session"]
        var findings: [CodeReviewFinding] = []

        for file in scopeFiles {
            let lowerFile = file.lowercased()
            guard lowerFile.contains("route") || lowerFile.contains("controller") || lowerFile.contains("handler") || lowerFile.contains("view") else { continue }
            guard let lines = loadLines(for: file, workspacePath: workspacePath) else { continue }
            let lowerContent = lines.joined(separator: "\n").lowercased()
            let hasRoute = routeTokens.contains(where: { lowerContent.contains($0) })
            let hasAuth = authTokens.contains(where: { lowerContent.contains($0) })
            guard hasRoute && !hasAuth else { continue }
            findings.append(
                makeFinding(
                    severity: .warning,
                    category: .security,
                    origin: .securityAuditor,
                    filePath: file,
                    lineNumber: nil,
                    message: "Surface applicativa con handler/route senza segnali evidenti di authz.",
                    suggestedFix: "Verifica che i path sensibili siano protetti da middleware, permessi o session guards espliciti.",
                    confidence: 0.68,
                    evidence: "route-like handlers found without authz markers",
                    sourceTool: ReviewAuditToolName.securityAuthz,
                    blocking: false
                )
            )
        }

        return (
            findings,
            true,
            findings.isEmpty ? "Nessun gap di authz evidente nei file scoped." : "Rilevati \(findings.count) potenziali gap di authz.",
            [],
            ["signal_type": "semantic", "verification_hint": "Confronta i path segnalati con middleware e controlli di ruolo reali", "promotion_gate": "strict_verified"]
        )
    }

    static func runSecurityCryptoAudit(
        scopeFiles: [String],
        workspacePath: URL
    ) -> (findings: [CodeReviewFinding], coverageAvailable: Bool, summary: String, adapters: [String], metadata: [String: String]) {
        let patterns: [(String, FindingSeverity, String, String, Double)] = [
            ("md5", .warning, "Uso di MD5 rilevato.", "Sostituisci con SHA-256/512 o primitive moderne orientate allo use-case.", 0.82),
            ("sha1", .warning, "Uso di SHA1 rilevato.", "Evita SHA1 per nuove implementazioni e token security-sensitive.", 0.81),
            ("rand()", .warning, "Generatore pseudo-random non adatto a segreti o token.", "Usa generatori crittograficamente sicuri.", 0.77),
            ("arc4random", .suggestion, "Generatore random legacy rilevato.", "Valuta primitive moderne e intenzione esplicita del random usato.", 0.61),
        ]
        return patternAudit(
            scopeFiles: scopeFiles,
            workspacePath: workspacePath,
            patterns: patterns,
            category: .security,
            origin: .securityAuditor,
            sourceTool: ReviewAuditToolName.securityCrypto,
            summaryWhenEmpty: "Nessun pattern crypto debole rilevato.",
            summaryWhenNonEmpty: "Rilevati pattern crypto deboli o legacy."
        )
    }

    static func runSecurityDeserializationAudit(
        scopeFiles: [String],
        workspacePath: URL
    ) -> (findings: [CodeReviewFinding], coverageAvailable: Bool, summary: String, adapters: [String], metadata: [String: String]) {
        let patterns: [(String, FindingSeverity, String, String, Double)] = [
            ("pickle.load", .critical, "Deserializzazione Python non sicura.", "Usa formati sicuri o valida rigorosamente la sorgente prima del decode.", 0.91),
            ("yaml.load(", .warning, "Parsing YAML potenzialmente non sicuro.", "Preferisci safe_load o equivalente sicuro.", 0.83),
            ("nskeyedunarchiver.unarchiveobject", .warning, "Deserializzazione Objective-C/Swift legacy rilevata.", "Richiedi secure coding e valida il payload.", 0.80),
            ("eval(", .critical, "Valutazione dinamica di codice rilevata.", "Elimina eval o isola rigidamente l'input e l'ambiente.", 0.94),
        ]
        return patternAudit(
            scopeFiles: scopeFiles,
            workspacePath: workspacePath,
            patterns: patterns,
            category: .security,
            origin: .securityAuditor,
            sourceTool: ReviewAuditToolName.securityDeserialization,
            summaryWhenEmpty: "Nessun pattern di deserializzazione pericolosa rilevato.",
            summaryWhenNonEmpty: "Rilevati pattern di parsing/deserializzazione da verificare."
        )
    }

    static func runSecuritySurfaceAudit(
        scopeFiles: [String],
        workspacePath: URL
    ) -> (findings: [CodeReviewFinding], coverageAvailable: Bool, summary: String, adapters: [String], metadata: [String: String]) {
        let patterns: [(String, FindingSeverity, String, String, Double)] = [
            ("nsallowsarbitraryloads", .warning, "ATS rilassato nel progetto.", "Riduci l'eccezione ATS al minimo indispensabile e documenta il motivo.", 0.73),
            ("wkwebview", .suggestion, "Surface WebView presente: controlla navigation policy, script injection e origin isolation.", "Verifica sandbox, navigation delegate e contenuti caricati.", 0.60),
            ("debug = true", .suggestion, "Flag di debug abilitato nel codice scoped.", "Verifica che i flag di debug non siano attivi nei build di produzione.", 0.58),
        ]
        return patternAudit(
            scopeFiles: scopeFiles,
            workspacePath: workspacePath,
            patterns: patterns,
            category: .security,
            origin: .securityAuditor,
            sourceTool: ReviewAuditToolName.securitySurface,
            summaryWhenEmpty: "Nessuna configurazione di surface ad alto rischio rilevata.",
            summaryWhenNonEmpty: "Rilevati segnali di attack surface da rivedere."
        )
    }

    static func runSecuritySupplyChainAudit(
        scopeFiles: [String],
        workspacePath: URL
    ) -> (findings: [CodeReviewFinding], coverageAvailable: Bool, summary: String, adapters: [String], metadata: [String: String]) {
        let dependency = runSecurityDependenciesAudit(workspacePath: workspacePath)
        var findings = dependency.findings
        var adaptersUsed: [String] = []

        let osv = runOptionalAdapter(name: "osv-scanner", arguments: ["--recursive", "."], workspacePath: workspacePath, timeoutSeconds: 14)
        if osv.available { adaptersUsed.append(osv.name) }
        if let finding = parseAdapterHint(
            osv,
            matchers: ["vulnerabilities", "severity", "id"],
            findingMessage: "osv-scanner ha rilevato advisory potenzialmente rilevanti nella supply chain.",
            filePath: "osv-scanner"
        ) {
            findings.append(finding)
        }

        return (
            deduplicate(findings),
            dependency.coverageAvailable || !adaptersUsed.isEmpty || !scopeFiles.isEmpty,
            findings.isEmpty ? "Nessuna anomalia supply-chain rilevata." : "Rilevate \(findings.count) anomalie supply-chain/dependency.",
            adaptersUsed,
            ["signal_type": "pattern", "verification_hint": "Conferma advisory, reachability e lockfile effettivo prima della promozione", "promotion_gate": "strict_verified", "behavioral_impact": "runtime_dependency_risk"]
        )
    }

    static func runSecurityDependenciesAudit(
        workspacePath: URL
    ) -> (findings: [CodeReviewFinding], coverageAvailable: Bool, summary: String) {
        let managers: [(manifest: String, arguments: [String], label: String)] = [
            ("package-lock.json", ["audit", "--json"], "npm"),
            ("pnpm-lock.yaml", ["audit", "--json"], "pnpm"),
            ("yarn.lock", ["audit", "--json"], "yarn"),
        ]

        for manager in managers {
            let manifestURL = workspacePath.appendingPathComponent(manager.manifest)
            guard FileManager.default.fileExists(atPath: manifestURL.path) else { continue }
            guard let result = commandOutput(
                executable: "/usr/bin/env",
                arguments: [manager.label] + manager.arguments,
                currentDirectoryURL: workspacePath
            ) else {
                return ([], false, "Failed to run \(manager.label) dependency audit.")
            }
            return parseDependencyAuditOutput(
                result.output,
                manager: manager.label,
                status: result.status
            )
        }

        return ([], false, "No supported dependency manifest found for security dependency audit.")
    }

    private static func parseDependencyAuditOutput(
        _ output: String,
        manager: String,
        status: Int32
    ) -> (findings: [CodeReviewFinding], coverageAvailable: Bool, summary: String) {
        let lower = output.lowercased()
        let critical = lower.contains("\"critical\":") && !lower.contains("\"critical\":0")
        let high = lower.contains("\"high\":") && !lower.contains("\"high\":0")
        guard critical || high || status != 0 else {
            return ([], true, "No blocking dependency vulnerabilities reported by \(manager) audit.")
        }

        let severity: FindingSeverity = critical ? .critical : .warning
        let finding = makeFinding(
            severity: severity,
            category: .security,
            origin: .securityAuditor,
            filePath: "\(manager)-dependency-audit",
            lineNumber: nil,
            message: "\(manager) audit reported vulnerable dependencies.",
            suggestedFix: "Review the dependency audit report, update or replace vulnerable packages, and re-run the audit.",
            confidence: critical ? 0.92 : 0.80,
            evidence: String(output.prefix(400)),
            sourceTool: ReviewAuditToolName.securityDependencies,
            blocking: critical
        )
        return ([finding], true, "Dependency audit reported vulnerabilities for \(manager).")
    }

    private static func patternAudit(
        scopeFiles: [String],
        workspacePath: URL,
        patterns: [(needle: String, severity: FindingSeverity, message: String, remediation: String, confidence: Double)],
        category: FindingCategory,
        origin: FindingOrigin,
        sourceTool: String,
        summaryWhenEmpty: String,
        summaryWhenNonEmpty: String
    ) -> (findings: [CodeReviewFinding], coverageAvailable: Bool, summary: String, adapters: [String], metadata: [String: String]) {
        var findings: [CodeReviewFinding] = []
        for file in scopeFiles {
            guard !isAuditSourceFile(file),
                  let lines = loadLines(for: file, workspacePath: workspacePath) else { continue }
            for (index, line) in lines.enumerated() {
                let lower = line.lowercased()
                for pattern in patterns where lower.contains(pattern.needle.lowercased()) {
                    findings.append(
                        makeFinding(
                            severity: pattern.severity,
                            category: category,
                            origin: origin,
                            filePath: file,
                            lineNumber: index + 1,
                            message: pattern.message,
                            suggestedFix: pattern.remediation,
                            confidence: pattern.confidence,
                            evidence: line.trimmingCharacters(in: .whitespacesAndNewlines),
                            sourceTool: sourceTool,
                            blocking: pattern.severity == .critical
                        )
                    )
                }
            }
        }
        return (
            deduplicate(findings),
            !scopeFiles.isEmpty,
            findings.isEmpty ? summaryWhenEmpty : summaryWhenNonEmpty,
            [],
            ["signal_type": "pattern", "verification_hint": "Conferma il contesto runtime attorno alla riga segnalata", "promotion_gate": "strict_verified"]
        )
    }
}
