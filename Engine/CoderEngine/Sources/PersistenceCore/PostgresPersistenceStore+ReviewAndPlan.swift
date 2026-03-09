import Foundation

extension PostgresPersistenceStore {
    public func deleteCodeReviewSession(sessionId: String) throws {
        try ensureReady()
        _ = try execute(sql: """
        BEGIN;
        DELETE FROM review_chat_projection WHERE run_id = \(PersistenceSupport.sqlLiteral(sessionId));
        DELETE FROM review_sessions WHERE session_id = \(PersistenceSupport.sqlLiteral(sessionId));
        DELETE FROM verified_findings_checkpoints WHERE session_id = \(PersistenceSupport.sqlLiteral(sessionId));
        DELETE FROM revalidation_reports WHERE session_id = \(PersistenceSupport.sqlLiteral(sessionId));
        DELETE FROM patch_artifacts WHERE session_id = \(PersistenceSupport.sqlLiteral(sessionId));
        DELETE FROM verification_reports WHERE session_id = \(PersistenceSupport.sqlLiteral(sessionId));
        DELETE FROM evidence WHERE session_id = \(PersistenceSupport.sqlLiteral(sessionId));
        DELETE FROM findings WHERE session_id = \(PersistenceSupport.sqlLiteral(sessionId));
        DELETE FROM pipeline_events WHERE session_id = \(PersistenceSupport.sqlLiteral(sessionId));
        DELETE FROM command_log WHERE session_id = \(PersistenceSupport.sqlLiteral(sessionId));
        DELETE FROM pipeline_trace_log WHERE session_id = \(PersistenceSupport.sqlLiteral(sessionId));
        DELETE FROM pipeline_runs WHERE session_id = \(PersistenceSupport.sqlLiteral(sessionId));
        COMMIT;
        """)
    }

    public func persistCodeReviewSnapshot(_ snapshot: CodeReviewSessionSnapshot) throws {
        try ensureReady()
        let payload = try PersistenceSupport.jsonLiteral(snapshot)
        let summary = snapshot.outcome.summary
        let conversationId = sqlNullable(snapshot.conversationId?.uuidString.lowercased())
        let workspaceId = sqlNullable(snapshot.workspacePath)
        if let conversation = snapshot.conversationId?.uuidString.lowercased() {
            _ = try execute(sql: """
            INSERT INTO conversations(id, workspace_id, created_at, updated_at)
            VALUES (\(PersistenceSupport.sqlLiteral(conversation)), NULL, NOW(), NOW())
            ON CONFLICT (id) DO UPDATE SET updated_at = NOW(), version = conversations.version + 1;
            """)
        }
        _ = try execute(sql: """
        INSERT INTO review_sessions(session_id, conversation_id, workspace_id, mutation_sequence, phase, stage, findings_count, open_findings_count, current_round, active_worker_count, scope_type, scope_ref, started_at, completed_at, analysis_completed_at, status_payload, last_updated_at)
        VALUES (\(PersistenceSupport.sqlLiteral(snapshot.sessionId)), \(conversationId), \(workspaceId), \(snapshot.mutationSequence),
            \(PersistenceSupport.sqlLiteral(snapshot.phase.rawValue)), \(PersistenceSupport.sqlLiteral(snapshot.stage.rawValue)),
            \(snapshot.findings.count), \(snapshot.openFindings.count), \(snapshot.currentRound), \(snapshot.activeWorkerCount),
            \(sqlNullable(snapshot.scope?.type.rawValue)), \(sqlNullable(snapshot.scope?.ref)),
            \(sqlTimestamp(snapshot.startedAt)), \(sqlTimestamp(snapshot.completedAt)), \(sqlTimestamp(snapshot.analysisCompletedAt)),
            \(payload)::jsonb, \(sqlTimestamp(snapshot.lastUpdatedAt)))
        ON CONFLICT (session_id) DO UPDATE SET status_payload = EXCLUDED.status_payload, last_updated_at = EXCLUDED.last_updated_at, mutation_sequence = EXCLUDED.mutation_sequence, version = review_sessions.version + 1;
        """)
        if let verified = snapshot.verifiedFindings {
            try persistVerifiedFindingsEnvelope(verified)
        }
        _ = try execute(sql: """
        INSERT INTO review_chat_projection(run_id, summary, verified_count, candidate_count, rejected_count, needs_manual_review_count, updated_at)
        VALUES (\(PersistenceSupport.sqlLiteral(snapshot.sessionId)), \(PersistenceSupport.sqlLiteral(summary)),
            \(snapshot.verifiedFindings?.projectionSnapshot.verifiedQueue.count ?? 0), \(snapshot.candidates.count),
            \(snapshot.findings.filter { $0.status == .dismissed }.count), \(snapshot.findings.filter { $0.status == .open }.count),
            \(sqlTimestamp(snapshot.lastUpdatedAt)))
        ON CONFLICT (run_id) DO UPDATE SET summary = EXCLUDED.summary, updated_at = EXCLUDED.updated_at;
        """)
    }

    public func readCodeReviewSnapshot(sessionId: String) throws -> CodeReviewSessionSnapshot? {
        try querySingleJSON(
            "SELECT status_payload::text FROM review_sessions WHERE session_id = \(PersistenceSupport.sqlLiteral(sessionId));",
            as: CodeReviewSessionSnapshot.self
        )
    }

    public func readCodeReviewSnapshots(conversationId: UUID? = nil) throws -> [CodeReviewSessionSnapshot] {
        let filter: String
        if let conversationId {
            filter = " WHERE conversation_id = \(PersistenceSupport.sqlLiteral(conversationId.uuidString.lowercased()))"
        } else {
            filter = ""
        }
        return try queryJSONArray(
            "SELECT COALESCE(jsonb_agg(status_payload ORDER BY last_updated_at DESC), '[]'::jsonb)::text FROM review_sessions\(filter);",
            as: [CodeReviewSessionSnapshot].self
        )
    }

    public func persistBugHunterSnapshot(_ snapshot: MCPSharedBugHunterSnapshot) throws {
        try ensureReady()
        let payload = try PersistenceSupport.jsonLiteral(snapshot)
        if let conversationId = snapshot.conversationId {
            _ = try execute(sql: """
            INSERT INTO conversations(id, workspace_id, created_at, updated_at)
            VALUES (\(PersistenceSupport.sqlLiteral(conversationId)), NULL, NOW(), NOW())
            ON CONFLICT (id) DO UPDATE SET updated_at = NOW(), version = conversations.version + 1;
            """)
        }
        _ = try execute(sql: """
        INSERT INTO bug_hunter_runs(run_id, conversation_id, review_session_id, workspace_id, source_kind, trigger_kind, git_root, branch_name, primary_commit, related_commits, status, started_at, completed_at, last_updated_at, last_message, auto_fix_mode, clean_after_fix, verified_findings_count, candidate_findings_count, last_revalidation_verdict, security_gate_ready, status_payload)
        VALUES (\(PersistenceSupport.sqlLiteral(snapshot.runId)), \(sqlNullable(snapshot.conversationId)), \(sqlNullable(snapshot.reviewSessionId)),
            NULL, \(PersistenceSupport.sqlLiteral(snapshot.sourceKind.rawValue)), \(PersistenceSupport.sqlLiteral(snapshot.triggerKind.rawValue)),
            \(PersistenceSupport.sqlLiteral(snapshot.gitRoot)), \(sqlNullable(snapshot.branchName)), \(sqlNullable(snapshot.primaryCommit)),
            \(try PersistenceSupport.jsonLiteral(snapshot.relatedCommits))::jsonb, \(PersistenceSupport.sqlLiteral(snapshot.status.rawValue)),
            \(sqlTimestamp(snapshot.startedAt)), \(sqlTimestamp(snapshot.completedAt)), \(sqlTimestamp(snapshot.lastUpdatedAt)),
            \(sqlNullable(snapshot.lastMessage)), \(PersistenceSupport.sqlLiteral(snapshot.autoFixMode)), \(snapshot.cleanAfterFix),
            \(snapshot.verifiedFindingsCount), \(snapshot.candidateFindingsCount), \(sqlNullable(snapshot.lastRevalidationVerdict)),
            \(snapshot.securityGateReady.map { $0 ? "TRUE" : "FALSE" } ?? "NULL"), \(payload)::jsonb)
        ON CONFLICT (run_id) DO UPDATE SET status_payload = EXCLUDED.status_payload, last_updated_at = EXCLUDED.last_updated_at, version = bug_hunter_runs.version + 1;
        """)
    }

    public func readBugHunterSnapshot(runId: String) throws -> MCPSharedBugHunterSnapshot? {
        try querySingleJSON(
            "SELECT status_payload::text FROM bug_hunter_runs WHERE run_id = \(PersistenceSupport.sqlLiteral(runId));",
            as: MCPSharedBugHunterSnapshot.self
        )
    }

    public func readBugHunterSnapshots(conversationId: UUID? = nil) throws -> [MCPSharedBugHunterSnapshot] {
        let filter = conversationId.map {
            " WHERE conversation_id = \(PersistenceSupport.sqlLiteral($0.uuidString.lowercased()))"
        } ?? ""
        return try queryJSONArray(
            "SELECT COALESCE(jsonb_agg(status_payload ORDER BY last_updated_at DESC), '[]'::jsonb)::text FROM bug_hunter_runs\(filter);",
            as: [MCPSharedBugHunterSnapshot].self
        )
    }

    public func writePlanSnapshot(
        conversationId: UUID,
        goal: String,
        chosenPath: String?,
        steps: [[String: Any]],
        walkthroughMarkdown: String?,
        summary: String?,
        outcome: String?,
        maxHistoryPerConversation: Int
    ) throws {
        let planId = "plan-\(conversationId.uuidString.lowercased())"
        let conversationKey = conversationId.uuidString.lowercased()
        let now = ISO8601DateFormatter().string(from: .now)
        let normalizedSteps = MCPSharedState.canonicalizedPlanSteps(steps, now: now)
        let snapshot = MCPSharedPlanSnapshot(
            snapshotId: UUID().uuidString.lowercased(),
            conversationId: conversationKey,
            goal: MCPSharedState.sanitizedText(goal, fallback: "Operational plan in progress"),
            chosenPath: MCPSharedState.optionalSanitizedText(chosenPath),
            steps: normalizedSteps,
            walkthroughMarkdown: MCPSharedState.optionalSanitizedText(walkthroughMarkdown),
            summary: MCPSharedState.optionalSanitizedText(summary),
            outcome: MCPSharedState.normalizeOutcome(outcome),
            createdAt: now,
            updatedAt: now
        )
        let signature = MCPSharedState.signature(for: snapshot)
        let latest = try readLatestPlanSnapshot(conversationId: conversationId)
        let activeSnapshot = latest?.signature == signature ? latest!.snapshot : snapshot
        _ = try execute(sql: """
        INSERT INTO conversations(id, workspace_id, created_at, updated_at)
        VALUES (\(PersistenceSupport.sqlLiteral(conversationKey)), NULL, NOW(), NOW())
        ON CONFLICT (id) DO UPDATE SET updated_at = NOW(), version = conversations.version + 1;
        INSERT INTO plans(id, conversation_id, workspace_id, title, status, goal, chosen_path_summary, walkthrough_markdown, summary, outcome, created_at, updated_at)
        VALUES (\(PersistenceSupport.sqlLiteral(planId)), \(PersistenceSupport.sqlLiteral(conversationKey)), NULL,
            \(PersistenceSupport.sqlLiteral("Plan")), \(PersistenceSupport.sqlLiteral("active")), \(PersistenceSupport.sqlLiteral(snapshot.goal)),
            \(sqlNullable(snapshot.chosenPath)), \(sqlNullable(snapshot.walkthroughMarkdown)), \(sqlNullable(snapshot.summary)),
            \(sqlNullable(snapshot.outcome)), \(PersistenceSupport.sqlLiteral(now)), \(PersistenceSupport.sqlLiteral(now)))
        ON CONFLICT (id) DO UPDATE SET goal = EXCLUDED.goal, updated_at = NOW(), version = plans.version + 1;
        """)
        if activeSnapshot.snapshotId == snapshot.snapshotId {
            let payload = try PersistenceSupport.jsonLiteral(snapshot)
            _ = try execute(sql: """
            INSERT INTO plan_snapshots(id, plan_id, conversation_id, goal, chosen_path_summary, summary, outcome, signature, snapshot_payload, created_at, updated_at)
            VALUES (\(PersistenceSupport.sqlLiteral(snapshot.snapshotId)), \(PersistenceSupport.sqlLiteral(planId)), \(PersistenceSupport.sqlLiteral(conversationKey)),
                \(PersistenceSupport.sqlLiteral(snapshot.goal)), \(sqlNullable(snapshot.chosenPath)), \(sqlNullable(snapshot.summary)),
                \(sqlNullable(snapshot.outcome)), \(PersistenceSupport.sqlLiteral(signature)), \(payload)::jsonb,
                \(PersistenceSupport.sqlLiteral(snapshot.createdAt)), \(PersistenceSupport.sqlLiteral(snapshot.updatedAt)));
            DELETE FROM plan_snapshot_steps WHERE snapshot_id = \(PersistenceSupport.sqlLiteral(snapshot.snapshotId));
            """)
            for (index, step) in normalizedSteps.enumerated() {
                _ = try execute(sql: """
                INSERT INTO plan_snapshot_steps(snapshot_id, step_id, step_index, title, description, target_file, status, linked_files, depends_on, notes, updated_at)
                VALUES (\(PersistenceSupport.sqlLiteral(snapshot.snapshotId)), \(PersistenceSupport.sqlLiteral(step.id)), \(index),
                    \(PersistenceSupport.sqlLiteral(step.title)), \(PersistenceSupport.sqlLiteral(step.description)),
                    \(sqlNullable(step.targetFile)), \(PersistenceSupport.sqlLiteral(step.status)),
                    \(try PersistenceSupport.jsonLiteral(step.linkedFiles))::jsonb, \(try PersistenceSupport.jsonLiteral(step.dependsOn))::jsonb,
                    \(PersistenceSupport.sqlLiteral(step.notes)), \(PersistenceSupport.sqlLiteral(step.updatedAt)));
                """)
            }
        }
        _ = try execute(sql: """
        DELETE FROM plan_steps WHERE plan_id = \(PersistenceSupport.sqlLiteral(planId));
        DELETE FROM plan_step_dependencies WHERE plan_id = \(PersistenceSupport.sqlLiteral(planId));
        """)
        for (index, step) in normalizedSteps.enumerated() {
            _ = try execute(sql: """
            INSERT INTO plan_steps(id, plan_id, step_index, title, description, target_file, status, notes, linked_files, updated_at)
            VALUES (\(PersistenceSupport.sqlLiteral(step.id)), \(PersistenceSupport.sqlLiteral(planId)), \(index),
                \(PersistenceSupport.sqlLiteral(step.title)), \(PersistenceSupport.sqlLiteral(step.description)),
                \(sqlNullable(step.targetFile)), \(PersistenceSupport.sqlLiteral(step.status)), \(PersistenceSupport.sqlLiteral(step.notes)),
                \(try PersistenceSupport.jsonLiteral(step.linkedFiles))::jsonb, \(PersistenceSupport.sqlLiteral(step.updatedAt)));
            """)
            for dependency in step.dependsOn {
                _ = try execute(sql: """
                INSERT INTO plan_step_dependencies(plan_id, step_id, depends_on_step_id)
                VALUES (\(PersistenceSupport.sqlLiteral(planId)), \(PersistenceSupport.sqlLiteral(step.id)), \(PersistenceSupport.sqlLiteral(dependency)))
                ON CONFLICT DO NOTHING;
                """)
            }
        }
        _ = try execute(sql: """
        DELETE FROM plan_snapshots
        WHERE plan_id = \(PersistenceSupport.sqlLiteral(planId))
          AND id NOT IN (
            SELECT id FROM plan_snapshots WHERE plan_id = \(PersistenceSupport.sqlLiteral(planId))
            ORDER BY created_at DESC LIMIT \(max(1, maxHistoryPerConversation))
          );
        """)
    }

    public func readLatestPlanSnapshot(conversationId: UUID?) throws -> (snapshot: MCPSharedPlanSnapshot, signature: String)? {
        let filter = conversationId.map {
            " WHERE conversation_id = \(PersistenceSupport.sqlLiteral($0.uuidString.lowercased()))"
        } ?? ""
        struct Row: Decodable { let snapshot_payload: MCPSharedPlanSnapshot; let signature: String }
        return try querySingleJSON(
            "SELECT jsonb_build_object('snapshot_payload', snapshot_payload, 'signature', signature)::text FROM plan_snapshots\(filter) ORDER BY created_at DESC LIMIT 1;",
            as: Row.self
        ).map { ($0.snapshot_payload, $0.signature) }
    }

    public func readPlanHistory(conversationId: UUID?, limit: Int) throws -> [MCPSharedPlanSnapshot] {
        let filter = conversationId.map {
            " WHERE conversation_id = \(PersistenceSupport.sqlLiteral($0.uuidString.lowercased()))"
        } ?? ""
        return try queryJSONArray(
            "SELECT COALESCE(jsonb_agg(snapshot_payload ORDER BY created_at DESC), '[]'::jsonb)::text FROM (SELECT snapshot_payload, created_at FROM plan_snapshots\(filter) ORDER BY created_at DESC LIMIT \(max(1, min(limit, 50)))) t;",
            as: [MCPSharedPlanSnapshot].self
        )
    }
}
