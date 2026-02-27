import Foundation

enum SwarmMetadataResolver {
    private static let groupPrefix = "swarm-"

    private static func firstSwarmID(
        in item: [String: Any],
        keys: [String]
    ) -> String? {
        for key in keys {
            if let rawValue = item[key] as? String {
                let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    static func normalizeGroupID(from swarmID: String) -> String {
        return swarmID.hasPrefix(groupPrefix) ? swarmID : "\(groupPrefix)\(swarmID)"
    }

    @discardableResult
    static func applySwarmMetadata(
        to payload: inout [String: String],
        from item: [String: Any],
        keys: [String] = ["swarm_id"],
        forceGroupID: Bool = false
    ) -> Bool {
        guard let swarmID = firstSwarmID(in: item, keys: keys) else { return false }
        payload["swarm_id"] = swarmID

        let shouldSetGroupID = forceGroupID || (payload["group_id"]?.isEmpty ?? true)
        if shouldSetGroupID {
            payload["group_id"] = normalizeGroupID(from: swarmID)
        }
        return true
    }
}
