import Foundation

enum SwarmMetadata {
    private static let swarmGroupPrefix = "swarm-"
    private static let supervisorKinds: Set<String> = ["orchestrator", "supervisor"]

    static func swarmId(from payload: [String: String]) -> String? {
        if let direct = (payload["swarm_id"] ?? payload["swarmId"])?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !direct.isEmpty {
            return direct
        }

        guard let groupId = (payload["group_id"] ?? payload["groupId"])?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              groupId.lowercased().hasPrefix(swarmGroupPrefix),
              groupId.count > swarmGroupPrefix.count else {
            return nil
        }

        let extracted = String(groupId.dropFirst(swarmGroupPrefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !extracted.isEmpty else { return nil }
        return extracted
    }

    static func canonicalGroupId(from payload: [String: String]) -> String? {
        guard let swarmId = swarmId(from: payload) else { return nil }
        return "\(swarmGroupPrefix)\(swarmId)"
    }

    static func isSwarmEvent(_ payload: [String: String]) -> Bool {
        return swarmId(from: payload) != nil
    }

    static func supervisorKind(from payload: [String: String]) -> String? {
        let candidates = [
            payload["supervisor_kind"],
            payload["supervisorKind"],
            payload["owner_kind"],
            payload["ownerKind"],
        ]
        for candidate in candidates {
            let normalized = candidate?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""
            if supervisorKinds.contains(normalized) {
                return normalized
            }
        }
        return nil
    }

    static func isSupervisorEvent(_ payload: [String: String]) -> Bool {
        supervisorKind(from: payload) != nil
    }
}
