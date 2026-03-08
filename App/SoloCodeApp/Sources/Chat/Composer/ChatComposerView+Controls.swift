import SwiftUI

extension ChatComposerView {
    internal var attachedAttachmentsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: isIDEStyle ? 6 : 8) {
                ForEach(Array(attachedAttachments.enumerated()), id: \.element.id) { index, item in
                    if item.kind == .image {
                        ZStack(alignment: .topTrailing) {
                            composerImagePreview(for: item)
                            Button {
                                attachedAttachments.remove(at: index)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(3)
                                    .background(Color.black.opacity(0.55), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .offset(x: 4, y: -4)
                        }
                    } else {
                        HStack(spacing: 8) {
                            attachmentPreview(for: item)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.originalName)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if let size = item.sizeBytes {
                                    Text(readableBytes(size))
                                        .font(.system(size: 9.5, weight: .regular))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: 190, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            Text(kindLabel(item.kind))
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.secondary.opacity(0.85))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.07), in: Capsule())
                            Button {
                                attachedAttachments.remove(at: index)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .padding(4)
                                    .background(Color.white.opacity(0.08), in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, isIDEStyle ? 7 : 8)
                        .padding(.vertical, isIDEStyle ? 5 : 6)
                        .background(
                            RoundedRectangle(cornerRadius: isIDEStyle ? 12 : 16, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: isIDEStyle ? 12 : 16, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.11), lineWidth: 0.6)
                        )
                    }
                }
            }
        }
    }

    internal var composerSurfaceGradient: LinearGradient {
        let gray = isIDEStyle
            ? Color(red: 34 / 255, green: 34 / 255, blue: 36 / 255)
            : Color(red: 42 / 255, green: 42 / 255, blue: 42 / 255)
        return LinearGradient(
            stops: [
                .init(color: gray.opacity(0.98), location: 0.0),
                .init(color: gray.opacity(0.96), location: 0.38),
                .init(color: gray.opacity(0.96), location: 1.0),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    internal func readableBytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    internal func iconForAttachment(_ kind: ChatAttachmentKind) -> String {
        switch kind {
        case .image: return "photo"
        case .document: return "doc.text"
        case .file: return "paperclip"
        }
    }

    internal func kindLabel(_ kind: ChatAttachmentKind) -> String {
        switch kind {
        case .image: return "Image"
        case .document: return "Doc"
        case .file: return "File"
        }
    }

    internal func appendAttachments(_ incoming: [ComposerAttachment]) {
        guard !incoming.isEmpty else { return }
        var uniqueByPath = Set(attachedAttachments.map { $0.url.standardizedFileURL.path })
        for item in incoming {
            guard attachedAttachments.count < AttachmentIntakeService.maxAttachmentsPerMessage else { break }
            if let size = item.sizeBytes, size > AttachmentIntakeService.maxAttachmentSizeBytes {
                continue
            }
            let path = item.url.standardizedFileURL.path
            if uniqueByPath.insert(path).inserted {
                attachedAttachments.append(item)
            }
        }
    }
}
