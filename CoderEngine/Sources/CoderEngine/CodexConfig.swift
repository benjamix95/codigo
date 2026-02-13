import Foundation

/// Config letta da ~/.codex/config.toml (model, sandbox_mode, model_reasoning_effort)
public struct CodexConfig: Sendable {
    public let sandboxMode: String?
    public let model: String?
    public let modelReasoningEffort: String?
    
    public init(sandboxMode: String? = nil, model: String? = nil, modelReasoningEffort: String? = nil) {
        self.sandboxMode = sandboxMode
        self.model = model
        self.modelReasoningEffort = modelReasoningEffort
    }
}

/// Parser minimale per ~/.codex/config.toml
public enum CodexConfigLoader {
    private static var codexHome: String {
        ProcessInfo.processInfo.environment["CODEX_HOME"] ?? "\(NSHomeDirectory())/.codex"
    }
    
    private static var configPath: String {
        "\(codexHome)/config.toml"
    }
    
    /// Legge la config Codex. Ritorna valori nil se il file non esiste o la chiave non è trovata.
    public static func load() -> CodexConfig {
        let path = configPath
        guard FileManager.default.fileExists(atPath: path),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return CodexConfig()
        }
        
        var sandboxMode: String?
        var model: String?
        var modelReasoningEffort: String?
        
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            guard let eqIdx = trimmed.firstIndex(of: "=") else { continue }
            
            let key = String(trimmed[..<eqIdx]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: eqIdx)...])
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "^\"|\"$", with: "", options: .regularExpression)
            
            switch key {
            case "sandbox_mode": sandboxMode = value
            case "model": model = value
            case "model_reasoning_effort": modelReasoningEffort = value
            default: break
            }
        }
        
        return CodexConfig(
            sandboxMode: sandboxMode,
            model: model,
            modelReasoningEffort: modelReasoningEffort
        )
    }
}
