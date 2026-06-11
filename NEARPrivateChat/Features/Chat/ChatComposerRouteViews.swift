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
                .minimumScaleFactor(0.86)
                .frame(maxWidth: 180, alignment: .leading)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .opacity(0.55)
            }
        }
        .foregroundStyle(isActive ? Color.actionPress : Color.textPrimary)
        .padding(.leading, 9)
        .padding(.trailing, 10)
        .frame(minHeight: 44)
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

struct ComposerRouteIconChip: View {
    let symbolName: String
    let isActive: Bool

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isActive ? Color.actionPress : Color.textPrimary)
            .frame(width: 30, height: 30)
            .background(background, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(border, lineWidth: 1)
            }
            .minimumTouchTarget()
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
                    .foregroundStyle(Color.brandAccent)
                    .frame(width: 28, height: 28)
                    .background(Color.appSymbolBlueBackground, in: RoundedRectangle.app(AppRadius.pill))

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
                        .frame(minHeight: 44)
                        .background(Color.primaryAction, in: RoundedRectangle.app(AppRadius.pill))
                }
                .buttonStyle(.plain)

                if issue.recoveryAction != .switchToPrivate {
                    Button(action: onSwitchPrivate) {
                        Text("Use Private")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.primaryAction)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .background(Color.appSecondaryBackground, in: RoundedRectangle.app(AppRadius.pill))
                            .overlay {
                                RoundedRectangle.app(AppRadius.pill)
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
            .minimumTouchTarget()
        }
        .padding(10)
        .background(Color.appPanelBackground, in: RoundedRectangle.app(AppRadius.pill))
        .overlay {
            RoundedRectangle.app(AppRadius.pill)
                .stroke(Color.brandAccent.opacity(0.16), lineWidth: 1)
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

/// One-tap disclosed recovery for a restricted private send: re-run THIS turn
/// via the cloud privacy proxy without changing the selected model. When no
/// cloud key is configured, the primary action becomes adding one.
struct ProxyRetryCard: View {
    let offer: ProxyRetryOffer
    let proxyDisplayName: String?
    let onAccept: () -> Void
    let onAddCloudKey: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "eye.slash")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.brandAccent)
                    .frame(width: 28, height: 28)
                    .background(Color.appSymbolBlueBackground, in: RoundedRectangle.app(AppRadius.pill))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Private route is busy")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(message)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Button(action: offer.proxyModelID == nil ? onAddCloudKey : onAccept) {
                    Label(primaryTitle, systemImage: offer.proxyModelID == nil ? "key" : "cloud")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background(Color.primaryAction, in: RoundedRectangle.app(AppRadius.pill))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("message.recovery.proxy")

                Button(action: onDecline) {
                    Text("Not now")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.primaryAction)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background(Color.appSecondaryBackground, in: RoundedRectangle.app(AppRadius.pill))
                        .overlay {
                            RoundedRectangle.app(AppRadius.pill)
                                .stroke(Color.appBorder, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color.appPanelBackground, in: RoundedRectangle.app(AppRadius.pill))
        .overlay {
            RoundedRectangle.app(AppRadius.pill)
                .stroke(Color.brandAccent.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Private route is busy. \(message)")
    }

    private var message: String {
        if offer.proxyModelID == nil {
            return "Add a NEAR AI Cloud key to answer this turn through the anonymizing privacy proxy, or retry private in a moment."
        }
        let name = proxyDisplayName ?? "a cloud model"
        return "Answer this turn through the anonymizing privacy proxy (\(name)). Your default model stays private."
    }

    private var primaryTitle: String {
        offer.proxyModelID == nil ? "Add NEAR AI Cloud key" : "Answer via privacy proxy"
    }
}
