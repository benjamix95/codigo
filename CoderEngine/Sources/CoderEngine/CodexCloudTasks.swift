import Foundation

/// Task Codex Cloud
public struct CodexCloudTask: Identifiable, Sendable {
    public let id: String
    public let url: String?
    public let title: String?
    public let status: String?
    public let updatedAt: String?
    public let summary: String?
    
    public init(id: String, url: String? = nil, title: String? = nil, status: String? = nil, updatedAt: String? = nil, summary: String? = nil) {
        self.id = id
        self.url = url
        self.title = title
        self.status = status
        self.updatedAt = updatedAt
        self.summary = summary
    }
}

/// Recupera i task da Codex Cloud
public enum CodexCloudTasks {
    public static func list(codexPath: String, limit: Int = 10) async -> [CodexCloudTask] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["cloud", "list", "--json", "--limit", "\(limit)"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = nil
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tasksArray = json["tasks"] as? [[String: Any]] else {
                return []
            }
            return tasksArray.compactMap { taskDict in
                guard let id = taskDict["id"] as? String else { return nil }
                return CodexCloudTask(
                    id: id,
                    url: taskDict["url"] as? String,
                    title: taskDict["title"] as? String,
                    status: taskDict["status"] as? String,
                    updatedAt: taskDict["updated_at"] as? String,
                    summary: taskDict["summary"] as? String
                )
            }
        } catch {
            return []
        }
    }
}
