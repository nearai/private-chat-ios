import SwiftUI

// MARK: - CapabilitiesView (unchanged)

struct CapabilitiesEntryRow: View {
    let statusLine: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.brandAccent)
                .frame(width: 34, height: 34)
                .background(Color.brandAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                    Text("Capabilities")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(statusLine)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.brandAccent)
                    .lineLimit(2)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

struct CapabilitiesView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var agentStore: AgentStore
    @EnvironmentObject private var modelCatalogStore: ModelCatalogStore
    @EnvironmentObject private var securityStore: SecurityStore
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var connectionDiagnostics: ConnectionDiagnostics
    @Environment(\.dismiss) private var dismiss

    let onOpenAccountSettings: ((AccountSettingsDeepLink) -> Void)?
    let onOpenSecurity: (() -> Void)?
    let onOpenAgentWorkspace: (() -> Void)?
    let onRunSetupAgain: (() -> Void)?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    capabilityHeader
                    CapabilityStatusStrip(items: statusItems)
                    setupDefaultsCard

                    CapabilityCard(
                        iconName: "sparkles",
                        title: "General Assistant",
                        status: "Ready",
                        statusColor: .actionPrimary,
                        summary: "Write, code, research, summarize files, compare options, and turn messy context into concrete next actions.",
                        trustLine: "Default: start private, then use Web, Cloud, Agent, or Council only when the task calls for it.",
                        detail: "Ask in normal language. Attach files, paste notes, or describe what you want tracked; the chat surface should stage work for review before creating anything.",
                        primaryAction: nil,
                        secondaryAction: nil
                    )

                    CapabilityCard(
                        iconName: "lock.shield",
                        title: "Private Inference",
                        status: privateStatus,
                        statusColor: privateStatusColor,
                        summary: "Private chat works immediately on iPhone and can attach proof when the selected route supports it.",
                        trustLine: "Trust boundary: proof reports cover route evidence.",
                        detail: privateDetail,
                        primaryAction: privatePrimaryAction,
                        secondaryAction: nil
                    )

                    CapabilityCard(
                        iconName: "cloud.fill",
                        title: "NEAR AI Cloud",
                        status: cloudStatus,
                        statusColor: cloudStatusColor,
                        summary: "Connect Cloud when you want more external models inside the same conversation flow.",
                        trustLine: "Trust boundary: NEAR AI Cloud requests can leave the private route and do not carry NEAR Private proof.",
                        detail: cloudDetail,
                        primaryAction: cloudPrimaryAction,
                        secondaryAction: nil
                    )

                    CapabilityCard(
                        iconName: "terminal.fill",
                        title: "Agent",
                        status: agentStatus,
                        statusColor: agentStatusColor,
                        summary: "Use phone-safe Agent skills now, then hand off repo, shell, and code tasks when Hosted IronClaw is connected.",
                        trustLine: "Trust boundary: Hosted IronClaw receives prompt text plus file metadata unless source excerpts are included.",
                        detail: agentDetail,
                        primaryAction: agentPrimaryAction,
                        secondaryAction: agentSecondaryAction
                    )

                    CapabilityCard(
                        iconName: "square.grid.2x2.fill",
                        title: "Council",
                        status: councilStatus,
                        statusColor: councilStatusColor,
                        summary: "Compare private and Cloud models in one chat, then synthesize the strongest answer.",
                        trustLine: "Trust boundary: mixed councils can include both proof-backed private legs and external Cloud legs.",
                        detail: councilDetail,
                        primaryAction: councilPrimaryAction,
                        secondaryAction: nil
                    )

                    NavigationLink {
                        ConnectionDiagnosticsView()
                    } label: {
                        connectionDiagnosticsRow
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("capabilities.diagnostics")

                    if let nextStep {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Suggested next step")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            CapabilityActionButton(action: primaryAction(for: nextStep))
                            if let secondaryAction = secondaryAction(for: nextStep) {
                                CapabilityActionButton(action: secondaryAction)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 20)
                .frame(maxWidth: 640, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .background(HomeSurfaceBackground().ignoresSafeArea())
            .navigationTitle("Capabilities")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .platformLargeDetent()
    }

    private var connectionDiagnosticsRow: some View {
        let needsAttention = connectionDiagnostics.privateLooksUnauthenticated ||
            connectionDiagnostics.privateLooksTransportUnreachable
        return HStack(spacing: 12) {
            Image(systemName: needsAttention ? "exclamationmark.triangle.fill" : "waveform.path.ecg")
                .font(.body.weight(.semibold))
                .foregroundStyle(needsAttention ? Color.proofStale : Color.textSecondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Connection diagnostics")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(connectionDiagnosticsRowSubtitle)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(needsAttention ? Color.proofStale.opacity(0.4) : Color.appBorder, lineWidth: 1)
        }
    }

    private var connectionDiagnosticsRowSubtitle: String {
        if connectionDiagnostics.privateLooksUnauthenticated {
            return "Private session isn't authenticating — tap to see details."
        }
        if connectionDiagnostics.privateLooksTransportUnreachable {
            return "Private backend did not answer — tap to see details."
        }
        return "See the real status of the last request on each route."
    }

    private var capabilityHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Chat about anything. Starts private, then adds Web, Cloud, Agent, or Council when the task needs it.")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(headerStatusLine)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(setupPlan.readinessStatus)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let email = sessionStore.profile?.user.email {
                Text(email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusItems: [CapabilityStatusItemModel] {
        [
            CapabilityStatusItemModel(title: "Private", value: privateStatus, tint: privateStatusColor),
            CapabilityStatusItemModel(title: "Cloud", value: cloudStatus, tint: cloudStatusColor),
            CapabilityStatusItemModel(title: "Agent", value: agentStatus, tint: agentStatusColor),
            CapabilityStatusItemModel(title: "Council", value: councilStatus, tint: councilStatusColor)
        ]
    }

    private var headerStatusLine: String {
        [
            privateHeaderStatus,
            accountStore.nearCloudKeyConfigured ? "Cloud connected" : "Cloud not connected",
            agentStatus
        ].joined(separator: " · ")
    }

    private var privateHeaderStatus: String {
        securityStore.attestationSnapshot == nil ? "Private route" : "Private \(privateStatus.lowercased())"
    }

    private var setupDefaultsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Default setup")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            SetupPlanPreviewCard(plan: setupPlan)
        }
    }

    private var setupProfile: UserSetupProfile {
        guard let accountID = sessionStore.setupAccountID else { return .defaults }
        return UserSetupStorage.load(for: accountID) ?? .defaults
    }

    private var readinessSnapshot: AppSetupReadinessSnapshot {
        AppSetupReadinessSnapshot(
            modelCatalogLoaded: !modelCatalogStore.models.isEmpty,
            privateModelAvailable: modelCatalogStore.pickerModels.contains { !$0.isExternalModel },
            defaultCouncilModelCount: modelCatalogStore.defaultCouncilModels.count,
            ironclawMobileAvailable: modelCatalogStore.agentModels.contains { $0.id == ModelOption.ironclawMobileModelID },
            hostedIronclawAvailable: agentStore.ironclawRemoteWorkstationAvailable,
            nearCloudKeyConfigured: accountStore.nearCloudKeyConfigured
        )
    }

    private var setupPlan: AppSetupPlan {
        AppSetupPlan(profile: setupProfile, readiness: readinessSnapshot)
    }

    private var routeBlock: CapabilityRouteBlock? {
        let issue = RoutePlanner.routeReadinessIssue(
            selectedModelID: modelCatalogStore.selectedModel,
            requestedCouncilModelIDs: modelCatalogStore.councilModelIDs,
            isCouncilRequested: modelCatalogStore.isCouncilModeEnabled || modelCatalogStore.councilModelIDs.count > 1,
            nearCloudKeyConfigured: accountStore.nearCloudKeyConfigured,
            hostedIronclawEndpointUsable: agentStore.ironclawRemoteWorkstationAvailable,
            hostedIronclawEndpointMessage: agentStore.ironclawSettings.endpointValidationMessage
        )
        guard let issue else { return nil }
        switch issue.route {
        case .nearCloud:
            return .nearCloudKeyRequired
        case .hostedIronclaw:
            return .hostedIronclawEndpointRequired
        case .council:
            return .councilNeedsModels
        }
    }

    private var hasFreshPrivateProof: Bool {
        guard let snapshot = securityStore.attestationSnapshot else { return false }
        return AttestationFreshness.classify(attestedAt: snapshot.fetchedAt) != .stale
    }

    private var nextStep: CapabilityNextStep? {
        let recommendation = CapabilityNextStepPlanner.recommend(
            routeBlock: routeBlock,
            setupPlan: setupPlan,
            currentRoute: modelCatalogStore.selectedRouteKind,
            hasFreshPrivateProof: hasFreshPrivateProof,
            hostedIronclawAvailable: agentStore.ironclawRemoteWorkstationAvailable,
            autoCouncilReady: modelCatalogStore.defaultCouncilModels.count >= 2
        )
        if recommendation?.kind == .rerunSetup, onRunSetupAgain == nil {
            return nil
        }
        return recommendation
    }

    private var privateStatus: String {
        guard let snapshot = securityStore.attestationSnapshot else { return "No proof yet" }
        switch AttestationFreshness.classify(attestedAt: snapshot.fetchedAt) {
        case .underTwoMinutes:
            return "Proof fresh"
        case .underOneHour:
            return "Proof checked"
        case .stale:
            return "Proof stale"
        }
    }

    private var privateStatusColor: Color {
        guard let snapshot = securityStore.attestationSnapshot else { return Color.brandAccent }
        switch AttestationFreshness.classify(attestedAt: snapshot.fetchedAt) {
        case .underTwoMinutes, .underOneHour:
            return Color.proofVerified
        case .stale:
            return Color.proofStale
        }
    }

    private var privateDetail: String {
        guard let snapshot = securityStore.attestationSnapshot else {
            return "Current route: \(modelCatalogStore.selectedProviderDisplayName). Open Proof report when you need signed private-route evidence."
        }

        let coveredCount = max(snapshot.modelAttestationCount, snapshot.coveredModelIDs.count)
        let freshness = AttestationFreshness.classify(attestedAt: snapshot.fetchedAt).shortLabel
        let countLabel = "\(coveredCount) model\(coveredCount == 1 ? "" : "s")"
        return "Last report: \(countLabel) listed · \(freshness) · Current route: \(modelCatalogStore.selectedProviderDisplayName)."
    }

    private var cloudStatus: String {
        accountStore.nearCloudKeyConfigured ? "Connected" : "Not connected"
    }

    private var cloudStatusColor: Color {
        accountStore.nearCloudKeyConfigured ? Color.brandAccent : Color.proofStale
    }

    private var cloudDetail: String {
        if accountStore.nearCloudKeyConfigured {
            let plan = accountStore.billingSnapshot?.activeSubscription?.plan ?? "Cloud connected"
            return modelCatalogStore.selectedRouteUsesNearCloud
                ? "Current route uses \(modelCatalogStore.selectedModelDisplayName) through NEAR AI Cloud. \(plan)."
                : "Cloud unlocks premium external model rows in the picker. \(plan)."
        }
        return "Connect NEAR AI Cloud before sending with locked Cloud routes or mixed Cloud councils."
    }

    private var agentStatus: String {
        if agentStore.ironclawRemoteWorkstationAvailable {
            return "Hosted connected"
        }
        if modelCatalogStore.agentModels.contains(where: { $0.id == ModelOption.ironclawMobileModelID }) {
            return "Phone ready"
        }
        return "Not ready"
    }

    private var agentStatusColor: Color {
        if agentStore.ironclawRemoteWorkstationAvailable {
            return Color.proofVerified
        }
        return modelCatalogStore.agentModels.contains(where: { $0.id == ModelOption.ironclawMobileModelID }) ? Color.brandAccent : Color.proofStale
    }

    private var agentDetail: String {
        if let verifiedAt = agentStore.ironclawLastVerifiedAt, agentStore.ironclawRemoteWorkstationAvailable {
            return "Hosted tools last checked \(verifiedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))."
        }
        return agentStore.ironclawStatusText
    }

    private var councilStatus: String {
        let activeCount = modelCatalogStore.councilModelIDs.count
        if activeCount >= 2 {
            return "Current lineup ready"
        }
        if modelCatalogStore.defaultCouncilModels.count >= 2 {
            return "Auto lineup ready"
        }
        return "Needs one more model"
    }

    private var councilStatusColor: Color {
        (modelCatalogStore.councilModelIDs.count >= 2 || modelCatalogStore.defaultCouncilModels.count >= 2) ? Color.brandAccent : Color.proofStale
    }

    private var councilDetail: String {
        let models = modelCatalogStore.councilModelNames.isEmpty ? modelCatalogStore.defaultCouncilModels.map(\.displayName) : modelCatalogStore.councilModelNames
        let lineup = models.prefix(3).joined(separator: " · ")
        let suffix = models.count > 3 ? " +\(models.count - 3) more" : ""

        if models.isEmpty {
            return "Council turns on once at least two compatible chat models are available."
        }

        if !accountStore.nearCloudKeyConfigured,
           modelCatalogStore.defaultCouncilModels.contains(where: \.isNearCloudModel) {
            return "Auto lineup is available, but Cloud legs stay locked until a key is added. \(lineup)\(suffix)."
        }

        return "Lineup: \(lineup)\(suffix)."
    }

    private var privatePrimaryAction: CapabilityCardAction? {
        guard let onOpenSecurity else { return nil }
        return CapabilityCardAction(title: "Open Proof report", systemImage: "checkmark.shield", role: .primary) {
            dismissThen(onOpenSecurity)
        }
    }

    private var cloudPrimaryAction: CapabilityCardAction? {
        guard let onOpenAccountSettings else { return nil }
        return CapabilityCardAction(
            title: accountStore.nearCloudKeyConfigured ? "Manage Cloud keys" : "Connect Cloud",
            systemImage: accountStore.nearCloudKeyConfigured ? "slider.horizontal.3" : "key",
            role: .primary
        ) {
            dismissThen {
                onOpenAccountSettings(.nearCloudKeys)
            }
        }
    }

    private var agentPrimaryAction: CapabilityCardAction? {
        if agentStore.ironclawRemoteWorkstationAvailable, let onOpenAgentWorkspace {
            return CapabilityCardAction(title: "Run Agent", systemImage: "terminal", role: .primary) {
                dismissThen(onOpenAgentWorkspace)
            }
        }
        guard let onOpenAccountSettings else { return nil }
        return CapabilityCardAction(title: "Connect Agent", systemImage: "point.3.connected.trianglepath.dotted", role: .primary) {
            dismissThen {
                onOpenAccountSettings(.ironclawAgent)
            }
        }
    }

    private var agentSecondaryAction: CapabilityCardAction? {
        guard agentStore.ironclawRemoteWorkstationAvailable, let onOpenAccountSettings else { return nil }
        return CapabilityCardAction(title: "Manage Agent Connection", systemImage: "slider.horizontal.3", role: .secondary) {
            dismissThen {
                onOpenAccountSettings(.ironclawAgent)
            }
        }
    }

    private var councilPrimaryAction: CapabilityCardAction? {
        guard modelCatalogStore.councilModelIDs.count < 2, modelCatalogStore.defaultCouncilModels.count >= 2 else { return nil }
        return CapabilityCardAction(title: "Use recommended Council", systemImage: "square.grid.2x2", role: .primary) {
            modelCatalogStore.useDefaultCouncilLineup()
        }
    }

    private func primaryAction(for nextStep: CapabilityNextStep) -> CapabilityCardAction {
        switch nextStep.kind {
        case .openSecurity:
            return CapabilityCardAction(title: nextStep.actionTitle, systemImage: "checkmark.shield", role: .primary) {
                guard let onOpenSecurity else { return }
                dismissThen(onOpenSecurity)
            }
        case .openCloud:
            return CapabilityCardAction(title: nextStep.actionTitle, systemImage: "key", role: .primary) {
                guard let onOpenAccountSettings else { return }
                dismissThen {
                    onOpenAccountSettings(.nearCloudKeys)
                }
            }
        case .openAgent:
            return CapabilityCardAction(title: nextStep.actionTitle, systemImage: "point.3.connected.trianglepath.dotted", role: .primary) {
                guard let onOpenAccountSettings else { return }
                dismissThen {
                    onOpenAccountSettings(.ironclawAgent)
                }
            }
        case .useAutoCouncil:
            return CapabilityCardAction(title: nextStep.actionTitle, systemImage: "square.grid.2x2", role: .primary) {
                modelCatalogStore.useDefaultCouncilLineup()
            }
        case .rerunSetup:
            return CapabilityCardAction(title: nextStep.actionTitle, systemImage: "arrow.counterclockwise", role: .primary) {
                guard let onRunSetupAgain else { return }
                dismissThen(onRunSetupAgain)
            }
        }
    }

    private func secondaryAction(for nextStep: CapabilityNextStep) -> CapabilityCardAction? {
        guard let onRunSetupAgain, nextStep.kind != .rerunSetup else { return nil }
        return CapabilityCardAction(title: "Rerun Setup", systemImage: "arrow.counterclockwise", role: .secondary) {
            dismissThen(onRunSetupAgain)
        }
    }

    private func dismissThen(_ action: @escaping () -> Void) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            action()
        }
    }
}
