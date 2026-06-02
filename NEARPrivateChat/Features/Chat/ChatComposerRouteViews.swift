import SwiftUI

struct ComposerRouteChip: View {
    let title: String
    let symbolName: String
    let isActive: Bool
    let showsChevron: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(.footnote)
                .fontWeight(.medium)
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .opacity(0.55)
            }
        }
        .foregroundStyle(isActive ? Color.actionPress : Color.textPrimary)
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .frame(height: 30)
        .background(background, in: Capsule())
        .overlay {
            Capsule()
                .stroke(border, lineWidth: 1)
        }
    }

    private var background: Color {
        isActive ? Color.actionFill : Color.appPanelBackground
    }

    private var border: Color {
        isActive ? Color.actionPrimary.opacity(0.30) : Color.appBorder
    }
}

struct RouteReadinessRecoveryCard: View {
    let issue: ChatStore.RouteReadinessIssue
    let onPrimaryAction: () -> Void
    let onSwitchPrivate: () -> Void
    let onViewCapabilities: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbolName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 28, height: 28)
                    .background(Color.appSymbolBlueBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(issue.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(issue.message)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Button(action: onPrimaryAction) {
                    Label(issue.recoveryTitle, systemImage: primarySymbolName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(Color.primaryAction, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                if issue.recoveryAction != .switchToPrivate {
                    Button(action: onSwitchPrivate) {
                        Text("Use Private")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.primaryAction)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.appBorder, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            Button(action: onViewCapabilities) {
                    Label("Open Capabilities", systemImage: "slider.horizontal.3")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.primaryAction)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.brandBlue.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(issue.title). \(issue.message)")
    }

    private var symbolName: String {
        switch issue.route {
        case .nearCloud: "key"
        case .hostedIronclaw: "terminal"
        case .council: "square.grid.2x2"
        }
    }

    private var primarySymbolName: String {
        switch issue.recoveryAction {
        case .addNearCloudKey: "key"
        case .configureIronClawEndpoint: "point.3.connected.trianglepath.dotted"
        case .switchToPrivate: "lock.shield"
        case .editCouncilLineup: "slider.horizontal.3"
        }
    }
}
