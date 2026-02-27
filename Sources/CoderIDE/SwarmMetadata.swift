import Foundation

enum SwarmMetadata {
    private static let swarmGroupPrefix = "swarm-"

    static func swarmId(from payload: [String: String]) -> String? {
        if let direct = payload["swarm_id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !direct.isEmpty {
            return direct
        }

        guard let groupId = payload["group_id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              groupId.lowercased().hasPrefix(swarmGroupPrefix),
              groupId.count > swarmGroupPrefix.count else {
            return nil
        }

        return String(groupId.dropFirst(swarmGroupPrefix.count))
    }

    static func canonicalGroupId(from payload: [String: String]) -> String? {
        guard let swarmId = swarmId(from: payload) else { return nil }
        return "\(swarmGroupPrefix)\(swarmId)"
    }

    static func isSwarmEvent(_ payload: [String: String]) -> Bool {
        return swarmId(from: payload) != nil
    }
}

