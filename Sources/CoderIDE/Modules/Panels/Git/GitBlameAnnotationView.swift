import SwiftUI

// MARK: - Git Blame Annotation View

/// View per mostrare le annotations di git blame inline nell'editor.
struct GitBlameAnnotationView: View {
    let annotations: [GitBlameService.BlameAnnotation]
    let visibleLineRange: ClosedRange<Int>

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(visibleAnnotations) { annotation in
                annotationRow(annotation)
            }
        }
    }

    private var visibleAnnotations: [GitBlameService.BlameAnnotation] {
        annotations.filter { visibleLineRange.contains($0.line) }
    }

    private func annotationRow(_ annotation: GitBlameService.BlameAnnotation) -> some View {
        HStack(spacing: 6) {
            Text(annotation.author.components(separatedBy: " ").first ?? annotation.author)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: 80, alignment: .trailing)

            if let date = annotation.authorDate {
                Text(dateFormatter.string(from: date))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
                    .frame(width: 60)
            }

            Text(String(annotation.commitHash.prefix(7)))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.blue.opacity(0.7))
                .frame(width: 55)
        }
        .frame(height: 16)
        .padding(.horizontal, 4)
    }
}

// MARK: - Blame Gutter Provider

/// Provider per le annotations blame nella gutter dell'editor.
@MainActor
final class GitBlameGutterProvider: ObservableObject {
    @Published var annotations: [GitBlameService.BlameAnnotation] = []
    @Published var isLoading = false
    @Published var error: String?

    private let service = GitBlameService()

    func loadBlame(filePath: String, workspacePath: String) {
        isLoading = true
        error = nil

        Task { [weak self] in
            guard let self else { return }
            let result = await self.service.blame(
                filePath: filePath,
                workspacePath: workspacePath
            )
            await MainActor.run {
                self.annotations = result.annotations
                self.error = result.error
                self.isLoading = false
            }
        }
    }

    func clear() {
        annotations = []
        error = nil
    }
}
