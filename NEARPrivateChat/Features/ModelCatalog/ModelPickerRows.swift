import SwiftUI

// MARK: - Picker Row Components

struct ModelSpecSection<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)

            VStack(spacing: 0) {
                content
            }
            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.appBorder, lineWidth: 0.5)
            }
            .padding(.horizontal, 16)
        }
    }
}

enum ModelSpecTrailing {
    case none
    case checkmark
    case chevron
}

struct ModelSpecRow: View {
    let symbolName: String
    let symbolColor: Color
    let title: String
    let subtitle: String
    var badges: [String] = []
    let trailing: ModelSpecTrailing
    let isSelected: Bool
    let showsDivider: Bool
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: symbolName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isEnabled ? symbolColor : Color.textTertiary)
                        .frame(width: 22, height: 22)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.body)
                            .foregroundStyle(isEnabled ? Color.primary : Color.textSecondary)
                            .lineLimit(1)

                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        if !badges.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(Array(badges.prefix(3)), id: \.self) { badge in
                                    Text(badge)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Color.textSecondary)
                                        .lineLimit(1)
                                        .padding(.horizontal, 7)
                                        .frame(height: 20)
                                        .background(Color.appSecondaryBackground, in: Capsule())
                                }
                            }
                            .padding(.top, 3)
                        }
                    }

                    Spacer(minLength: 0)

                    trailingView
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(minHeight: 60)
                .background(isSelected ? Color.actionPrimary.opacity(0.10) : Color.clear)
                .contentShape(Rectangle())

                if showsDivider {
                    HStack(spacing: 0) {
                        Color.clear.frame(width: 52)
                        Rectangle()
                            .fill(Color.appHairline)
                            .frame(height: 0.5)
                    }
                    .frame(height: 0.5)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.48)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(rowAccessibilityValue)
        .accessibilityHint(isEnabled ? "Selects this model route." : subtitle)
    }

    private var rowAccessibilityValue: String {
        ([subtitle] + badges).joined(separator: ", ")
    }

    @ViewBuilder
    private var trailingView: some View {
        switch trailing {
        case .none:
            EmptyView()
        case .checkmark:
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.actionPrimary)
        case .chevron:
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
        }
    }
}

struct CouncilNumberedRow: View {
    let number: Int
    let title: String
    let subtitle: String
    let showsDivider: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(alignment: .center, spacing: 14) {
                Text("\(number)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.actionPrimary)
                    .frame(width: 22, height: 22)
                    .background(Color.actionPrimary.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 60)

            if showsDivider {
                HStack(spacing: 0) {
                    Color.clear.frame(width: 52)
                    Rectangle()
                        .fill(Color.appHairline)
                        .frame(height: 0.5)
                }
            }
        }
    }
}

extension ModelOption {
    var routeDisclosureBadges: [String] {
        if isNearCloudModel {
            return ["NEAR AI Cloud", "Privacy proxy"]
        }
        if isIronclawHostedModel {
            return ["Hosted IronClaw", "File names only"]
        }
        if isIronclawMobileRuntime {
            return ["IronClaw Mobile", "Outside proof"]
        }
        if isPrivateVerifiableChatModel {
            return ["NEAR Private", "Proof when fetched"]
        }
        return Array((["NEAR Private"] + capabilityBadges).prefix(3))
    }
}
