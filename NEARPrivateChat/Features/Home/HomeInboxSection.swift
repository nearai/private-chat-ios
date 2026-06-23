import SwiftUI

struct HomeInboxSectionPlan: Equatable {
    let selectedFilter: HomeFilter
    let searchQuery: String
    let activeConversationCount: Int
    let activeProjectCount: Int
    let projectContextMatchCount: Int
    let sharedWithMeCount: Int
    let archivedConversationCount: Int
    let archivedProjectCount: Int

    init(
        selectedFilter: HomeFilter,
        searchQuery: String,
        activeConversationCount: Int,
        activeProjectCount: Int,
        projectContextMatchCount: Int,
        sharedWithMeCount: Int,
        archivedConversationCount: Int,
        archivedProjectCount: Int
    ) {
        self.selectedFilter = selectedFilter
        self.searchQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        self.activeConversationCount = activeConversationCount
        self.activeProjectCount = activeProjectCount
        self.projectContextMatchCount = projectContextMatchCount
        self.sharedWithMeCount = sharedWithMeCount
        self.archivedConversationCount = archivedConversationCount
        self.archivedProjectCount = archivedProjectCount
    }

    var isSearching: Bool {
        !searchQuery.isEmpty
    }

    var filterCounts: [HomeFilter: Int] {
        [
            .all: activeConversationCount + activeProjectCount + projectContextMatchCount,
            .shared: sharedWithMeCount,
            .archived: archivedConversationCount + archivedProjectCount
        ]
    }

    var archivedItemCount: Int {
        archivedConversationCount + archivedProjectCount
    }

    var showsSharedLibraryShortcut: Bool {
        sharedWithMeCount > 0
    }

    var showsArchivedLibraryShortcut: Bool {
        archivedItemCount > 0
    }

    var showsLibraryShortcuts: Bool {
        showsSharedLibraryShortcut || showsArchivedLibraryShortcut
    }

    var showsActiveInbox: Bool {
        selectedFilter == .all
    }

    var showsProjectContext: Bool {
        showsActiveInbox && projectContextMatchCount > 0
    }

    var showsProjects: Bool {
        showsActiveInbox && activeProjectCount > 0
    }

    var showsConversations: Bool {
        showsActiveInbox && activeConversationCount > 0
    }

    var showsWorkboard: Bool {
        showsActiveInbox && !isSearching
    }

    var showsSharedWithMe: Bool {
        selectedFilter == .shared && sharedWithMeCount > 0
    }

    var showsArchivedProjects: Bool {
        selectedFilter == .archived && archivedProjectCount > 0
    }

    var showsArchivedConversations: Bool {
        selectedFilter == .archived && archivedConversationCount > 0
    }

    var hasActiveContent: Bool {
        activeConversationCount > 0 || activeProjectCount > 0 || projectContextMatchCount > 0
    }

    var showsActiveSetupEmptyState: Bool {
        showsActiveInbox && activeConversationCount == 0
    }

    var showsActiveSearchEmptyState: Bool {
        showsActiveInbox && isSearching && !hasActiveContent
    }

    var showsSharedEmptyState: Bool {
        selectedFilter == .shared && sharedWithMeCount == 0
    }

    var showsArchivedEmptyState: Bool {
        selectedFilter == .archived && archivedConversationCount == 0 && archivedProjectCount == 0
    }
}

struct HomeInboxEmptyState: View {
    let title: String
    let subtitle: String
    let symbolName: String
    var isLoading = false
    var actionTitle: String? = nil
    var actionSymbolName: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if isLoading {
                    ProgressView()
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: symbolName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Color.appSecondaryBackground, in: RoundedRectangle.app(AppRadius.pill))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: actionSymbolName ?? "arrow.clockwise")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.primaryAction)
                .background(Color.secondarySurface, in: RoundedRectangle.app(AppRadius.pill))
            }
        }
        .padding(14)
        .background(Color.appPanelBackground, in: RoundedRectangle.app(AppRadius.pill))
        .overlay {
            RoundedRectangle.app(AppRadius.pill)
                .stroke(Color.appBorder, lineWidth: 1)
        }
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
                    Text(selectedFilter == .all ? "Today" : "\(selectedFilter.title) items")
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
            }
        }
        .padding(4)
        .background(Color.appPanelBackground.opacity(0.86), in: RoundedRectangle.app(AppRadius.pill))
        .overlay {
            RoundedRectangle.app(AppRadius.pill)
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
        .frame(minHeight: 44)
        .background(
            isSelected ? Color.primaryAction.opacity(0.10) : Color.clear,
            in: RoundedRectangle.app(AppRadius.pill)
        )
        .overlay {
            if isSelected {
                RoundedRectangle.app(AppRadius.pill)
                    .stroke(Color.primaryAction.opacity(0.14), lineWidth: 1)
            }
        }
    }
}

struct HomeFeedScopeStrip: View {
    @Binding var selectedScope: HomeFeedScope
    let counts: [HomeFeedScope: Int]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(HomeFeedScope.allCases) { scope in
                let isSelected = selectedScope == scope
                let tint = accentColor(for: scope)
                Button {
                    selectedScope = scope
                    AppHaptics.selection()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: scope.symbolName)
                            .font(.caption.weight(.bold))
                        Text(scope.compactTitle)
                            .font(.caption.weight(isSelected ? .bold : .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        if let count = counts[scope], count > 0, scope != .all {
                            Text("\(count)")
                                .font(.caption2.weight(.bold))
                                .lineLimit(1)
                                .foregroundStyle(isSelected ? tint : Color.textTertiary)
                        }
                    }
                    .foregroundStyle(isSelected ? tint : Color.textSecondary)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: AppTouchTarget.minimum)
                    .background(isSelected ? tint.opacity(0.15) : Color.appPanelBackground.opacity(0.94), in: RoundedRectangle.app(AppRadius.pill))
                    .overlay {
                        RoundedRectangle.app(AppRadius.pill)
                            .stroke(isSelected ? tint.opacity(0.26) : Color.appBorder.opacity(0.72), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(scope.title)
                .accessibilityValue(isSelected ? "Selected" : "")
                .accessibilityIdentifier("home.scope.\(scope.rawValue)")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func accentColor(for scope: HomeFeedScope) -> Color {
        switch scope {
        case .all, .chats:
            return Color.actionPrimary
        case .briefings:
            return Color.proofVerifiedText
        case .watchers:
            return Color(red: 0.49, green: 0.36, blue: 0.86)
        }
    }
}

struct HomeBriefingFeedList: View {
    let briefings: [Briefing]
    let onOpen: (Briefing) -> Void

    var body: some View {
        VStack(spacing: 9) {
            ForEach(briefings) { briefing in
                HomeBriefingFeedCard(briefing: briefing) {
                    onOpen(briefing)
                }
            }
        }
    }
}

struct HomeBriefingFeedPresentation {
    enum StatusKind: Equatable {
        case attention
        case paused
    }

    let briefing: Briefing
    let now: Date

    init(briefing: Briefing, now: Date = Date()) {
        self.briefing = briefing
        self.now = now
    }

    var metaText: String {
        if statusKind != nil || briefing.lastRunAt == nil {
            return "\(categoryText) · \(scheduleSummaryText)"
        }
        return "\(categoryText) · \(Self.relativeTime(from: briefing.lastRunAt ?? briefing.createdAt, relativeTo: now))"
    }

    var scheduleAccessoryText: String? {
        guard statusKind == nil,
              briefing.lastRunAt != nil || briefing.latestResult != nil else {
            return nil
        }
        return scheduleTimeText
    }

    var shouldShowStatusPill: Bool {
        statusKind != nil
    }

    var isPending: Bool {
        briefing.latestResult == nil && !briefing.isPaused && statusKind == nil
    }

    var statusKind: StatusKind? {
        if briefing.isPaused { return .paused }
        if briefing.status == .failed { return .attention }
        return nil
    }

    var statusText: String {
        switch statusKind {
        case .paused:
            return "Paused"
        case .attention:
            return "Needs attention"
        case .none:
            if let lastRunAt = briefing.lastRunAt {
                return Self.relativeTime(from: lastRunAt, relativeTo: now)
            }
            return scheduleSummaryText
        }
    }

    var detailText: String {
        if briefing.status == .failed {
            return ThreadedBriefingView.deliveries(for: briefing).first?.summary?.nilIfBlank
                ?? "The last scheduled run didn't produce a result. Re-run now, or check the plan's route and sign-in."
        }
        if briefing.latestResult == nil, briefing.lastRunAt == nil, !briefing.isPaused {
            if let condition = briefing.condition {
                return "Watching for \(condition.summary)."
            }
            return "Runs on schedule. Open to Run now or change cadence."
        }
        if let chart = briefing.latestResult?.chart {
            if let caption = chart.caption?.nilIfBlank { return caption }
            if let label = chart.label?.nilIfBlank { return label }
        }
        if let metric = briefing.latestResult?.metric {
            if let caption = metric.caption?.nilIfBlank { return caption }
            if let label = metric.label?.nilIfBlank { return label }
        }
        if let story = briefing.latestResult?.newsBrief?.stories.first?.title.nilIfBlank {
            return story
        }
        if let note = briefing.latestResult?.note?.nilIfBlank {
            return note
        }
        if let result = briefing.latestResult?.title?.trimmingCharacters(in: .whitespacesAndNewlines), !result.isEmpty {
            return result
        }
        return briefing.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Ready to run." : briefing.prompt
    }

    var categoryText: String {
        if briefing.condition != nil || briefing.isCustomPromptWatcherLike { return "Watcher" }
        switch briefing.kind {
        case .dailyNews, .dailyBrief:
            return "Briefing"
        case .ethPrice, .cryptoPrice, .stockPrice, .watchlist, .nearAccount:
            return "Watcher"
        case .customPrompt:
            return briefing.council ? "Council" : "Briefing"
        }
    }

    var scheduleSummaryText: String {
        Self.compactScheduleLabel(briefing.schedule.scheduleLabel)
    }

    private var scheduleTimeText: String? {
        guard let time = briefing.schedule.timeComponents else { return nil }
        var components = DateComponents()
        components.hour = time.hour
        components.minute = time.minute
        guard let date = Calendar.current.date(from: components) else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mma"
        return formatter.string(from: date).uppercased()
    }

    private static func compactScheduleLabel(_ value: String) -> String {
        value.replacingOccurrences(of: " AM", with: "AM")
            .replacingOccurrences(of: " PM", with: "PM")
            .replacingOccurrences(of: " am", with: "AM")
            .replacingOccurrences(of: " pm", with: "PM")
            .replacingOccurrences(of: "am", with: "AM")
            .replacingOccurrences(of: "pm", with: "PM")
    }

    /// Countdown to the next scheduled run, shown as a capsule pill on the card.
    /// Returns nil when paused, failed, or no future run is calculable.
    var nextRunCountdownText: String? {
        guard statusKind == nil, !briefing.isPaused else { return nil }
        // Don't show countdown if briefing just ran (< 5 min ago) — justRanText takes over.
        if let lastRunAt = briefing.lastRunAt, now.timeIntervalSince(lastRunAt) < 5 * 60 { return nil }
        let anchor = briefing.lastRunAt ?? now
        guard let next = briefing.schedule.nextRun(after: anchor),
              next > now else { return nil }
        let seconds = next.timeIntervalSince(now)
        let hours = Int(seconds / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        if seconds < 24 * 3600 {
            if hours > 0 {
                return "in \(hours)h \(minutes)m"
            } else {
                return "in \(minutes)m"
            }
        } else {
            let days = Int(seconds / 86400)
            return days == 1 ? "in 1 day" : "in \(days) days"
        }
    }

    /// Returns a "just ran" indicator when the last run was within the past 5 minutes.
    var justRanText: String? {
        guard let lastRunAt = briefing.lastRunAt,
              briefing.status != .failed,
              now.timeIntervalSince(lastRunAt) < 5 * 60 else { return nil }
        return "just ran"
    }

    private static func relativeTime(from date: Date, relativeTo now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

private struct HomeBriefingFeedCard: View {
    let briefing: Briefing
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 10) {
                accentRail

                leadingVisual

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(presentation.metaText)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        if presentation.shouldShowStatusPill {
                            statusPill
                        } else if let justRanText = presentation.justRanText {
                            justRanBadge(text: justRanText)
                        } else if let countdown = presentation.nextRunCountdownText {
                            countdownPill(text: countdown)
                        } else if let scheduleTimeText = presentation.scheduleAccessoryText {
                            Text(scheduleTimeText)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Color.textTertiary)
                                .lineLimit(1)
                        }
                    }

                    headlineBlock

                    bottomMetadata
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .background {
                RoundedRectangle.app(AppRadius.control)
                    .fill(cardGradient)
            }
            .overlay {
                RoundedRectangle.app(AppRadius.control)
                    .stroke(cardBorder, lineWidth: 1)
            }
            .shadow(color: Color.brandBlack.opacity(0.032), radius: 13, y: 5)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var headlineBlock: some View {
        if let metricValue {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayTitle)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(metricTone)
                        .lineLimit(2)

                    Text(presentation.detailText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(metricValue)
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    if let metricDelta {
                        Text(metricDelta)
                            .font(.caption2.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(metricTone)
                            .lineLimit(1)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)

                Text(presentation.detailText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(3)
            }
        }
    }

    @ViewBuilder
    private var bottomMetadata: some View {
        let chips = metadataChips
        if !chips.isEmpty {
            HStack(spacing: 6) {
                ForEach(chips.prefix(4)) { chip in
                    HomeFeedMiniChip(chip: chip)
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 1)
        }
    }

    private var statusPill: some View {
        HStack(spacing: 4) {
            if presentation.statusKind == .attention {
                Image(systemName: "exclamationmark.triangle")
                    .font(.caption2.weight(.bold))
            }
            Text(presentation.statusText)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
        }
        .foregroundStyle(statusForeground)
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(statusBackground, in: RoundedRectangle.app(AppRadius.pill))
    }

    private var symbolName: String {
        if briefing.condition != nil || briefing.isCustomPromptWatcherLike { return "bell.badge.fill" }
        switch briefing.kind {
        case .dailyNews, .dailyBrief:
            return "newspaper.fill"
        case .ethPrice, .cryptoPrice, .stockPrice, .watchlist:
            return "chart.line.uptrend.xyaxis"
        case .nearAccount:
            return "wallet.pass.fill"
        case .customPrompt:
            return briefing.council ? "person.3.fill" : "doc.text.fill"
        }
    }

    @ViewBuilder
    private var leadingVisual: some View {
        if !sourceChips.isEmpty {
            HomeSourceClusterIcon(chips: Array(sourceChips.prefix(3)), tint: tint)
        } else {
            HomeBriefingVisualTile(
                symbolName: symbolName,
                tint: tint,
                isPending: presentation.isPending,
                isWatcher: presentation.categoryText == "Watcher"
            )
        }
    }

    private var tint: Color {
        if briefing.status == .failed { return Color.proofStale }
        if briefing.condition != nil || briefing.isCustomPromptWatcherLike { return watcherAccent }
        if briefing.kind.isLiveData { return Color.actionPrimary }
        return briefing.council ? Color.purple : Color.proofVerified
    }

    private var watcherAccent: Color {
        Color(red: 0.49, green: 0.36, blue: 0.86)
    }

    private var contextText: String? {
        if let accountID = briefing.accountID?.nilIfBlank { return accountID }
        if briefing.council { return "Council" }
        return nil
    }

    private var condition: BriefingCondition? {
        briefing.condition
    }

    private var sourceChips: [ConversationSourceChip] {
        let sources = briefing.latestResult?.newsBrief?.stories.flatMap(\.sources) ?? []
        var seen: Set<String> = []
        var chips: [ConversationSourceChip] = []
        for source in sources {
            let text = source.displaySourceText
            let key = (source.faviconIdentity ?? text).lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            chips.append(ConversationSourceChip(
                text: text,
                faviconDomain: source.faviconIdentity,
                fallback: source.fallbackMark,
                allowsNetworkFavicon: source.allowsNetworkFavicon
            ))
        }
        return chips
    }

    private var metadataChips: [HomeFeedMiniChip.Model] {
        var chips: [HomeFeedMiniChip.Model] = []
        if let contextText {
            chips.append(.init(text: contextText, symbolName: "folder", foreground: Color.textTertiary, background: Color.appSecondaryBackground))
        }
        if let condition {
            chips.append(.init(text: condition.summary, symbolName: "bell", foreground: Color.proofStaleText, background: Color.proofStale.opacity(0.10)))
        }
        if let sources = briefing.latestResult?.newsBrief?.stories.flatMap(\.sources), !sources.isEmpty {
            let visibleSources = sources.prefix(2).map { source in
                source
            }
            for source in visibleSources {
                chips.append(.init(
                    text: sourceChipText(for: source),
                    symbolName: nil,
                    foreground: Color.textSecondary,
                    background: Color.appSecondaryBackground,
                    faviconDomain: source.faviconIdentity,
                    faviconFallback: source.fallbackMark,
                    allowsNetworkFavicon: true
                ))
            }
            chips.append(.init(text: "\(sources.count) source\(sources.count == 1 ? "" : "s")", symbolName: nil, foreground: Color.textTertiary, background: nil))
        } else if briefing.latestResult?.followUp?.nilIfBlank != nil {
            chips.append(.init(text: "Ask follow-up", symbolName: "arrow.up.right", foreground: Color.actionPrimary, background: Color.actionFill.opacity(0.55)))
        }
        return chips
    }

    private func sourceChipText(for source: WidgetNewsSource) -> String {
        source.displaySourceText
    }

    private var metricValue: String? {
        if let value = briefing.latestResult?.chart?.value?.nilIfBlank { return value }
        if let value = briefing.latestResult?.metric?.value.nilIfBlank { return value }
        if let display = briefing.history.last?.display.nilIfBlank { return display }
        return nil
    }

    private var metricDelta: String? {
        briefing.latestResult?.chart?.delta?.nilIfBlank ?? briefing.latestResult?.metric?.delta?.nilIfBlank
    }

    private var metricTone: Color {
        let trend = briefing.latestResult?.chart?.trend ?? briefing.latestResult?.metric?.trend
        switch trend {
        case .up:
            return Color.proofVerifiedText
        case .down:
            return Color.proofMismatch
        case .flat, .none:
            return Color.textSecondary
        }
    }

    private var statusForeground: Color {
        presentation.statusKind == .attention ? Color.proofStaleText : Color.textTertiary
    }

    private var statusBackground: Color {
        presentation.statusKind == .attention ? Color.proofStale.opacity(0.13) : Color.appSecondaryBackground
    }

    private var presentation: HomeBriefingFeedPresentation {
        HomeBriefingFeedPresentation(briefing: briefing)
    }

    private var displayTitle: String {
        BriefingPresentationText.displayTitle(briefing.title)
    }

    private var accentRail: some View {
        RoundedRectangle.app(AppRadius.pill)
            .fill(tint)
            .frame(width: 3, height: 62)
            .opacity(presentation.statusKind == .attention ? 0.95 : 0.72)
            .padding(.top, 2)
    }

    private var cardGradient: LinearGradient {
        LinearGradient(
            colors: [
                presentation.statusKind == .attention ? Color.proofStale.opacity(0.09) : tint.opacity(0.08),
                Color.appPanelBackground.opacity(0.99),
                Color.appPanelBackground.opacity(0.96)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardBorder: Color {
        presentation.statusKind == .attention
            ? Color.proofStale.opacity(0.28)
            : tint.opacity(0.17)
    }

    @ViewBuilder
    private func countdownPill(text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "clock.fill")
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(Color.brandAccent)
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(Color.brandAccent.opacity(0.18), in: RoundedRectangle.app(AppRadius.pill))
    }

    @ViewBuilder
    private func justRanBadge(text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(Color.proofVerifiedText)
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(Color.proofVerified.opacity(0.18), in: RoundedRectangle.app(AppRadius.pill))
    }
}

private struct HomeBriefingVisualTile: View {
    let symbolName: String
    let tint: Color
    let isPending: Bool
    let isWatcher: Bool

    var body: some View {
        ZStack {
            RoundedRectangle.app(AppRadius.control)
                .fill(backgroundGradient)
                .overlay(alignment: .topTrailing) {
                    if isPending {
                        Circle()
                            .fill(Color.appPanelBackground)
                            .frame(width: 14, height: 14)
                            .overlay {
                                Circle()
                                    .fill(tint)
                                    .frame(width: 6, height: 6)
                            }
                            .offset(x: 3, y: -3)
                    }
                }
                .overlay {
                    RoundedRectangle.app(AppRadius.control)
                        .stroke(tint.opacity(isPending ? 0.20 : 0.14), lineWidth: 1)
                }

            VStack(spacing: 5) {
                Image(systemName: symbolName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(isPending ? .white : tint)

                HStack(spacing: 3) {
                    Capsule()
                        .fill(lineColor.opacity(isWatcher ? 0.86 : 0.96))
                        .frame(width: 13, height: 3)
                    Capsule()
                        .fill(lineColor.opacity(0.62))
                        .frame(width: 8, height: 3)
                    Capsule()
                        .fill(lineColor.opacity(0.78))
                        .frame(width: 11, height: 3)
                }
            }
            .padding(.top, 1)
        }
        .frame(width: 42, height: 42)
        .accessibilityHidden(true)
    }

    private var backgroundGradient: LinearGradient {
        if isPending {
            return LinearGradient(
                colors: [tint.opacity(0.90), secondaryTint.opacity(0.84)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [tint.opacity(0.14), Color.appPanelBackground],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var secondaryTint: Color {
        isWatcher ? Color.proofVerified : Color.brandSky
    }

    private var lineColor: Color {
        isPending ? .white : tint
    }
}

struct HomeRecentsRow: View {
    let conversations: [ConversationSummary]
    let previewTextForConversation: (ConversationSummary) -> String
    let hasSourceCueForConversation: (ConversationSummary) -> Bool
    let sourceSummaryForConversation: (ConversationSummary) -> String?
    let sourceChipsForConversation: (ConversationSummary) -> [ConversationSourceChip]
    let projectNameForConversation: (ConversationSummary) -> String?
    let onOpenConversation: (ConversationSummary) -> Void

    var body: some View {
        LazyVStack(spacing: 9) {
            ForEach(conversations) { conversation in
                HomeRecentCard(
                    conversation: conversation,
                    preview: previewTextForConversation(conversation),
                    hasSourceCue: hasSourceCueForConversation(conversation),
                    sourceSummary: sourceSummaryForConversation(conversation),
                    sourceChips: sourceChipsForConversation(conversation),
                    projectName: projectNameForConversation(conversation),
                    onOpen: { onOpenConversation(conversation) }
                )
            }
        }
    }
}

struct HomeRecentCard: View {
    let conversation: ConversationSummary
    let preview: String
    let hasSourceCue: Bool
    let sourceSummary: String?
    let sourceChips: [ConversationSourceChip]
    let projectName: String?
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 11) {
                accentRail
                leadingVisual

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(metaText)
                            .font(.caption2.weight(.semibold))
                            .tracking(0.5)
                            .textCase(.uppercase)
                            .foregroundStyle(statusTone == nil ? Color.textTertiary : cardTint)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        if let statusTone {
                            statusPill(tone: statusTone)
                        } else {
                            Image(systemName: "arrow.up.right")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.textTertiary)
                        }
                    }

                    Text(HomeConversationPreviewFormatter.displayTitle(conversation.title))
                        .font(.callout.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(preview)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(usesRecoveryTreatment ? 2 : 3)
                        .fixedSize(horizontal: false, vertical: true)

                    if !footerChips.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(footerChips.prefix(3)) { chip in
                                HomeFeedMiniChip(chip: chip)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.top, 1)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .background {
                RoundedRectangle.app(AppRadius.control)
                    .fill(cardGradient)
            }
            .overlay {
                RoundedRectangle.app(AppRadius.control)
                    .stroke(cardBorder, lineWidth: 1)
            }
            .shadow(color: Color.brandBlack.opacity(isAttentionState ? 0.045 : 0.028), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
    }

    private var metaText: String {
        "\(kindText) · \(timestampText)"
    }

    private var kindText: String {
        if normalizedTitle.contains("council") { return "Council" }
        if normalizedTitle.contains("briefing") || normalizedTitle.contains("digest") { return "Briefing" }
        if normalizedTitle.contains("release date") || normalizedTitle.contains("roadmap") { return "Research" }
        return "Answer"
    }

    private var accentRail: some View {
        RoundedRectangle.app(AppRadius.pill)
            .fill(cardTint)
            .frame(width: 3, height: 56)
            .opacity(usesRecoveryTreatment ? 0.95 : 0.70)
            .padding(.top, 2)
    }

    @ViewBuilder
    private var leadingVisual: some View {
        if hasSourceCue, !sourceChips.isEmpty {
            HomeSourceClusterIcon(chips: Array(sourceChips.prefix(3)), tint: cardTint)
        } else {
            recentIcon
        }
    }

    private var recentIcon: some View {
        Image(systemName: conversation.isPinned ? "pin.fill" : iconName)
            .font(.caption.weight(.bold))
            .foregroundStyle(iconTint)
            .frame(width: 30, height: 30)
            .background(iconTint.opacity(0.15), in: RoundedRectangle.app(AppRadius.control))
    }

    private var iconName: String {
        switch kindText {
        case "Council":
            return "person.3.fill"
        case "Briefing":
            return "doc.text.fill"
        case "Research":
            return "magnifyingglass"
        default:
            return "bubble.left.and.bubble.right.fill"
        }
    }

    private var iconTint: Color {
        if conversation.isPinned { return Color.proofStaleText }
        return cardTint
    }

    private var cardTint: Color {
        if usesRecoveryTreatment { return Color.proofStaleText }
        switch kindText {
        case "Council":
            return Color.purple
        case "Briefing":
            return Color.actionPrimary
        case "Research":
            return Color.proofVerifiedText
        default:
            return Color.actionPrimary
        }
    }

    private var cardGradient: LinearGradient {
        LinearGradient(
            colors: [
                usesRecoveryTreatment ? Color.proofStale.opacity(0.09) : cardTint.opacity(0.075),
                Color.appPanelBackground.opacity(0.99),
                Color.appPanelBackground.opacity(0.96)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardBorder: Color {
        usesRecoveryTreatment ? Color.proofStale.opacity(0.30) : cardTint.opacity(0.16)
    }

    private var statusTone: HomeFeedMiniChip.Model? {
        if isAttentionState {
            return .init(
                text: "Needs attention",
                symbolName: "exclamationmark.triangle",
                foreground: Color.proofStaleText,
                background: Color.proofStale.opacity(0.13)
            )
        }
        if isSourceGapState {
            return .init(
                text: "Needs sources",
                symbolName: "exclamationmark.triangle",
                foreground: Color.proofStaleText,
                background: Color.proofStale.opacity(0.13)
            )
        }
        return nil
    }

    private func statusPill(tone: HomeFeedMiniChip.Model) -> some View {
        HomeFeedMiniChip(chip: tone)
    }

    private var footerChips: [HomeFeedMiniChip.Model] {
        var chips: [HomeFeedMiniChip.Model] = []
        if usesRecoveryTreatment {
            chips.append(.init(
                text: "Open thread",
                symbolName: "arrow.up.right",
                foreground: Color.actionPrimary,
                background: Color.actionFill.opacity(0.55)
            ))
        } else if hasSourceCue, !sourceChips.isEmpty {
            for source in sourceChips.prefix(2) {
                chips.append(.init(
                    text: source.text,
                    symbolName: nil,
                    foreground: Color.textSecondary,
                    background: Color.appSecondaryBackground,
                    faviconDomain: source.faviconDomain,
                    faviconFallback: source.fallback,
                    allowsNetworkFavicon: source.allowsNetworkFavicon
                ))
            }
            if sourceChips.count > 2 {
                chips.append(.init(
                    text: "+\(sourceChips.count - 2)",
                    symbolName: nil,
                    foreground: Color.textTertiary,
                    background: nil
                ))
            }
        } else {
            chips.append(.init(
                text: primaryFooterText,
                symbolName: primaryFooterSymbolName,
                foreground: primaryFooterForeground,
                background: primaryFooterBackground
            ))
        }

        if let sourceGapChip {
            chips.append(sourceGapChip)
        }

        if let projectName {
            chips.append(.init(
                text: projectName,
                symbolName: "folder",
                foreground: Color.textTertiary,
                background: Color.appSecondaryBackground
            ))
        } else if let topicChip {
            chips.append(topicChip)
        }

        return chips
    }

    private var primaryFooterText: String {
        if kindText == "Council" { return "Council" }
        if let sourceSummary, hasSourceCue { return sourceSummary }
        return "Private chat"
    }

    private var primaryFooterSymbolName: String {
        if kindText == "Council" { return "person.3.sequence.fill" }
        if sourceSummary != nil, hasSourceCue { return "link" }
        return "checkmark.shield"
    }

    private var primaryFooterForeground: Color {
        if sourceSummary != nil, hasSourceCue { return Color.actionPrimary }
        return Color.textSecondary
    }

    private var primaryFooterBackground: Color {
        if sourceSummary != nil, hasSourceCue { return Color.actionFill.opacity(0.55) }
        return Color.appSecondaryBackground
    }

    private var sourceGapChip: HomeFeedMiniChip.Model? {
        guard !usesRecoveryTreatment,
              topicChip != nil,
              !hasSourceCue else {
            return nil
        }
        return .init(
            text: "No sources",
            symbolName: "exclamationmark.triangle",
            foreground: Color.proofStaleText,
            background: Color.proofStale.opacity(0.12)
        )
    }

    private var topicChip: HomeFeedMiniChip.Model? {
        if normalizedText.contains("spacex") || normalizedText.contains("iran") || normalizedText.contains("ipo") || normalizedText.contains("news") {
            return .init(text: "Current events", symbolName: nil, foreground: Color.textTertiary, background: nil)
        }
        if normalizedText.contains("release") {
            return .init(text: "Release watch", symbolName: nil, foreground: Color.textTertiary, background: nil)
        }
        return nil
    }

    private var isAttentionState: Bool {
        HomeConversationRecoveryPolicy.isAttentionState(normalizedText)
    }

    private var isSourceGapState: Bool {
        HomeConversationRecoveryPolicy.isSourceGapState(normalizedText, hasSourceCue: hasSourceCue)
    }

    private var usesRecoveryTreatment: Bool {
        isAttentionState || isSourceGapState
    }

    private var normalizedText: String {
        "\(conversation.title) \(preview)".lowercased()
    }

    private var normalizedTitle: String {
        conversation.title.lowercased()
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

private struct HomeSourceClusterIcon: View {
    let chips: [ConversationSourceChip]
    let tint: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle.app(AppRadius.control)
                .fill(tint.opacity(0.12))
                .frame(width: 42, height: 42)
                .overlay {
                    RoundedRectangle.app(AppRadius.control)
                        .stroke(tint.opacity(0.18), lineWidth: 1)
                }

            ForEach(Array(chips.prefix(3).enumerated()), id: \.offset) { index, chip in
                SourceFaviconView(
                    domain: chip.faviconDomain,
                    size: index == 0 ? 24 : 19,
                    fallbackText: chip.fallback,
                    cornerRadius: index == 0 ? 8 : 7,
                    borderColor: Color.appPanelBackground,
                    borderWidth: 1.5,
                    allowsNetworkFavicon: chip.allowsNetworkFavicon
                )
                .offset(offset(for: index))
            }
        }
        .frame(width: 42, height: 42)
        .accessibilityHidden(true)
    }

    private func offset(for index: Int) -> CGSize {
        switch index {
        case 0:
            return CGSize(width: 6, height: 6)
        case 1:
            return CGSize(width: 21, height: 4)
        default:
            return CGSize(width: 19, height: 21)
        }
    }
}

struct HomeFeedMiniChip: View {
    struct Model: Identifiable {
        let id = UUID()
        let text: String
        let symbolName: String?
        let foreground: Color
        let background: Color?
        var faviconDomain: String? = nil
        var faviconFallback: String = "S"
        var allowsNetworkFavicon: Bool = false
    }

    let chip: Model

    var body: some View {
        HStack(spacing: 4) {
            if let faviconDomain = chip.faviconDomain {
                SourceFaviconView(
                    domain: faviconDomain,
                    size: 18,
                    fallbackText: chip.faviconFallback,
                    cornerRadius: 6,
                    borderColor: Color.appBorder.opacity(0.75),
                    borderWidth: 0.5,
                    allowsNetworkFavicon: chip.allowsNetworkFavicon
                )
            } else if let symbolName = chip.symbolName {
                Image(systemName: symbolName)
                    .font(.caption2.weight(.semibold))
            }
            Text(chip.text)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .foregroundStyle(chip.foreground)
        .padding(.horizontal, chip.background == nil ? 0 : 7)
        .frame(height: chip.background == nil ? 20 : 22)
        .background(chip.background ?? Color.clear, in: RoundedRectangle.app(AppRadius.pill))
        .overlay {
            if chip.background != nil {
                RoundedRectangle.app(AppRadius.pill)
                    .stroke(Color.appBorder.opacity(0.68), lineWidth: 0.5)
            }
        }
    }
}

extension Briefing {
    var isCustomPromptWatcherLike: Bool {
        guard kind == .customPrompt else { return false }
        let text = "\(title) \(prompt)".lowercased()
        let watcherCues = [
            "alert", "watch", "watcher", "track", "tracker", "monitor",
            "notify", "notification", "threshold", "price", "release date",
            "no-alert", "market data"
        ]
        return watcherCues.contains { text.contains($0) }
    }

    var isWatcherLike: Bool {
        if condition != nil || !history.isEmpty || isCustomPromptWatcherLike {
            return true
        }
        switch kind {
        case .ethPrice, .cryptoPrice, .stockPrice, .watchlist, .nearAccount:
            return true
        case .customPrompt, .dailyNews, .dailyBrief:
            return false
        }
    }
}

extension BriefingStatus {
    func feedSortRank(failedFirst: Bool) -> Int {
        if failedFirst {
            switch self {
            case .failed:
                return 0
            case .live:
                return 1
            case .active:
                return 2
            case .scheduled:
                return 3
            case .paused:
                return 4
            }
        }

        switch self {
        case .active, .live:
            return 0
        case .scheduled:
            return 1
        case .failed:
            return 2
        case .paused:
            return 3
        }
    }
}
