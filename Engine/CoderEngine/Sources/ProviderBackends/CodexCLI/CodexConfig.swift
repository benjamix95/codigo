import Foundation

/// Full config letta da ~/.codex/config.toml
public struct CodexConfig: Sendable, Equatable {
    public var sandboxMode: String?
    public var fastMode: Bool?
    public var model: String?
    public var modelProvider: String?
    public var modelReasoningEffort: String?
    public var modelReasoningSummary: String?
    public var modelVerbosity: String?
    public var personality: String?
    public var networkAccess: Bool?
    public var additionalWriteRoots: [String]
    public var developerInstructions: String?
    public var checkForUpdateOnStartup: Bool?

    public init(
        sandboxMode: String? = nil,
        fastMode: Bool? = nil,
        model: String? = nil,
        modelProvider: String? = nil,
        modelReasoningEffort: String? = nil,
        modelReasoningSummary: String? = nil,
        modelVerbosity: String? = nil,
        personality: String? = nil,
        networkAccess: Bool? = nil,
        additionalWriteRoots: [String] = [],
        developerInstructions: String? = nil,
        checkForUpdateOnStartup: Bool? = nil
    ) {
        self.sandboxMode = sandboxMode
        self.fastMode = fastMode
        self.model = model
        self.modelProvider = modelProvider
        self.modelReasoningEffort = modelReasoningEffort
        self.modelReasoningSummary = modelReasoningSummary
        self.modelVerbosity = modelVerbosity
        self.personality = personality
        self.networkAccess = networkAccess
        self.additionalWriteRoots = additionalWriteRoots
        self.developerInstructions = developerInstructions
        self.checkForUpdateOnStartup = checkForUpdateOnStartup
    }
}

/// Parser e writer per ~/.codex/config.toml
public enum CodexConfigLoader {
    private static let cacheLock = NSLock()
    private static var cachedPath: String?
    private static var cachedMtime: Date?
    private static var cachedConfig: CodexConfig?

    public static var codexHome: String {
        ProcessInfo.processInfo.environment["CODEX_HOME"] ?? "\(NSHomeDirectory())/.codex"
    }

    public static func configPath(forCodexHome codexHome: String) -> String {
        "\(codexHome)/config.toml"
    }

    public static var configPath: String {
        configPath(forCodexHome: codexHome)
    }

    public static func load() -> CodexConfig {
        load(from: configPath)
    }

    public static func load(from path: String) -> CodexConfig {
        let fileManager = FileManager.default
        let mtime = modificationDate(for: path, fileManager: fileManager)

        cacheLock.lock()
        if cachedPath == path, cachedMtime == mtime, let cachedConfig {
            cacheLock.unlock()
            return cachedConfig
        }
        cacheLock.unlock()

        guard fileManager.fileExists(atPath: path),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            let empty = CodexConfig()
            updateCache(path: path, mtime: mtime, config: empty)
            return empty
        }

        let parsed = parse(content)
        updateCache(path: path, mtime: mtime, config: parsed)
        return parsed
    }

    public static func save(_ config: CodexConfig) {
        save(config, to: configPath)
    }

    public static func save(_ config: CodexConfig, to path: String) {
        let existingContent = try? String(contentsOfFile: path, encoding: .utf8)
        let mergedContent = renderMergedContent(existingContent: existingContent, config: config)
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try? mergedContent.write(toFile: path, atomically: true, encoding: .utf8)
        let mtime = modificationDate(for: path, fileManager: .default)
        updateCache(path: path, mtime: mtime, config: config)
    }

    static func modificationDate(for path: String, fileManager: FileManager) -> Date? {
        guard let attrs = try? fileManager.attributesOfItem(atPath: path) else { return nil }
        return attrs[.modificationDate] as? Date
    }

    static func updateCache(path: String, mtime: Date?, config: CodexConfig) {
        cacheLock.lock()
        cachedPath = path
        cachedMtime = mtime
        cachedConfig = config
        cacheLock.unlock()
    }
}
