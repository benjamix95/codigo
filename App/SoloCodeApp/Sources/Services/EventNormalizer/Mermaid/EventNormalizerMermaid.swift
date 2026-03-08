import Foundation

extension EventNormalizer {
    static func normalizeMermaidRender(payload: [String: String], timestamp: Date) -> [NormalizedEvent] {
        let code = (payload["code"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if code.isEmpty {
            return [
                .taskActivity(TaskActivity(
                    type: "mermaid_render",
                    title: "Mermaid render",
                    detail: "No mermaid content",
                    payload: payload,
                    timestamp: timestamp,
                    phase: .planning,
                    isRunning: false
                ))
            ]
        }
        let title = payload["title"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            .mermaidRender(code: code, title: title),
            .taskActivity(TaskActivity(
                type: "mermaid_render",
                title: title ?? "Mermaid diagram",
                detail: "Rendered diagram in IDE",
                payload: payload,
                timestamp: timestamp,
                phase: .planning,
                isRunning: false
            ))
        ]
    }
}
