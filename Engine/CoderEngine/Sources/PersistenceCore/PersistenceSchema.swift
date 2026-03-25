import Foundation

public enum PersistenceSchema {
    public static let version = 3

    public static func migrationSQL() -> String {
        [
            metadataSQL,
            identitySQL,
            verifiedFindingsSQL,
            planningSQL,
            debugSQL,
            projectionSQL,
            archiveSQL,
            seedSQL,
            vectorSearchSQL,
        ].joined(separator: "\n\n")
    }
}
