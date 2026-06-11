import SwiftUI

struct LoadingHomeRow: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
    }
}

struct ProjectContextSearchRow: View {
    let match: HomeProjectContextMatch

    var body: some View {
        HStack(spacing: 12) {
            SidebarSymbol(
                symbolName: match.kind.symbolName,
                isSelected: false,
                isAction: true,
                tintColor: match.project.tintColor,
                backgroundColor: match.project.tintBackgroundColor,
                size: 32
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(match.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text("\(match.project.name) · \(match.kind.title)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let detail = match.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "arrow.up.right.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
    }
}

struct WorkspaceCommandHeader: View {
    let title: String
    let subtitle: String
    let onNewChat: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 11) {
                PrivacySeal(size: 46)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                    Text(subtitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.70))
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                }

                Spacer(minLength: 0)
            }

            Button(action: onNewChat) {
                HStack(spacing: 12) {
                    Image(systemName: "square.and.pencil")
                        .font(.headline.weight(.bold))
                        .frame(width: 30, height: 30)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ask NEAR")
                            .font(.headline.weight(.bold))
                            .lineLimit(1)
                        Text("Just type. NEAR handles routing.")
                            .font(.caption.weight(.semibold))
                            .opacity(0.72)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "arrow.right")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(Color.brandBlack)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(Color.brandSky, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background {
            CommandCardBackground(cornerRadius: 8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.11), lineWidth: 1)
        }
        .shadow(color: Color.brandAccent.opacity(0.14), radius: 18, y: 8)
    }
}

struct CommandCardBackground: View {
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.brandBlack,
                        Color.commandGradientMid,
                        Color.commandGradientEnd
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(alignment: .topTrailing) {
                LinearGradient(
                    colors: [
                        Color.brandAccent.opacity(0.78),
                        Color.brandSky.opacity(0.28),
                        Color.clear
                    ],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
    }
}

struct WorkspaceCommandButton: View {
    let title: String
    let symbolName: String
    let isPrimary: Bool
    var height: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbolName)
                .font(.subheadline.weight(.bold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(isPrimary ? Color.brandBlack : .white)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(isPrimary ? Color.brandSky : .white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(isPrimary ? 0 : 0.14), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

struct WorkspaceModeButton: View {
    let title: String
    let subtitle: String
    let symbolName: String
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: symbolName)
                    .font(.headline.weight(.bold))
                    .frame(width: 26, height: 22, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)
                    Text(subtitle)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                        .opacity(isPrimary ? 0.74 : 0.68)
                }
            }
            .foregroundStyle(isPrimary ? Color.brandBlack : .white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 72)
            .padding(.horizontal, 12)
            .background(isPrimary ? Color.brandSky : .white.opacity(0.13), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(isPrimary ? 0 : 0.15), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct StatusChip: View {
    let title: String
    let symbolName: String
    let isPrimary: Bool

    var body: some View {
        Label(title, systemImage: symbolName)
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(isPrimary ? Color.primaryAction : Color.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isPrimary ? Color.primaryAction.opacity(0.08) : Color.secondarySurface, in: Capsule())
    }
}

struct ProjectRow: View {
    let title: String
    let subtitle: String?
    let symbolName: String
    let isSelected: Bool
    var isAction = false
    var tintColor: Color = .primaryAction
    var tintBackground: Color? = nil

    var body: some View {
        HStack(spacing: 12) {
            SidebarSymbol(
                symbolName: symbolName,
                isSelected: isSelected,
                isAction: isAction,
                tintColor: tintColor,
                backgroundColor: tintBackground,
                size: 32
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(
            isSelected ? (tintBackground ?? Color.brandAccent.opacity(0.07)) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tintColor.opacity(0.12), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
    }
}

struct SidebarSymbol: View {
    let symbolName: String
    let isSelected: Bool
    let isAction: Bool
    var tintColor: Color = .primaryAction
    var backgroundColor: Color? = nil
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: symbolName)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(isSelected || isAction ? tintColor : .secondary)
            .frame(width: size, height: size)
            .background(
                (isSelected || isAction ? (backgroundColor ?? tintColor.opacity(0.11)) : Color.appSecondaryBackground.opacity(0.82)),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
    }
}

struct AccountToolbarButton: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var chatStore: ChatStore
    @State private var showingAccount = false
    let onRunSetupAgain: () -> Void

    var body: some View {
        Button {
            showingAccount = true
        } label: {
            Image(systemName: "person.crop.circle")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 36, height: 36)
                .background(Color.panel.opacity(0.82), in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.border, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Account")
        .sheet(isPresented: $showingAccount) {
            AccountSettingsView(
                onRunSetupAgain: onRunSetupAgain,
                isCurrentChatEmpty: { chatStore.selectedConversation == nil && chatStore.transcriptStore.messages.isEmpty }
            )
                .environmentObject(sessionStore)
        }
    }
}
