import Foundation

public enum VerifiedFindingsSessionSyncService {
    private static let cacheLock = NSLock()
    private static var envelopeCache: [String: VerifiedFindingsSessionEnvelope] = [:]

    public static func sync(
        snapshot: CodeReviewSessionSnapshot,
        existingEnvelope: VerifiedFindingsSessionEnvelope? = nil,
        entryPoint: VerifiedFindingOriginEntryPoint = .reviewChat
    ) -> VerifiedFindingsSessionEnvelope {
        let cacheKey = makeCacheKey(
            snapshot: snapshot,
            existingEnvelope: existingEnvelope,
            entryPoint: entryPoint
        )
        if let cached = cachedEnvelope(for: cacheKey) {
            return cached
        }

        let traceLog = snapshot.events.map { $0.detail ?? $0.type.rawValue }
        let baseFindings = buildBaseFindings(snapshot: snapshot, entryPoint: entryPoint)
        let rustSync = syncWithRust(
            findings: baseFindings,
            traceLog: traceLog
        )
        let identifiedFindings = rustSync?.findings ?? applyIdentityPolicy(to: baseFindings)
        let findings = applyVersionPolicy(
            to: identifiedFindings,
            existingEnvelope: existingEnvelope
        )
        let evidences = buildEvidences(snapshot: snapshot, findings: findings)
        let reports = buildVerificationReports(snapshot: snapshot, findings: findings, evidences: evidences)
        let patches = buildPatchArtifacts(snapshot: snapshot)
        let revalidations = buildRevalidationReports(snapshot: snapshot)
        let run = buildRun(snapshot: snapshot, entryPoint: entryPoint)
        let canonicalSnapshot = VerifiedFindingsCanonicalSnapshot(
            runs: [run.id: run],
            findings: Dictionary(uniqueKeysWithValues: findings.map { ($0.id, $0) }),
            evidences: Dictionary(uniqueKeysWithValues: evidences.map { ($0.id, $0) }),
            verificationReports: Dictionary(uniqueKeysWithValues: reports.map { ($0.id, $0) }),
            patchArtifacts: Dictionary(uniqueKeysWithValues: patches.map { ($0.id, $0) }),
            revalidationReports: Dictionary(uniqueKeysWithValues: revalidations.map { ($0.id, $0) }),
            commandLog: existingEnvelope?.canonicalSnapshot.commandLog ?? [],
            eventLog: snapshot.events.enumerated().map { index, event in
                VerifiedPipelineEvent(
                    id: event.id,
                    runId: snapshot.sessionId,
                    entityId: event.metadata["finding_id"] ?? event.metadata["candidate_id"] ?? snapshot.sessionId,
                    entityType: event.metadata["patch_id"] == nil ? .finding : .patch,
                    eventType: event.type.rawValue,
                    payload: event.toPayload().merging(["sequence": String(index)]) { current, _ in current },
                    eventSchemaVersion: 1,
                    entitySchemaVersion: 1,
                    migrationHint: nil,
                    createdAt: event.timestamp
                )
            },
            traceLog: traceLog
        )
        let envelope = VerifiedFindingsSessionEnvelope(
            sessionId: snapshot.sessionId,
            canonicalSnapshot: canonicalSnapshot,
            projectionSnapshot: rustSync?.projection ?? VerifiedFindingsProjectionBuilder.build(from: canonicalSnapshot),
            lastUpdatedAt: snapshot.lastUpdatedAt
        )
        storeCachedEnvelope(envelope, for: cacheKey)
        return envelope
    }

    static func buildBaseFindings(
        snapshot: CodeReviewSessionSnapshot,
        entryPoint: VerifiedFindingOriginEntryPoint
    ) -> [VerifiedFinding] {
        let patchesByFindingId = Dictionary(
            uniqueKeysWithValues: snapshot.patches.map { ($0.findingId, $0) }
        )
        var results = snapshot.findings.map { finding in
            mapFinding(
                finding,
                patch: patchesByFindingId[finding.id],
                entryPoint: entryPoint
            )
        }
        let findingIds = Set(results.map(\.id))
        for candidate in snapshot.candidates where !findingIds.contains(candidate.id) {
            results.append(mapCandidate(candidate, entryPoint: entryPoint))
        }
        return results
    }

    static func applyIdentityPolicy(to findings: [VerifiedFinding]) -> [VerifiedFinding] {
        var output: [VerifiedFinding] = []
        var identityIndex = FindingIdentityService.IdentityIndex()
        for finding in findings.sorted(by: { $0.createdAt < $1.createdAt }) {
            let candidateIdentity = FindingIdentityService.prepare(finding)
            let resolvedFinding: VerifiedFinding
            if let match = FindingIdentityService.findDuplicate(
                candidateIdentity: candidateIdentity,
                existingIndex: identityIndex
            ) {
                resolvedFinding = copying(
                    finding,
                    possibleDuplicateOf: [match.existingFindingId],
                    mergedIntoFindingId: match.isExactDuplicate ? match.existingFindingId : nil,
                    recurrenceGroupId: match.existingFindingId
                )
            } else {
                resolvedFinding = finding
            }
            output.append(resolvedFinding)
            identityIndex.insert(FindingIdentityService.prepare(resolvedFinding))
        }
        return output
    }

    static func applyVersionPolicy(
        to findings: [VerifiedFinding],
        existingEnvelope: VerifiedFindingsSessionEnvelope?
    ) -> [VerifiedFinding] {
        let existingFindings = existingEnvelope?.canonicalSnapshot.findings ?? [:]
        return findings.map { finding in
            guard let previous = existingFindings[finding.id] else { return finding }
            let unchanged = hasSameVersionedContent(previous, finding)
            return VerifiedFinding(
                id: finding.id,
                domain: finding.domain,
                title: finding.title,
                summary: finding.summary,
                category: finding.category,
                severity: finding.severity,
                confidence: finding.confidence,
                status: finding.status,
                filePath: finding.filePath,
                lineStart: finding.lineStart,
                lineEnd: finding.lineEnd,
                ruleId: finding.ruleId,
                evidenceIds: finding.evidenceIds,
                verificationReportId: finding.verificationReportId,
                patchId: finding.patchId,
                revalidationReportId: finding.revalidationReportId,
                rootCause: finding.rootCause,
                impact: finding.impact,
                exploitability: finding.exploitability,
                reproducibility: finding.reproducibility,
                version: unchanged ? previous.version : previous.version + 1,
                originEntryPoint: finding.originEntryPoint,
                sourceOrigin: finding.sourceOrigin,
                lastCommandId: previous.lastCommandId,
                staleStatus: finding.staleStatus,
                closedReason: finding.closedReason,
                policyFlags: finding.policyFlags,
                findingFingerprint: finding.findingFingerprint,
                identityVersion: previous.identityVersion,
                possibleDuplicateOf: finding.possibleDuplicateOf,
                mergedIntoFindingId: finding.mergedIntoFindingId,
                recurrenceGroupId: finding.recurrenceGroupId,
                createdAt: previous.createdAt,
                updatedAt: unchanged ? previous.updatedAt : finding.updatedAt
            )
        }
    }

    static func hasSameVersionedContent(
        _ lhs: VerifiedFinding,
        _ rhs: VerifiedFinding
    ) -> Bool {
        lhs.domain == rhs.domain
            && lhs.title == rhs.title
            && lhs.summary == rhs.summary
            && lhs.category == rhs.category
            && lhs.severity == rhs.severity
            && lhs.confidence == rhs.confidence
            && lhs.status == rhs.status
            && lhs.filePath == rhs.filePath
            && lhs.lineStart == rhs.lineStart
            && lhs.lineEnd == rhs.lineEnd
            && lhs.ruleId == rhs.ruleId
            && lhs.evidenceIds == rhs.evidenceIds
            && lhs.verificationReportId == rhs.verificationReportId
            && lhs.patchId == rhs.patchId
            && lhs.revalidationReportId == rhs.revalidationReportId
            && lhs.rootCause == rhs.rootCause
            && lhs.impact == rhs.impact
            && lhs.exploitability == rhs.exploitability
            && lhs.reproducibility == rhs.reproducibility
            && lhs.sourceOrigin == rhs.sourceOrigin
            && lhs.staleStatus == rhs.staleStatus
            && lhs.closedReason == rhs.closedReason
            && lhs.policyFlags == rhs.policyFlags
            && lhs.findingFingerprint == rhs.findingFingerprint
            && lhs.possibleDuplicateOf == rhs.possibleDuplicateOf
            && lhs.mergedIntoFindingId == rhs.mergedIntoFindingId
            && lhs.recurrenceGroupId == rhs.recurrenceGroupId
    }

    private static func syncWithRust(
        findings: [VerifiedFinding],
        traceLog: [String]
    ) -> ReviewCoreVerifiedSyncResponse? {
        ReviewCoreBridge.call(
            functionName: "review_core_sync_verified_findings",
            request: ReviewCoreVerifiedSyncRequest(
                schemaVersion: 1,
                findings: findings,
                traceLog: traceLog
            )
        )
    }

    static func syncWithRustForBenchmark(
        findings: [VerifiedFinding],
        traceLog: [String]
    ) -> ReviewCoreVerifiedSyncResponse? {
        syncWithRust(findings: findings, traceLog: traceLog)
    }

    private static func makeCacheKey(
        snapshot: CodeReviewSessionSnapshot,
        existingEnvelope: VerifiedFindingsSessionEnvelope?,
        entryPoint: VerifiedFindingOriginEntryPoint
    ) -> String {
        let existingMarker: String
        if let existingEnvelope {
            existingMarker = "\(existingEnvelope.lastUpdatedAt.timeIntervalSince1970)#\(existingEnvelope.canonicalSnapshot.findings.count)"
        } else {
            existingMarker = "none"
        }
        return [
            snapshot.sessionId,
            String(snapshot.mutationSequence),
            String(snapshot.lastUpdatedAt.timeIntervalSince1970),
            entryPoint.rawValue,
            existingMarker,
        ].joined(separator: "#")
    }

    private static func cachedEnvelope(for key: String) -> VerifiedFindingsSessionEnvelope? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return envelopeCache[key]
    }

    private static func storeCachedEnvelope(
        _ envelope: VerifiedFindingsSessionEnvelope,
        for key: String
    ) {
        cacheLock.lock()
        envelopeCache[key] = envelope
        if envelopeCache.count > 64 {
            envelopeCache.removeValue(forKey: envelopeCache.keys.sorted().first ?? key)
        }
        cacheLock.unlock()
    }
}

struct ReviewCoreVerifiedSyncRequest: Encodable {
    let schemaVersion: Int
    let findings: [VerifiedFinding]
    let traceLog: [String]
}

struct ReviewCoreVerifiedSyncResponse: Decodable {
    let findings: [VerifiedFinding]
    let projection: VerifiedFindingsProjectionSnapshot
}
