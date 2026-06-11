import SwiftUI

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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(attachments) { attachment in
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
