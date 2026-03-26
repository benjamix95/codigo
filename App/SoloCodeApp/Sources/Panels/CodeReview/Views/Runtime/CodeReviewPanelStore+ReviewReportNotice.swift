#if os(macOS)
import AppKit
#endif
import Foundation

extension CodeReviewPanelStore {
    func dismissReviewReportExportNotice() {
        reviewReportExportNotice = nil
    }

    /// Riporta in primo piano il Finder con MD e PDF dell’ultimo export.
    func revealExportedReviewReportsInFinder() {
        #if os(macOS)
        guard let notice = reviewReportExportNotice else { return }
        NSWorkspace.shared.activateFileViewerSelecting([notice.markdownFileURL, notice.pdfFileURL])
        #endif
    }
}
