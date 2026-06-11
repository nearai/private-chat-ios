import SwiftUI

/// One-line composer caption that says whether an attached document's TEXT
/// will reach the model — the trust gap behind "the app passed me the
/// filename but no content". Renders nothing when no document is staged.
struct DocumentContextIndicator: View {
    let attachments: [ChatAttachment]
    let stagingStore: AttachmentStagingStore

    var body: some View {
        if let status {
            HStack(spacing: 6) {
                Image(systemName: status.included ? "doc.text.magnifyingglass" : "doc")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(status.included ? Color.brandAccent : Color.textTertiary)
                Text(status.text)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 2)
            .accessibilityIdentifier("composer.documentContext")
        }
    }

    private struct Status {
        var text: String
        var included: Bool
    }

    private var status: Status? {
        let documentAttachments = attachments.filter { attachment in
            attachment.isLocalOnly ||
                AttachmentStagingStore.isRecoverableDocumentText(attachment) ||
                stagingStore.hasDocumentText(for: attachment.id)
        }
        guard let first = documentAttachments.first else { return nil }
        let readableCount = documentAttachments.filter {
            stagingStore.hasDocumentText(for: $0.id) || AttachmentStagingStore.isRecoverableDocumentText($0)
        }.count
        if readableCount > 0 {
            let extra = documentAttachments.count > 1 ? " +\(documentAttachments.count - 1) more" : ""
            return Status(text: "Reading \(first.name)\(extra) — text goes to the model", included: true)
        }
        return Status(text: "\(first.name) attached — text not extracted on this route", included: false)
    }
}
