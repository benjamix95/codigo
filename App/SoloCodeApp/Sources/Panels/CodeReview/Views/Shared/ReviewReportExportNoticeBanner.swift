import SwiftUI

/// Banner condiviso tra tab Commands e Findings per export MD/PDF.
struct ReviewReportExportNoticeBanner: View {
    @ObservedObject var store: CodeReviewPanelStore
    let notice: ReviewReportExportNotice

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "doc.richtext.fill")
                    .foregroundStyle(store.accent)
                Text("Report esportati (Markdown e PDF)")
                    .font(.system(size: 10.5, weight: .semibold))
                Spacer(minLength: 8)
                Button("Chiudi") {
                    store.dismissReviewReportExportNotice()
                }
                .buttonStyle(.plain)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
            }
            Text(notice.markdownFileURL.path)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 8) {
                Button("Mostra nel Finder") {
                    store.revealExportedReviewReportsInFinder()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(store.accent)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(store.accent.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(store.accent.opacity(0.25), lineWidth: 0.5)
        )
    }
}
