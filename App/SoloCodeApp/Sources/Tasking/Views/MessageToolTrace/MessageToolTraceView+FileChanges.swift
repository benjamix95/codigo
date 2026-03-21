import SwiftUI

extension MessageToolTraceView {
    // MARK: - File Changes Section

    func fileChangesSectionView(derived: DerivedState) -> some View {
        let compactDiff = compactDiffPreview(fileChanges: derived.fileChanges)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                Text("\(derived.fileChanges.count) \(pluralized("file", count: derived.fileChanges.count)) changed")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Text("+\(derived.fileAddedTotal)")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.success)
                Text("-\(derived.fileRemovedTotal)")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.error)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)

            ForEach(derived.fileChanges) { change in
                fileChangeRow(change)
            }

            if let compactDiff {
                compactDiffSection(diff: compactDiff, derived: derived)
            } else if !derived.fileChanges.isEmpty {
                buildDiffButton()
            }
        }
    }

    @ViewBuilder
    func fileChangeRow(_ change: ToolTraceFileChange) -> some View {
        let isExpandedRow = expandedFileIds.contains(change.id)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: change.kind == .created ? "plus.circle" : change.kind == .deleted ? "minus.circle" : "pencil.circle")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(change.kind == .created ? DesignSystem.Colors.success : change.kind == .deleted ? DesignSystem.Colors.error : DesignSystem.Colors.info)

                Button {
                    openFileForChange(change)
                } label: {
                    Text(change.basename)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)

                if let path = change.path, !path.isEmpty {
                    Text(shortenedPath(path))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.textQuaternary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text("+\(max(0, change.added))")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.success)
                Text("-\(max(0, change.removed))")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.error)

                Button {
                    toggleExpandedFile(change)
                } label: {
                    Image(systemName: isExpandedRow ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.textQuaternary)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)

            if isExpandedRow {
                if loadingPreviewIds.contains(change.id) {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Loading diff...")
                            .font(.system(size: 10))
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                } else if let preview = filePreviewByEventId[change.id] {
                    if case .diff = preview {
                        diffBlock(preview.text)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                    } else {
                        codeBlock(label: preview.label, value: preview.text)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(DesignSystem.Colors.backgroundSecondary.opacity(0.25))
        )
    }

    @ViewBuilder
    func compactDiffSection(diff: String, derived: DerivedState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.12)) {
                    isCompactDiffExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    Text("Unified diff")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Spacer(minLength: 0)
                    Image(systemName: isCompactDiffExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.textQuaternary)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isCompactDiffExpanded {
                diffBlock(diff)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(DesignSystem.Colors.backgroundSecondary.opacity(0.25))
        )
    }

    @ViewBuilder
    func buildDiffButton() -> some View {
        if !isCompactDiffLoading {
            Button {
                loadCompactDiffPreviewIfNeeded()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    Text("Build unified diff")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Building diff...")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
        }
    }
}
