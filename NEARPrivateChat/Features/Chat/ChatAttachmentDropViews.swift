import SwiftUI

struct AttachmentDropTargetOverlay: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.actionPrimary.opacity(0.08))
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    Color.actionPrimary.opacity(0.72),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 5])
                )

            VStack(spacing: 10) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.actionPrimary)
                    .frame(width: 46, height: 46)
                    .background(Color.actionPrimary.opacity(0.12), in: Circle())

                VStack(spacing: 3) {
                    Text("Drop files to attach")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Up to five files")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.appBorder, lineWidth: 1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

enum ChatAutoScrollAnchor: Equatable {
    case top
    case bottom

    var unitPoint: UnitPoint {
        switch self {
        case .top:
            return .top
        case .bottom:
            return .bottom
        }
    }
}

struct ChatAutoScrollSignature: Equatable {
    let targetID: String?
    let targetAnchor: ChatAutoScrollAnchor
    let messageCount: Int
    let lastTextLength: Int
    let lastStatus: String?
    let isStreaming: Bool

    init(displayItems: [ChatDisplayItem], messages: [ChatMessage], isStreaming: Bool) {
        let lastMessage = messages.last
        let lastDisplayItem = displayItems.last
        self.targetID = lastDisplayItem?.id
        if case .council = lastDisplayItem, !isStreaming {
            self.targetAnchor = .top
        } else {
            self.targetAnchor = .bottom
        }
        self.messageCount = messages.count
        self.lastTextLength = lastMessage?.text.count ?? 0
        self.lastStatus = lastMessage?.status
        self.isStreaming = isStreaming
    }
}
