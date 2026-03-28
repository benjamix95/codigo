import Foundation

// MARK: - Performance Audit Tools

extension CodeReviewAuditService {

    // MARK: - Bottleneck Detection

    static func runPerfBottlenecks(
        scopeFiles: [String],
        workspacePath: URL
    ) -> (
        findings: [CodeReviewFinding],
        coverageAvailable: Bool,
        summary: String,
        adapters: [String],
        metadata: [String: String]
    ) {
        var findings: [CodeReviewFinding] = []
        let patterns: [(String, FindingSeverity, String, String, Double)] = [
            ("DispatchQueue.main.sync", .critical,
             "Chiamata sincrona sulla main queue — potenziale deadlock o blocco UI.",
             "Usa DispatchQueue.main.async o sposta il lavoro fuori dal main thread.", 0.93),
            ("Thread.sleep", .warning,
             "Thread.sleep blocca il thread corrente — rallenta pipeline e UI.",
             "Usa Task.sleep o timer asincroni.", 0.85),
            ("usleep(", .warning,
             "usleep blocca il thread corrente.",
             "Sostituisci con sleep asincrono o timer.", 0.82),
            (".sorted(by:", .suggestion,
             "Ordinamento inline potenzialmente costoso su collezioni grandi.",
             "Valuta se la collezione può essere pre-ordinata o limitata.", 0.55),
            ("for _ in 0..<", .suggestion,
             "Loop con range potenzialmente ampio — verifica bounds e complessità.",
             "Assicurati che il range sia limitato e il corpo del loop leggero.", 0.50),
        ]

        for file in scopeFiles {
            guard !isAuditSourceFile(file),
                  let lines = loadLines(for: file, workspacePath: workspacePath) else { continue }
            for (lineIndex, line) in lines.enumerated() {
                let lower = line.lowercased()
                for (pattern, severity, message, fix, confidence) in patterns {
                    if lower.contains(pattern.lowercased()) {
                        findings.append(makeFinding(
                            severity: severity,
                            category: .performance,
                            origin: .auditTool,
                            filePath: file,
                            lineNumber: lineIndex + 1,
                            message: message,
                            suggestedFix: fix,
                            confidence: confidence,
                            evidence: "Pattern: \(pattern) trovato in linea \(lineIndex + 1)",
                            sourceTool: ReviewAuditToolName.perfBottlenecks
                        ))
                    }
                }
            }
        }

        let summary = findings.isEmpty
            ? "Nessun collo di bottiglia evidente rilevato."
            : "Rilevati \(findings.count) potenziali colli di bottiglia."
        return (findings, true, summary, ["pattern_scanner"], [
            "signal_type": "pattern",
            "verification_hint": "Conferma il contesto runtime prima della promozione",
            "promotion_gate": "strict_verified",
        ])
    }

    // MARK: - Memory Audit

    static func runPerfMemory(
        scopeFiles: [String],
        workspacePath: URL
    ) -> (
        findings: [CodeReviewFinding],
        coverageAvailable: Bool,
        summary: String,
        adapters: [String],
        metadata: [String: String]
    ) {
        var findings: [CodeReviewFinding] = []
        let patterns: [(String, FindingSeverity, String, String, Double)] = [
            ("strong self", .warning,
             "Cattura forte di self in closure — rischio retain cycle.",
             "Usa [weak self] o [unowned self] se il ciclo di vita è garantito.", 0.78),
            ("[unowned self]", .suggestion,
             "unowned self può causare crash se self è già deallocato.",
             "Valuta se [weak self] è più sicuro per questo contesto.", 0.65),
            ("NSCache", .info,
             "Uso di NSCache — verifica policy di eviction e dimensione massima.",
             "Configura countLimit e totalCostLimit per limitare la memoria.", 0.50),
            ("imageNamed", .suggestion,
             "UIImage(named:) usa cache di sistema che non viene rilasciata facilmente.",
             "Per immagini grandi o temporanee, usa UIImage(contentsOfFile:).", 0.60),
            ("autoreleasepool", .info,
             "Uso di autoreleasepool — buona pratica in loop pesanti.",
             "Verifica che il pool copra effettivamente l'allocazione critica.", 0.40),
        ]

        for file in scopeFiles {
            guard !isAuditSourceFile(file),
                  let lines = loadLines(for: file, workspacePath: workspacePath) else { continue }
            for (lineIndex, line) in lines.enumerated() {
                let lower = line.lowercased()
                for (pattern, severity, message, fix, confidence) in patterns {
                    if lower.contains(pattern.lowercased()) {
                        findings.append(makeFinding(
                            severity: severity,
                            category: .performance,
                            origin: .auditTool,
                            filePath: file,
                            lineNumber: lineIndex + 1,
                            message: message,
                            suggestedFix: fix,
                            confidence: confidence,
                            evidence: "Pattern: \(pattern) trovato in linea \(lineIndex + 1)",
                            sourceTool: ReviewAuditToolName.perfMemory
                        ))
                    }
                }
            }
        }

        let summary = findings.isEmpty
            ? "Nessun problema di memoria evidente rilevato."
            : "Rilevati \(findings.count) potenziali problemi di memoria."
        return (findings, true, summary, ["pattern_scanner"], [
            "signal_type": "pattern",
            "verification_hint": "Conferma retain cycle e leak con strumenti runtime (Instruments/Leaks)",
            "promotion_gate": "strict_verified",
        ])
    }

    // MARK: - UI Responsiveness

    static func runPerfUIResponsiveness(
        scopeFiles: [String],
        workspacePath: URL
    ) -> (
        findings: [CodeReviewFinding],
        coverageAvailable: Bool,
        summary: String,
        adapters: [String],
        metadata: [String: String]
    ) {
        var findings: [CodeReviewFinding] = []
        let patterns: [(String, FindingSeverity, String, String, Double)] = [
            ("DispatchQueue.main.sync", .critical,
             "Sync su main thread — blocca la UI fino al completamento.",
             "Usa async o sposta il lavoro su background queue.", 0.93),
            (".task {", .suggestion,
             "SwiftUI .task modifier — verifica che non esegua lavoro pesante inline.",
             "Sposta operazioni costose in un Task detached o background actor.", 0.55),
            ("JSONDecoder().decode", .suggestion,
             "Decodifica JSON potenzialmente pesante — può bloccare la UI se su main thread.",
             "Esegui la decodifica su background queue.", 0.60),
            ("FileManager.default", .suggestion,
             "Operazioni FileManager su main thread possono causare jank UI.",
             "Sposta le operazioni I/O su background queue.", 0.55),
            (".onAppear", .info,
             "onAppear può eseguire lavoro sul main thread — verifica complessità.",
             "Usa .task {} per lavoro asincrono in onAppear.", 0.40),
        ]

        for file in scopeFiles {
            guard !isAuditSourceFile(file),
                  let lines = loadLines(for: file, workspacePath: workspacePath) else { continue }
            for (lineIndex, line) in lines.enumerated() {
                let lower = line.lowercased()
                for (pattern, severity, message, fix, confidence) in patterns {
                    if lower.contains(pattern.lowercased()) {
                        findings.append(makeFinding(
                            severity: severity,
                            category: .performance,
                            origin: .auditTool,
                            filePath: file,
                            lineNumber: lineIndex + 1,
                            message: message,
                            suggestedFix: fix,
                            confidence: confidence,
                            evidence: "Pattern: \(pattern) trovato in linea \(lineIndex + 1)",
                            sourceTool: ReviewAuditToolName.perfUIResponsiveness
                        ))
                    }
                }
            }
        }

        let summary = findings.isEmpty
            ? "Nessun problema di responsività UI rilevato."
            : "Rilevati \(findings.count) potenziali problemi di responsività UI."
        return (findings, true, summary, ["pattern_scanner"], [
            "signal_type": "pattern",
            "verification_hint": "Verifica con Time Profiler che le operazioni siano effettivamente su main thread",
            "promotion_gate": "strict_verified",
        ])
    }

    // MARK: - Startup Performance

    static func runPerfStartup(
        scopeFiles: [String],
        workspacePath: URL
    ) -> (
        findings: [CodeReviewFinding],
        coverageAvailable: Bool,
        summary: String,
        adapters: [String],
        metadata: [String: String]
    ) {
        var findings: [CodeReviewFinding] = []
        let patterns: [(String, FindingSeverity, String, String, Double)] = [
            ("+load", .warning,
             "+load eseguito prima di main() — rallenta il tempo di avvio.",
             "Sposta l'inizializzazione in +initialize o al primo uso.", 0.88),
            ("__attribute__((constructor))", .warning,
             "Funzione constructor eseguita prima di main() — impatta startup time.",
             "Differisci l'inizializzazione al primo utilizzo.", 0.85),
            ("UIApplication.shared", .suggestion,
             "Accesso a UIApplication.shared durante init — verifica se è nel path di startup.",
             "Differisci accessi a UIApplication dopo didFinishLaunching.", 0.50),
            ("UserDefaults.standard", .info,
             "Accesso a UserDefaults durante startup può essere costoso con dati grandi.",
             "Carica solo chiavi necessarie durante l'avvio.", 0.45),
        ]

        for file in scopeFiles {
            guard !isAuditSourceFile(file),
                  let lines = loadLines(for: file, workspacePath: workspacePath) else { continue }
            for (lineIndex, line) in lines.enumerated() {
                let lower = line.lowercased()
                for (pattern, severity, message, fix, confidence) in patterns {
                    if lower.contains(pattern.lowercased()) {
                        findings.append(makeFinding(
                            severity: severity,
                            category: .performance,
                            origin: .auditTool,
                            filePath: file,
                            lineNumber: lineIndex + 1,
                            message: message,
                            suggestedFix: fix,
                            confidence: confidence,
                            evidence: "Pattern: \(pattern) trovato in linea \(lineIndex + 1)",
                            sourceTool: ReviewAuditToolName.perfStartup
                        ))
                    }
                }
            }
        }

        let summary = findings.isEmpty
            ? "Nessun problema di startup rilevato."
            : "Rilevati \(findings.count) potenziali problemi di startup time."
        return (findings, true, summary, ["pattern_scanner"], [
            "signal_type": "pattern",
            "verification_hint": "Usa Instruments App Launch per confermare l'impatto reale sullo startup",
            "promotion_gate": "strict_verified",
        ])
    }

    // MARK: - Hot Paths (file churn + complexity)

    static func runPerfHotPaths(
        scopeFiles: [String],
        workspacePath: URL
    ) -> (
        findings: [CodeReviewFinding],
        coverageAvailable: Bool,
        summary: String,
        adapters: [String],
        metadata: [String: String]
    ) {
        var findings: [CodeReviewFinding] = []

        // Incrocia file con alto churn git e alta complessità (linee)
        let churnCounts = gitHistoryFileCounts(workspacePath: workspacePath)
        let highChurnThreshold = 15

        for file in scopeFiles {
            guard !isAuditSourceFile(file),
                  let lines = loadLines(for: file, workspacePath: workspacePath) else { continue }

            let lineCount = lines.count
            let churn = churnCounts[file] ?? 0

            // File con alto churn E molte righe = hot path probabile
            if churn >= highChurnThreshold && lineCount > 300 {
                findings.append(makeFinding(
                    severity: .warning,
                    category: .performance,
                    origin: .auditTool,
                    filePath: file,
                    lineNumber: nil,
                    message: "File hot path: \(churn) commit in 90gg e \(lineCount) righe — alta probabilità di collo di bottiglia.",
                    suggestedFix: "Considera decomposizione del file e profilazione mirata con Instruments.",
                    confidence: min(0.95, 0.5 + Double(churn) / 100.0),
                    evidence: "git churn=\(churn), lines=\(lineCount)",
                    sourceTool: ReviewAuditToolName.perfHotPaths
                ))
            }

            // Cerca nested loops (indicatore di complessità O(n²+))
            var nestingLevel = 0
            for (lineIndex, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("for ") || trimmed.hasPrefix("while ") {
                    nestingLevel += 1
                    if nestingLevel >= 2 {
                        findings.append(makeFinding(
                            severity: .warning,
                            category: .performance,
                            origin: .auditTool,
                            filePath: file,
                            lineNumber: lineIndex + 1,
                            message: "Loop annidato (livello \(nestingLevel)) — complessità O(n^\(nestingLevel)) o superiore.",
                            suggestedFix: "Valuta se è possibile ridurre la complessità con strutture dati ottimizzate.",
                            confidence: 0.70,
                            evidence: "Nesting level: \(nestingLevel) a linea \(lineIndex + 1)",
                            sourceTool: ReviewAuditToolName.perfHotPaths
                        ))
                    }
                }
                if trimmed.contains("}") {
                    nestingLevel = max(0, nestingLevel - 1)
                }
            }
        }

        let summary = findings.isEmpty
            ? "Nessun hot path critico rilevato."
            : "Rilevati \(findings.count) hot path o aree ad alta complessità."
        return (findings, true, summary, ["git_churn", "complexity_scanner"], [
            "signal_type": "multi_signal",
            "verification_hint": "Profila con Time Profiler per confermare i colli di bottiglia reali",
            "promotion_gate": "strict_verified",
        ])
    }
}
