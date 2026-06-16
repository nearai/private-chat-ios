import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct AssistantAvatar: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.brandAccent.opacity(0.10))
            Image(systemName: "lock.shield.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.brandAccent)
        }
        .frame(width: 30, height: 30)
    }
}

struct MessageAttachmentStrip: View {
    let attachments: [ChatAttachment]
    /// Optional async fetch for image file content — used to render inline
    /// thumbnails on sent messages. Pass nil to skip image rendering.
    var fetchImageContent: ((String) async -> Data?)? = nil

    private var imageAttachments: [ChatAttachment] {
        guard fetchImageContent != nil else { return [] }
        return attachments.filter { $0.isNativeVisionImage }
    }

    private var nonImageAttachments: [ChatAttachment] {
        guard fetchImageContent != nil else { return attachments }
        return attachments.filter { !$0.isNativeVisionImage }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !imageAttachments.isEmpty, let fetch = fetchImageContent {
                MessageImageThumbnailRow(attachments: imageAttachments, fetchContent: fetch)
            }
            ForEach(nonImageAttachments) { attachment in
                Label {
                    Text(attachment.name)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: attachment.systemImageName)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

private struct MessageImageThumbnailRow: View {
    let attachments: [ChatAttachment]
    let fetchContent: (String) async -> Data?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    MessageImageThumbnailCell(attachment: attachment, fetchContent: fetchContent)
                }
            }
        }
    }
}

private struct MessageImageThumbnailCell: View {
    let attachment: ChatAttachment
    let fetchContent: (String) async -> Data?

    @State private var imageData: Data? = nil
    @State private var isLoading = false
    @State private var showingFullScreen = false

    var body: some View {
        Group {
            #if canImport(UIKit)
            if let data = imageData, let uiImage = UIImage(data: data) {
                Button {
                    showingFullScreen = true
                } label: {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: 240)
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .fullScreenCover(isPresented: $showingFullScreen) {
                    FullScreenImageView(image: uiImage)
                }
            } else if isLoading {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.appSecondaryBackground)
                    .frame(width: 120, height: 80)
                    .overlay {
                        ProgressView()
                            .controlSize(.small)
                    }
            } else {
                // Placeholder while task hasn't started yet — avoids zero-size layout flash
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.appSecondaryBackground)
                    .frame(width: 120, height: 80)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }
            #else
            Label(attachment.name, systemImage: attachment.systemImageName)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            #endif
        }
        .task(id: attachment.id) {
            guard imageData == nil else { return }
            isLoading = true
            let data = await fetchContent(attachment.id)
            isLoading = false
            imageData = data
        }
    }
}

#if canImport(UIKit)
private struct FullScreenImageView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(20)
            }
            .buttonStyle(.plain)
        }
        .statusBarHidden()
    }
}
#endif
