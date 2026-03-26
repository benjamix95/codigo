import CoderEngine
import Foundation

extension CodeReviewPanelStore {
    @MainActor
    func maybeExportReviewReportArtifacts(
        snapshot: CodeReviewSessionSnapshot,
        scope: ReviewScopeTarget,
        depth: ReviewScanDepth
    ) async {
        let shouldExport: Bool = {
            if case .codebase = scope { return true }
            if depth == .pro { return true }
            return false
        }()

        guard shouldExport else { return }
        guard snapshot.phase == .completed else { return }
        if let err = snapshot.lastError, !err.isEmpty { return }

        let scopeLabel = scope.displayDescription
        let depthLabel = depth.displayName
        let markdown = ReviewPanelReportMarkdownBuilder.markdown(
            snapshot: snapshot,
            scopeLabel: scopeLabel,
            scanDepthLabel: depthLabel
        )

        let base = "review-\(snapshot.sessionId)"
            .replacingOccurrences(of: "/", with: "-")
        let folder = Self.reviewReportsDirectory()

        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let mdURL = folder.appendingPathComponent("\(base).md")
        let pdfURL = folder.appendingPathComponent("\(base).pdf")

        do {
            try markdown.write(to: mdURL, atomically: true, encoding: .utf8)
            try ReviewPanelReportPDFExporter.writeMultipagePDF(text: markdown, destination: pdfURL)
            reviewReportExportNotice = ReviewReportExportNotice(
                markdownFileURL: mdURL,
                pdfFileURL: pdfURL,
                savedAt: Date()
            )
            appendPanelSystemMessage(
                "Report review salvati: \(mdURL.path) e \(pdfURL.path)",
                kind: .statusNote
            )
        } catch {
            appendPanelSystemMessage(
                "Export report review non riuscito: \(error.localizedDescription)",
                kind: .statusNote
            )
        }
    }

    static func reviewReportsDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let root = support?.appendingPathComponent("SoloCode", isDirectory: true)
        return (root ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("ReviewReports", isDirectory: true)
    }
}
