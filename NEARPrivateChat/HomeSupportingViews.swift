import SwiftUI

struct SetupLaunchCard: View {
    let plan: AppSetupPlan
    let onPrimaryAction: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 38, height: 38)
                    .background(Color.appSymbolBlueBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Setup ready")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.primaryAction)
                    Text(plan.launchCardTitle)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(plan.launchCardSubtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if !plan.launchCardMetadata.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(plan.launchCardMetadata, id: \.self) { item in
                            SetupLaunchPill(title: item)
                        }
                    }
                    .padding(.horizontal, 1)
                }
                .scrollClipDisabled()
            }

            if let firstRunDraft = plan.firstRunDraft {
                VStack(alignment: .leading, spacing: 5) {
                    Text("First prompt")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.textSecondary)
                    Text(firstRunDraft)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Text(plan.readinessStatus)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button(action: onPrimaryAction) {
                    Label(primaryActionTitle, systemImage: primaryActionSymbolName)
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(Color.primaryAction, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button("Not now", action: onDismiss)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(height: 44)
                    .padding(.horizontal, 12)
                    .background(Color.secondarySurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.brandBlue.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: Color.brandBlue.opacity(0.05), radius: 12, y: 6)
    }

    private var primaryActionTitle: String {
        switch plan.modelRoute {
        case .ironclaw:
            return "Open agent prompt"
        case .council:
            return "Open council prompt"
        case .privateModel:
            return "Open first prompt"
        }
    }

    private var primaryActionSymbolName: String {
        switch plan.modelRoute {
        case .ironclaw:
            return "terminal"
        case .council:
            return "square.grid.2x2"
        case .privateModel:
            return "arrow.right"
        }
    }
}

struct SetupLaunchPill: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Color.secondarySurface, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.appBorder, lineWidth: 1)
            }
    }
}

struct HomeSurfaceBackground: View {
    var body: some View {
        ZStack {
            Color.appBackground
            LinearGradient(
                colors: [
                    Color.brandBlue.opacity(0.10),
                    Color.brandSky.opacity(0.05),
                    Color.clear,
                    Color.clear
                ],
                startPoint: .topTrailing,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
    }
}

struct ConversationRow: View {
    let conversation: ConversationSummary
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            SidebarSymbol(
                symbolName: conversation.isPinned ? "pin.fill" : "bubble.left",
                isSelected: isSelected || conversation.isPinned,
                isAction: false
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.title)
                    .font(.body.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let createdAt = conversation.createdAt {
                    Text(Self.timestampText(for: Date(timeIntervalSince1970: createdAt)))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }
            Spacer(minLength: 0)

            if isSelected {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.brandBlue)
                    .frame(width: 4, height: 28)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(isSelected ? Color.brandBlue.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.brandBlue.opacity(0.10), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
    }

    private static func timestampText(for date: Date) -> String {
        let elapsed = max(0, Date().timeIntervalSince(date))
        if elapsed < 60 {
            return "Just now"
        }
        if elapsed < 3600 {
            return "\(Int(elapsed / 60))m ago"
        }
        if elapsed < 86_400 {
            return "\(Int(elapsed / 3600))h ago"
        }
        if elapsed < 604_800 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

struct SidebarSearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.body)
                .tokenInputTraits()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.brandBlue.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: Color.brandBlue.opacity(0.05), radius: 12, y: 6)
    }
}

struct HomeSectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var actionSymbolName: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 4) {
                        if let actionSymbolName {
                            Image(systemName: actionSymbolName)
                                .font(.caption.weight(.bold))
                        }
                        Text(actionTitle)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Color.primaryAction)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 6)
        .padding(.trailing, 6)
    }
}

struct HomeHeroActions: View {
    let showsAgent: Bool
    let projectTitle: String
    let onAgent: () -> Void
    let onProject: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            if showsAgent {
                HomeTextActionButton(title: "Run Agent", symbolName: "terminal", action: onAgent)
            }

            HomeTextActionButton(title: projectTitle, symbolName: "folder", action: onProject)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }
}

struct HomeTextActionButton: View {
    let title: String
    let symbolName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbolName)
                    .font(.caption.weight(.bold))
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(Color.textSecondary)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
    }
}

struct HomeFilterStrip: View {
    @Binding var selectedFilter: HomeFilter
    let counts: [HomeFilter: Int]
    let onSelect: (HomeFilter) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            filterButtons

            Menu {
                ForEach(HomeFilter.allCases) { filter in
                    Button {
                        onSelect(filter)
                    } label: {
                        Label(filter.title, systemImage: filter.symbolName)
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: selectedFilter.symbolName)
                    Text("\(selectedFilter.title) chats")
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
            }
        }
        .padding(4)
        .background(Color.appPanelBackground.opacity(0.86), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }

    private var filterButtons: some View {
        HStack(spacing: 6) {
            ForEach(HomeFilter.allCases) { filter in
                Button {
                    onSelect(filter)
                } label: {
                    filterLabel(for: filter)
                }
                .buttonStyle(.plain)
                .accessibilityValue(selectedFilter == filter ? "Selected" : "")
            }
        }
    }

    private func filterLabel(for filter: HomeFilter) -> some View {
        let isSelected = selectedFilter == filter
        return HStack(spacing: 5) {
            Image(systemName: filter.symbolName)
                .font(.caption.weight(.bold))
            Text(filter.title)
                .font(.caption.weight(isSelected ? .bold : .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            if let count = counts[filter], count > 0 {
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isSelected ? Color.primaryAction : Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .padding(.horizontal, 5)
                    .frame(height: 18)
                    .background(
                        isSelected ? Color.primaryAction.opacity(0.12) : Color.appSecondaryBackground,
                        in: Capsule()
                    )
            }
        }
        .foregroundStyle(isSelected ? Color.primaryAction : Color.textSecondary)
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .background(
            isSelected ? Color.primaryAction.opacity(0.10) : Color.clear,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.primaryAction.opacity(0.14), lineWidth: 1)
            }
        }
    }
}

struct HomeRecentsRow: View {
    let conversations: [ConversationSummary]
    let projectNameForConversation: (ConversationSummary) -> String?
    let onOpenConversation: (ConversationSummary) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(conversations) { conversation in
                    HomeRecentCard(
                        conversation: conversation,
                        projectName: projectNameForConversation(conversation),
                        onOpen: { onOpenConversation(conversation) }
                    )
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }
}

struct HomeRecentCard: View {
    let conversation: ConversationSummary
    let projectName: String?
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Text(conversation.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "arrow.forward.circle.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.primaryAction)
                }

                Text(projectName ?? "Private chat")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Text(timestampText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text("Resume")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.primaryAction)
                }
            }
            .padding(12)
            .frame(minWidth: 222, idealWidth: 222, maxWidth: 222, minHeight: 104, alignment: .topLeading)
            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.appBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var timestampText: String {
        guard let createdAt = conversation.createdAt else { return "Recent" }
        let date = Date(timeIntervalSince1970: createdAt)
        let elapsed = max(0, Date().timeIntervalSince(date))
        if elapsed < 60 {
            return "Just now"
        }
        if elapsed < 3600 {
            return "\(Int(elapsed / 60))m ago"
        }
        if elapsed < 86_400 {
            return "\(Int(elapsed / 3600))h ago"
        }
        if elapsed < 604_800 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

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
                        .lineLimit(1)
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
        .shadow(color: Color.brandBlue.opacity(0.14), radius: 18, y: 8)
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
                        Color(red: 0.006, green: 0.16, blue: 0.28),
                        Color(red: 0.0, green: 0.38, blue: 0.72)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(alignment: .topTrailing) {
                LinearGradient(
                    colors: [
                        Color.brandBlue.opacity(0.78),
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
            isSelected ? (tintBackground ?? Color.brandBlue.opacity(0.07)) : Color.clear,
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
            AccountSettingsView(onRunSetupAgain: onRunSetupAgain)
                .environmentObject(sessionStore)
                .environmentObject(chatStore)
        }
    }
}
