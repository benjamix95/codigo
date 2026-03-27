import AppKit
import SwiftUI

enum MessageLinkDisposition: Equatable {
    case file(String)
    case external(URL)
    case ignored
}

enum MessageLinkRouter {
    private static let allowedExternalSchemes: Set<String> = [
        "http",
        "https",
        "mailto",
        "x-xcode-log"
    ]

    static func disposition(for url: URL) -> MessageLinkDisposition {
        if url.isFileURL {
            return .file(url.path)
        }

        guard let scheme = url.scheme?.lowercased(),
              allowedExternalSchemes.contains(scheme) else {
            return .ignored
        }

        return .external(url)
    }

    @MainActor
    static func open(_ url: URL, onFileClicked: (String) -> Void) -> OpenURLAction.Result {
        switch disposition(for: url) {
        case .file(let path):
            onFileClicked(path)
            return .handled
        case .external(let externalURL):
            NSWorkspace.shared.open(externalURL)
            return .handled
        case .ignored:
            return .discarded
        }
    }
}
