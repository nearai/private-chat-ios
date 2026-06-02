import SwiftUI

struct CapabilityStatusItemModel: Identifiable {
    let title: String
    let value: String
    let tint: Color

    var id: String { title }
}

struct CapabilityStatusStrip: View {
    let items: [CapabilityStatusItemModel]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(item.value)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(item.tint)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.appPanelBackground, in: Capsule())
                }
            }
        }
    }
}

struct CapabilityCardAction {
    enum Role {
        case primary
        case secondary
    }

    let title: String
    let systemImage: String
    let role: Role
    let action: () -> Void
}

struct CapabilityCard: View {
    let iconName: String
    let title: String
    let status: String
    let statusColor: Color
    let summary: String
    let trustLine: String
    let detail: String
    let primaryAction: CapabilityCardAction?
    let secondaryAction: CapabilityCardAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .frame(width: 38, height: 38)
                    .background(statusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(status)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor)
                }

                Spacer(minLength: 0)
            }

            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(trustLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if primaryAction != nil || secondaryAction != nil {
                HStack(spacing: 8) {
                    if let primaryAction {
                        CapabilityActionButton(action: primaryAction)
                    }
                    if let secondaryAction {
                        CapabilityActionButton(action: secondaryAction)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.border, lineWidth: 1)
        }
    }
}

struct CapabilityActionButton: View {
    let action: CapabilityCardAction

    var body: some View {
        Button(action: action.action) {
            Label(action.title, systemImage: action.systemImage)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .foregroundStyle(action.role == .primary ? Color.white : Color.primaryAction)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(backgroundShape)
                .overlay {
                    if action.role == .secondary {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.appBorder, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var backgroundShape: some View {
        if action.role == .primary {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primaryAction)
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.appSecondaryBackground)
        }
    }
}
