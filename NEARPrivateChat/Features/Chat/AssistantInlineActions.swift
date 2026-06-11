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

    var body: some View {
        // Width-constrained so trailing affordances (the sources pill) clip at
        // the scroll edge instead of bleeding past the screen.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                actionButton(symbolName: "doc.on.doc", label: "Copy", action: onCopy)
                exportMenu
                actionButton(symbolName: "arrow.clockwise", label: "Regenerate", action: onRegenerate)
                if canOpen {
                    actionButton(symbolName: "rectangle.expand.vertical", label: "Open Output", action: onOpen)
                }
                actionButton(symbolName: "checkmark.shield", label: "Copy Device-Signed Snippet", action: onCopySigned)
                saveButton
                if sourceCount > 0 {
                    Button(action: onSources) {
                        HStack(spacing: 7) {
                            ZStack {
                                Circle()
                                    .fill(Color.trustVerified.opacity(0.20))
                                Image(systemName: "link")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.trustVerified)
                            }
                            .frame(width: 24, height: 24)
                            Text(sourceButtonLabel)
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(.secondary)
                        .frame(height: 34)
                        .padding(.horizontal, 8)
                        .background(Color.clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(sourceCount == 1 ? "Open source" : "Open \(sourceCount) sources")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }

    private var exportMenu: some View {
        Menu {
            Button {
                onExport(.markdown)
            } label: {
                Label("Markdown", systemImage: "doc.plaintext")
            }
            Button {
                onExport(.pdf)
            } label: {
                Label("PDF", systemImage: "doc.richtext")
            }
            Button {
                onExport(.docx)
            } label: {
                Label("Word Document", systemImage: "doc")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.title3.weight(.regular))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(Color.clear, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Export Answer")
    }

    private var saveButton: some View {
        Button(action: onSave) {
            Image(systemName: saveSymbolName)
                .font(.title3.weight(.regular))
                .foregroundStyle(saveForeground)
                .frame(width: 34, height: 34)
                .background(saveBackground, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(isSavedToProject)
        .accessibilityLabel(saveAccessibilityLabel)
    }

    private var sourceButtonLabel: String {
        "\(sourceCount) source\(sourceCount == 1 ? "" : "s")"
    }

    private func actionButton(symbolName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.title3.weight(.regular))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(Color.clear, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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

    private var saveForeground: Color {
        isSavedToProject || canSaveToProject ? Color.brandAccent : .secondary
    }

    private var saveBackground: Color {
        isSavedToProject || canSaveToProject ? Color.brandAccent.opacity(0.10) : Color.appSecondaryBackground
    }

    private var saveAccessibilityLabel: String {
        if isSavedToProject {
            return "Saved to Project"
        }
        return canSaveToProject ? "Save to Project" : "Select a Project to Save"
    }
}
