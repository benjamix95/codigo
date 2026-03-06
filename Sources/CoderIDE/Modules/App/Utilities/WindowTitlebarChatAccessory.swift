import AppKit
import SwiftUI

struct WindowTitlebarChatInfo: Equatable {
    let title: String
    let projectName: String?
    let projectPath: String?

    init?(title: String, projectName: String?, projectPath: String?) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }
        self.title = trimmedTitle

        let trimmedProjectName = projectName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedProjectName.isEmpty || projectPath?.isEmpty != false {
            self.projectName = nil
            self.projectPath = nil
        } else {
            self.projectName = trimmedProjectName
            self.projectPath = projectPath
        }
    }

    init?(userInfo: [AnyHashable: Any]?) {
        guard
            let userInfo,
            let title = userInfo["title"] as? String
        else {
            return nil
        }
        self.init(
            title: title,
            projectName: userInfo["projectName"] as? String,
            projectPath: userInfo["projectPath"] as? String
        )
    }

    var notificationUserInfo: [AnyHashable: Any] {
        var payload: [AnyHashable: Any] = ["title": title]
        if let projectName { payload["projectName"] = projectName }
        if let projectPath { payload["projectPath"] = projectPath }
        return payload
    }
}

extension Notification.Name {
    static let windowTitlebarChatInfoDidChange = Notification.Name("CoderIDE.WindowTitlebarChatInfoDidChange")
}

enum WindowTitlebarChatAccessoryBridge {
    static func post(info: WindowTitlebarChatInfo?) {
        NotificationCenter.default.post(
            name: .windowTitlebarChatInfoDidChange,
            object: nil,
            userInfo: info?.notificationUserInfo
        )
    }
}

struct WindowTitlebarChatAccessoryView: View {
    let info: WindowTitlebarChatInfo
    let openProject: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(info.title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            if let projectName = info.projectName,
               let projectPath = info.projectPath {
                Button(action: openProject) {
                    Text(projectName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .buttonStyle(.plain)
                .help("Open folder \(projectPath)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
