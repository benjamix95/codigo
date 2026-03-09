import Foundation

public final class LegacyPersistenceImportService {
    private let store: PostgresPersistenceStore

    public init(store: PostgresPersistenceStore) {
        self.store = store
    }

    public func importIfNeeded() throws -> PersistenceMigrationReport {
        let importedAlready = try store.execute(
            sql: "SELECT COALESCE(details->>'import_completed', 'false') FROM retention_jobs WHERE id = 'events-archive-90d';"
        ).trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        if importedAlready {
            return PersistenceMigrationReport(
                schemaVersion: PersistenceSchema.version,
                appliedAt: Date(),
                importedLegacyData: true,
                importedEntities: [:]
            )
        }

        var counts: [String: Int] = [:]
        counts["plans"] = try importPlanState()
        counts["verified_findings"] = try importVerifiedFindings()
        counts["code_review"] = try importCodeReview()
        counts["bug_hunter"] = try importBugHunter()

        _ = try store.execute(sql: """
        UPDATE retention_jobs
        SET details = jsonb_set(details, '{import_completed}', 'true'::jsonb, true),
            updated_at = NOW()
        WHERE id = 'events-archive-90d';
        """)

        return PersistenceMigrationReport(
            schemaVersion: PersistenceSchema.version,
            appliedAt: Date(),
            importedLegacyData: true,
            importedEntities: counts
        )
    }

    private func importPlanState() throws -> Int {
        let document = MCPSharedState.readPlanDocument()
        var imported = 0
        for (conversationKey, history) in document.snapshotsByConversation {
            guard let conversationId = UUID(uuidString: conversationKey) else { continue }
            for snapshot in history {
                let rawSteps = snapshot.steps.map { step in
                    [
                        "id": step.id,
                        "title": step.title,
                        "description": step.description,
                        "target_file": step.targetFile as Any,
                        "status": step.status,
                        "linked_files": step.linkedFiles,
                        "depends_on": step.dependsOn,
                        "notes": step.notes,
                        "updated_at": step.updatedAt,
                    ]
                }
                try store.writePlanSnapshot(
                    conversationId: conversationId,
                    goal: snapshot.goal,
                    chosenPath: snapshot.chosenPath,
                    steps: rawSteps,
                    walkthroughMarkdown: snapshot.walkthroughMarkdown,
                    summary: snapshot.summary,
                    outcome: snapshot.outcome,
                    maxHistoryPerConversation: 50
                )
                imported += 1
            }
        }
        return imported
    }

    private func importVerifiedFindings() throws -> Int {
        let directory = MCPSharedState.verifiedFindingsSessionsDirectoryPath
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return 0
        }
        var imported = 0
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let envelope = try? decoder.decode(VerifiedFindingsSessionEnvelope.self, from: data) else {
                continue
            }
            try store.persistVerifiedFindingsEnvelope(envelope)
            imported += 1
        }
        return imported
    }

    private func importCodeReview() throws -> Int {
        let directory = MCPSharedState.codeReviewSessionsDirectoryPath
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return 0
        }
        var imported = 0
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let snapshot = try? decoder.decode(CodeReviewSessionSnapshot.self, from: data) else {
                continue
            }
            try store.persistCodeReviewSnapshot(snapshot)
            imported += 1
        }
        return imported
    }

    private func importBugHunter() throws -> Int {
        let directory = MCPSharedState.bugHunterSnapshotsDirectoryPath
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return 0
        }
        var imported = 0
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let snapshot = try? decoder.decode(MCPSharedBugHunterSnapshot.self, from: data) else {
                continue
            }
            try store.persistBugHunterSnapshot(snapshot)
            imported += 1
        }
        return imported
    }
}
