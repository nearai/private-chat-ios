import SwiftUI

struct AttestedMessageChip: View {
    let status: AttestationStatus
    let modelID: String?

    var body: some View {
        let isCovered = status.coverage(for: modelID) == .covered
        let copy = status.userFacingCopy()
        Label(copy.badge, systemImage: status.symbolName)
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(isCovered ? Color.verifiedGreen : status.tintColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(status.tintColor.opacity(0.10), in: Capsule())
            .accessibilityHint(copy.detail)
    }
}

struct ResponseVariantPicker: View {
    let variant: MessageBranchVariant
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            variantButton(
                symbolName: "chevron.left",
                responseID: variant.previousResponseID,
                label: "Previous response variant"
            )

            Text("Response \(variant.displayIndex) of \(variant.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            variantButton(
                symbolName: "chevron.right",
                responseID: variant.nextResponseID,
                label: "Next response variant"
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.appPanelBackground, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.appBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Response variant \(variant.displayIndex) of \(variant.count)")
    }

    private func variantButton(symbolName: String, responseID: String?, label: String) -> some View {
        Button {
            if let responseID {
                onSelect(responseID)
            }
        } label: {
            Image(systemName: symbolName)
                .font(.caption.weight(.bold))
                .frame(width: 24, height: 24)
                .foregroundStyle(responseID == nil ? Color.secondary.opacity(0.45) : Color.brandAccent)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(responseID == nil)
        .accessibilityLabel(label)
        .help(label)
    }
}
