import Foundation

/// Store per i file aperti nell'editor, condiviso tra Sidebar e Editor panel
@MainActor
final class OpenFilesStore: ObservableObject {
    @Published var openFilePath: String?
    
    func openFile(_ path: String?) {
        openFilePath = path
    }
}
