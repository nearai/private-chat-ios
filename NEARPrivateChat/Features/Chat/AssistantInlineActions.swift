import SwiftUI

struct AssistantInlineActions: View {
    let canSaveToProject: Bool
    let isSavedToProject: Bool
    let canOpen: Bool
    let sourceCount: Int
    let onCopy: () -> Void
    let onCopySigned: () -> Void
    let onExport: (ConversationExportFormat) -> Void
    let onRegenerate: () -> Void
    let onSave: () -> Void
    let onOpen: () -> Void
    let onSources: () -> Void
    @State private var showingMoreActions = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                compactActionButton(
                    symbolName: "doc.on.doc",
                    title: "Copy",
                    accessibilityIdentifier: "message.action.copy",
                    action: onCopy
                )

                if sourceCount > 0 {
                    compactActionButton(
                        symbolName: "link",
                        title: sourceButtonLabel,
                        tint: Color.trustVerified,
                        accessibilityIdentifier: "message.action.sources",
                        accessibilityLabel: sourceAccessibilityLabel,
                        action: onSources
                    )
                }

                if canOpen {
                    compactActionButton(
                        symbolName: "rectangle.expand.vertical",
                        title: "Open",
                        accessibilityIdentifier: "message.action.open",
                        action: onOpen
                    )
                }

                moreMenu
            }
            .padding(.trailing, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 1)
        .confirmationDialog("Answer actions", isPresented: $showingMoreActions, titleVisibility: .visible) {
            moreActionButtons
        }
    }

    private var moreMenu: some View {
        Button {
            showingMoreActions = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 44, height: 44)
                .background(Color.appPanelBackground, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.appBorder.opacity(0.7), lineWidth: 1)
                }
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More answer actions")
        .accessibilityIdentifier("message.action.more")
    }

    @ViewBuilder
    private var moreActionButtons: some View {
        if canOpen {
            Button("Open output") { onOpen() }
        }
        Button("Export Markdown") { onExport(.markdown) }
        Button("Export PDF") { onExport(.pdf) }
        Button("Export Word Document") { onExport(.docx) }
        Button("Copy signed snippet") { onCopySigned() }
        Button("Regenerate") { onRegenerate() }
        Button(saveLabel) { onSave() }
            .disabled(isSavedToProject)
    }

    private func compactActionButton(
        symbolName: String,
        title: String,
        tint: Color = Color.actionPrimary,
        accessibilityIdentifier: String,
        accessibilityLabel: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbolName)
                    .font(.caption.weight(.bold))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background(tint.opacity(0.08), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(tint.opacity(0.14), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? title)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var sourceButtonLabel: String {
        sourceCount > 99 ? "99+" : "\(sourceCount)"
    }

    private var sourceAccessibilityLabel: String {
        "\(sourceCount) source\(sourceCount == 1 ? "" : "s")"
    }

    private var saveLabel: String {
        if isSavedToProject {
            return "Saved"
        }
        return canSaveToProject ? "Save" : "Project"
    }

    private var saveSymbolName: String {
        if isSavedToProject {
            return "checkmark"
        }
        return canSaveToProject ? "bookmark.fill" : "bookmark"
    }
}
