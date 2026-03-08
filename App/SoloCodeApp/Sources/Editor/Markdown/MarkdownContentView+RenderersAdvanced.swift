import SwiftUI

extension MarkdownContentView {
    // MARK: - Code Block

    func codeBlockView(language: String, code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if !language.isEmpty {
                    Text(language.lowercased())
                        .font(
                            FontPreferences.resolveCodeFont(
                                size: max(codeFontSize - 2, 10),
                                family: uiCodeFontFamily,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(accentColor.opacity(0.6))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(accentColor.opacity(0.08), in: Capsule())
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(FontPreferences.resolveSansFont(size: 9, family: uiSansFontFamily))
                        Text("Copy")
                            .font(
                                FontPreferences.resolveSansFont(
                                    size: 9.5,
                                    family: uiSansFontFamily,
                                    weight: .medium
                                )
                            )
                    }
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
                .help("Copy code")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                colorScheme == .dark
                    ? Color.white.opacity(0.02)
                    : Color.black.opacity(0.015)
            )

            Rectangle()
                .fill(codeBorder)
                .frame(height: 0.5)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(FontPreferences.resolveCodeFont(size: codeFontSize, family: uiCodeFontFamily))
                    .foregroundStyle(.primary.opacity(0.85))
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(codeBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(codeBorder, lineWidth: 0.5)
        )
    }

    func mermaidBlockView(code: String) -> some View {
        MermaidDiagramView(
            mermaidCode: code,
            accentColor: accentColor
        )
    }

    // MARK: - Table Rendering

    func tableView(headers: [String], rows: [[String]]) -> some View {
        let colCount = headers.count
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(headers.enumerated()), id: \.offset) { idx, header in
                    Text(header)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(h2Color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                    if idx < colCount - 1 {
                        Rectangle()
                            .fill(codeBorder)
                            .frame(width: 0.5)
                    }
                }
            }
            .background(accentColor.opacity(colorScheme == .dark ? 0.06 : 0.04))

            Rectangle().fill(codeBorder).frame(height: 0.5)

            ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                HStack(spacing: 0) {
                    ForEach(0..<colCount, id: \.self) { colIdx in
                        let cellText = colIdx < row.count ? row[colIdx] : ""
                        inlineMarkdown(cellText, fontSize: 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        if colIdx < colCount - 1 {
                            Rectangle()
                                .fill(codeBorder)
                                .frame(width: 0.5)
                        }
                    }
                }
                .background(
                    rowIdx % 2 == 1
                        ? codeBackground.opacity(0.5)
                        : Color.clear
                )

                if rowIdx < rows.count - 1 {
                    Rectangle().fill(codeBorder).frame(height: 0.5)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(codeBorder, lineWidth: 0.5)
        )
    }
}
