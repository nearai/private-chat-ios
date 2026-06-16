import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ProjectContextStrip: View {
    let attachments: [ChatAttachment]
    let linkCount: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Label(contextLabel, systemImage: "folder")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.brandAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.brandAccent.opacity(0.10), in: Capsule())

                ForEach(attachments.prefix(4)) { attachment in
                    Label(attachment.name, systemImage: attachment.systemImageName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.appSecondaryBackground, in: Capsule())
                }
            }
        }
    }

    private var contextLabel: String {
        var parts: [String] = []
        if !attachments.isEmpty {
            parts.append(countLabel(attachments.count, singular: "file"))
        }
        if linkCount > 0 {
            parts.append(countLabel(linkCount, singular: "source link"))
        }
        return parts.isEmpty ? "Project context" : parts.joined(separator: " · ")
    }

    private func countLabel(_ count: Int, singular: String) -> String {
        "\(count) \(singular)\(count == 1 ? "" : "s")"
    }
}

struct AttachmentStrip: View {
    let attachments: [ChatAttachment]
    var showsMetadataOnly = false
    var thumbnailProvider: ((String) -> Data?)? = nil
    let onRemove: (ChatAttachment) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(attachments) { attachment in
                    HStack(spacing: 6) {
                        attachmentLeadingView(for: attachment)
                        VStack(alignment: .leading, spacing: 1) {
                            // Middle truncation keeps both the document name's start
                            // and its extension visible on narrow widths.
                            Text(attachmentShelfTitle(for: attachment))
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 180, alignment: .leading)
                            Text(attachmentShelfDetail(for: attachment))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(attachmentShelfTitle(for: attachment)), \(attachmentShelfDetail(for: attachment))")
                        Button {
                            AppHaptics.selection()
                            onRemove(attachment)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(attachment.name)")
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 56)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle.app(AppRadius.pill))
                }
            }
        }
    }

    @ViewBuilder
    private func attachmentLeadingView(for attachment: ChatAttachment) -> some View {
        #if canImport(UIKit)
        if attachment.isNativeVisionImage,
           let data = thumbnailProvider?(attachment.id),
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            defaultLeadingIcon(for: attachment)
        }
        #else
        defaultLeadingIcon(for: attachment)
        #endif
    }

    private func defaultLeadingIcon(for attachment: ChatAttachment) -> some View {
        Image(systemName: attachment.systemImageName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.brandAccent)
            .frame(width: 28, height: 28)
            .background(Color.brandAccent.opacity(0.09), in: RoundedRectangle.app(AppRadius.pill))
    }

    private func attachmentShelfTitle(for attachment: ChatAttachment) -> String {
        if attachment.isLocalPendingText {
            return "Large paste staged"
        }
        if attachment.kind == "pdf_text" {
            return "PDF text extracted"
        }
        return attachment.name
    }

    private func attachmentShelfDetail(for attachment: ChatAttachment) -> String {
        if showsMetadataOnly {
            var hostedParts = ["File names only", "filename plus prompt excerpts only"]
            if let displaySize = attachment.displaySize {
                hostedParts.append(displaySize)
            }
            return hostedParts.joined(separator: " · ")
        }

        var parts: [String] = []
        if attachment.isLocalPendingText {
            parts.append("Uploads as text on send")
            parts.append(attachment.name)
        } else if attachment.kind == "pdf_text" {
            parts.append("Readable text attachment")
            parts.append(attachment.name)
        } else {
            parts.append(attachment.displayKind)
        }
        if let displaySize = attachment.displaySize {
            parts.append(displaySize)
        }
        return parts.joined(separator: " · ")
    }
}
