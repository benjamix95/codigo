import Foundation

public enum PersistenceSchema {
    public static let version = 1

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
        ].joined(separator: "\n\n")
    }
}
