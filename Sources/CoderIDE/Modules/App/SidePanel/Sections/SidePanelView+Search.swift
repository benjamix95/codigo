import SwiftUI
import CoderEngine
import Foundation

extension SidePanelView {
    var searchPanelContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
                TextField("Search in workspace…", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .onSubmit { performSearch() }
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DesignSystem.Colors.backgroundPrimary.opacity(0.78))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(DesignSystem.Colors.borderSubtle, lineWidth: 0.5)
            )

            if searchResults.isEmpty && !searchQuery.isEmpty {
                VStack(spacing: 6) {
                    Text("Nessun risultato")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(searchResults.prefix(200).enumerated()), id: \.offset) { _, result in
                            Button {
                                openFilesStore.openFile(result.path)
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "doc.text.magnifyingglass")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(DesignSystem.Colors.info)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text((result.path as NSString).lastPathComponent)
                                            .font(.system(size: 11.5, weight: .semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(EditorPathResolver.displayPath(result.path, roots: context?.folderPaths ?? []))
                                            .font(.system(size: 9.5, design: .monospaced))
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                        Text("L\(result.line)  \(result.text)")
                                            .font(.system(size: 10.5, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.white.opacity(0.03))
                                )
                            }
                            .buttonStyle(.plain)
                            .hoverHighlight(Color.white.opacity(0.03))
                        }
                    }
                }
            }
        }
        .padding(10)
    }

    private func performSearch() {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, let ctx = context else { searchResults = []; return }

        Task {
            var results: [(path: String, line: Int, text: String)] = []
            for root in ctx.folderPaths {
                await searchInDirectory(root, query: q, results: &results, maxResults: 200)
            }
            await MainActor.run { searchResults = results }
        }
    }

    private func searchInDirectory(
        _ dir: String,
        query: String,
        results: inout [(path: String, line: Int, text: String)],
        maxResults: Int
    ) async {
        guard results.count < maxResults else { return }
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
        let filtered = items.filter { !$0.hasPrefix(".") && !Self.excludedDirs.contains($0) }

        for item in filtered {
            guard results.count < maxResults else { return }
            let path = (dir as NSString).appendingPathComponent(item)
            if isDirectory(path) {
                await searchInDirectory(path, query: query, results: &results, maxResults: maxResults)
            } else {
                guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
                let lines = content.components(separatedBy: .newlines)
                for (i, line) in lines.enumerated() {
                    guard results.count < maxResults else { break }
                    if line.localizedCaseInsensitiveContains(query) {
                        results.append((path: path, line: i + 1, text: line.trimmingCharacters(in: .whitespaces)))
                    }
                }
            }
        }
    }
}
