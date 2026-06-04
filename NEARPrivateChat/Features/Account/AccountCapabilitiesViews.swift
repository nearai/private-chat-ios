import SwiftUI

struct AccountSettingsView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var agentStore: AgentStore
    @EnvironmentObject private var modelCatalogStore: ModelCatalogStore
    @EnvironmentObject private var securityStore: SecurityStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let initialDeepLink: AccountSettingsDeepLink?
    let onRunSetupAgain: () -> Void
    let isCurrentChatEmpty: () -> Bool
    @State private var systemPrompt = ""
    @State private var webSearchEnabled = true
    @State private var notificationPreferenceEnabled = false
    @State private var appearancePreference: AppAppearancePreference = .system
    @State private var largeTextAsFileEnabled = true
    @State private var temperature = ""
    @State private var topP = ""
    @State private var maxTokens = ""
    @State private var reasoningEffort: ModelReasoningEffort = .automatic
    @State private var nearCloudAPIKey = ""
    @State private var ironclawEnabled = false
    @State private var ironclawEndpoint = ""
    @State private var ironclawToken = ""
    @State private var ironclawThreadID = ""
    @State private var isSavingSettings = false
    @State private var showingChatImporter = false
    @State private var showingShareGroups = false
    @State private var showingCapabilities = false
    @State private var showingSecurity = false
    @State private var showingSignOutConfirm = false
    @State private var showingIronclawPowerTool = false
    @State private var showingAPIKeysPowerTool = false
    @State private var hasOpenedInitialDeepLink = false
    @AppStorage("account.powerToolsExpanded") private var powerToolsExpanded = false

    init(
        initialDeepLink: AccountSettingsDeepLink? = nil,
        onRunSetupAgain: @escaping () -> Void,
        isCurrentChatEmpty: @escaping () -> Bool = { false }
    ) {
        self.initialDeepLink = initialDeepLink
        self.onRunSetupAgain = onRunSetupAgain
        self.isCurrentChatEmpty = isCurrentChatEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                accountSection
                appearanceSection
                privacySection
                modelDefaultsSection
                powerToolsSection
                aboutSection
                footerSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Account")
            .platformInlineNavigationTitle()
            .onAppear {
                systemPrompt = accountStore.systemPrompt
                webSearchEnabled = modelCatalogStore.webSearchEnabled
                notificationPreferenceEnabled = accountStore.notificationPreferenceEnabled
                appearancePreference = accountStore.appearancePreference
                largeTextAsFileEnabled = accountStore.largeTextAsFileEnabled
                loadAdvancedParams(accountStore.advancedModelParams)
                nearCloudAPIKey = ""
                loadIronclawBridge()
                if accountStore.billingSnapshot == nil {
                    Task { await accountStore.refreshBilling() }
                }
                openInitialDeepLinkIfNeeded()
            }
            .navigationDestination(isPresented: $showingIronclawPowerTool) {
                PowerToolIronclawView(
                    ironclawEnabled: $ironclawEnabled,
                    ironclawEndpoint: $ironclawEndpoint,
                    ironclawToken: $ironclawToken,
                    ironclawThreadID: $ironclawThreadID,
                    onSave: saveIronclawBridge,
                    onReload: loadIronclawBridge
                )
                .environmentObject(agentStore)
            }
            .navigationDestination(isPresented: $showingAPIKeysPowerTool) {
                PowerToolAPIKeysView(
                    nearCloudAPIKey: $nearCloudAPIKey,
                    onPaste: pasteNearCloudKeyFromClipboard,
                    onConnectAccount: connectNearCloudAccount,
                    onConnect: connectNearCloud,
                    onOpenCloud: openNearCloudSignup
                )
                .environmentObject(accountStore)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $showingChatImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case let .success(urls):
                    guard let url = urls.first else { return }
                    Task {
                        await accountStore.importChats(from: url)
                    }
                case let .failure(error):
                    accountStore.showBanner(error.localizedDescription)
                }
            }
            .sheet(isPresented: $showingShareGroups) {
                ShareGroupsView()
            }
            .sheet(isPresented: $showingSecurity) {
                SecurityView()
                    .environmentObject(securityStore)
            }
            .sheet(isPresented: $showingCapabilities) {
                CapabilitiesView(
                    onOpenAccountSettings: { deepLink in
                        openDeepLink(deepLink)
                    },
                    onOpenSecurity: { showingSecurity = true },
                    onOpenAgentWorkspace: nil,
                    onRunSetupAgain: onRunSetupAgain
                )
                .environmentObject(accountStore)
                .environmentObject(agentStore)
                .environmentObject(modelCatalogStore)
                .environmentObject(securityStore)
                .environmentObject(sessionStore)
            }
            .confirmationDialog("Sign out of NEAR Private Chat?", isPresented: $showingSignOutConfirm, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    sessionStore.signOut()
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            }
        }
        .platformLargeDetent()
    }

    // MARK: - 1. Account

    private var accountSection: some View {
        Section("Account") {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.actionTint)
                    .frame(width: 32, height: 32)
                    .overlay {
                        Text(String(sessionStore.displayName.prefix(1)).uppercased())
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.actionPrimary)
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text(sessionStore.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text(accountStatusSummary)
                        .font(.footnote)
                        .fontWeight(.regular)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 4)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            NavigationLink {
                SignInMethodDetailView()
                    .environmentObject(sessionStore)
            } label: {
                accountDetailRow(
                    title: "Sign-in method",
                    detail: sessionStore.session?.sessionID.isEmpty == false ? "Browser session" : "Session token"
                )
            }

            NavigationLink {
                PlanDetailView()
                    .environmentObject(accountStore)
            } label: {
                accountDetailRow(
                    title: "Plan",
                    detail: accountStore.billingSnapshot?.activeSubscription?.plan.capitalized ?? accountStore.currentBillingPlanName.capitalized
                )
            }

            Button {
                showingSignOutConfirm = true
            } label: {
                Text("Sign Out")
                    .foregroundStyle(Color.proofMismatch)
            }
        }
    }

    private func accountDetailRow(title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            Text(detail)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.86)
        }
    }

    private var accountStatusSummary: String {
        sessionStore.session?.sessionID.isEmpty == false ? "Browser session active" : "Session token active"
    }

    /// Friendly name for the active default model, falling back to the
    /// raw id humanized if the catalog hasn't loaded yet.
    private var currentDefaultModelLabel: String {
        let id = modelCatalogStore.effectiveDefaultModelID
        if let option = modelCatalogStore.pickerModels.first(where: { $0.id == id }) {
            return option.displayName
        }
        return ModelOption.humanize(modelID: id)
    }

    // MARK: - 2. Appearance

    private var appearanceSection: some View {
        Section("Appearance") {
            HStack(spacing: 12) {
                Text("Theme")
                    .foregroundStyle(.primary)
                Spacer()
                Picker("Theme", selection: $appearancePreference) {
                    ForEach(AppAppearancePreference.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
                .labelsHidden()
            }
            .onChange(of: appearancePreference) { _, _ in
                Task { await saveChatSettings() }
            }

            NavigationLink {
                DynamicTypeDetailView()
            } label: {
                accountDetailRow(title: "Dynamic Type", detail: "Default")
            }

            Toggle("Notifications", isOn: $notificationPreferenceEnabled)
                .onChange(of: notificationPreferenceEnabled) { _, _ in
                    Task { await saveChatSettings() }
                }
        }
    }

    // MARK: - 3. Privacy

    private var privacySection: some View {
        Section("Privacy") {
            Button {
                showingChatImporter = true
            } label: {
                Label(accountStore.isImportingChats ? "Importing Chats" : "Import Chats", systemImage: "square.and.arrow.down")
                    .foregroundStyle(.primary)
            }
            .disabled(accountStore.isImportingChats)

            Text("Export signed transcripts and proof reports from a conversation's Share menu.")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)

        }
    }

    // MARK: - 4. Model defaults

    private var modelDefaultsSection: some View {
        Section("Model Defaults") {
            NavigationLink {
                DefaultModelDetailView { nextDefaultModelID in
                    modelCatalogStore.setPreferredDefaultModel(
                        nextDefaultModelID,
                        shouldSwitchCurrentEmptyChat: isCurrentChatEmpty()
                    )
                }
                .environmentObject(modelCatalogStore)
            } label: {
                accountDetailRow(title: "Default model", detail: currentDefaultModelLabel)
            }

            NavigationLink {
                ReasoningEffortDetailView(
                    selection: $reasoningEffort,
                    onSave: { Task { await saveChatSettings() } }
                )
            } label: {
                accountDetailRow(title: "Default reasoning effort", detail: reasoningEffort.title)
            }

            Toggle("Default web search", isOn: $webSearchEnabled)
                .onChange(of: webSearchEnabled) { _, _ in
                    Task { await saveChatSettings() }
                }
            Text("Web search is off by default for private chat; research setup can turn current-source search on.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - 5. Capabilities

    private var powerToolsSection: some View {
        Section {
            Button {
                showingCapabilities = true
            } label: {
                powerToolButtonRow(icon: "square.grid.2x2", title: "Capability Center", subtitle: capabilitiesStatusLine)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)

            Button {
                openIronclawPowerTool()
            } label: {
                powerToolButtonRow(icon: "terminal", title: "Agent", subtitle: "Connect Hosted IronClaw or run phone-safe Agent tasks")
            }
            .buttonStyle(.plain)

            Button {
                openAPIKeysPowerTool()
            } label: {
                powerToolButtonRow(icon: "key", title: "Cloud keys", subtitle: accountStore.nearCloudKeyConfigured ? "NEAR AI Cloud connected" : "Connect NEAR AI Cloud")
            }
            .buttonStyle(.plain)

            Button {
                showingSecurity = true
            } label: {
                powerToolSubRow(icon: "seal", title: "Proof report", subtitle: securityStore.attestationSnapshot == nil ? "No proof report fetched" : "Proof report available")
                    .foregroundStyle(.primary)
            }

            DisclosureGroup(isExpanded: $powerToolsExpanded) {
                NavigationLink {
                    PowerToolDiagnosticsView()
                        .environmentObject(accountStore)
                } label: {
                    powerToolSubRow(icon: "slider.horizontal.3", title: "Diagnostics", subtitle: nil)
                }

                NavigationLink {
                    PowerToolEndpointsView(
                        systemPrompt: $systemPrompt,
                        temperature: $temperature,
                        topP: $topP,
                        maxTokens: $maxTokens,
                        largeTextAsFileEnabled: $largeTextAsFileEnabled,
                        isSavingSettings: $isSavingSettings,
                        onSave: { Task { await saveChatSettings() } },
                        advancedParamsSummary: advancedParams.summary
                    )
                    .environmentObject(sessionStore)
                } label: {
                    powerToolSubRow(icon: "doc.text", title: "Advanced API settings", subtitle: nil)
                }
            } label: {
                Label("Advanced", systemImage: "wrench.and.screwdriver")
                    .font(.body)
                    .foregroundStyle(.primary)
            }
        } header: {
            Text("Capabilities")
        } footer: {
            Text("Private chat works now. Connect Cloud or Agent only when a task needs them.")
                .font(.footnote)
                .fontWeight(.regular)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private var capabilitiesStatusLine: String {
        [
            "Private route",
            accountStore.nearCloudKeyConfigured ? "Cloud connected" : "Cloud not connected",
            agentCapabilityStatus
        ].joined(separator: " · ")
    }

    private var agentCapabilityStatus: String {
        if agentStore.ironclawRemoteWorkstationAvailable {
            return "Agent connected"
        }
        if modelCatalogStore.agentModels.contains(where: { $0.id == ModelOption.ironclawMobileModelID }) {
            return "Phone agent available"
        }
        return "Agent not set up"
    }

    private func powerToolSubRow(icon: String, title: String, subtitle: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .fontWeight(.regular)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func powerToolButtonRow(icon: String, title: String, subtitle: String?) -> some View {
        HStack(spacing: 12) {
            powerToolSubRow(icon: icon, title: title, subtitle: subtitle)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.textTertiary)
        }
        .contentShape(Rectangle())
    }

    // MARK: - 6. About

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version").foregroundStyle(.primary)
                Spacer()
                Text(appVersion)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)
            }
            Button {
                openLegalURL(LegalTerms.nearAIServicesTermsURL)
            } label: {
                Text("Terms").foregroundStyle(.primary)
            }
            Button {
                openLegalURL(LegalTerms.nearAIPrivacyPolicyURL)
            } label: {
                Text("Privacy Policy").foregroundStyle(.primary)
            }
            Button {
                accountStore.showBanner("Acknowledgments: NEAR AI, IronClaw, SwiftUI, WidgetKit, EventKit, CryptoKit, Vision, PDFKit, and the open web sources you choose to use.")
            } label: {
                Text("Acknowledgments").foregroundStyle(.primary)
            }
        }
    }

    private var footerSection: some View {
        Section {
            Text("https://private.near.ai")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 24, trailing: 16))
        }
    }

    // MARK: - Helpers

    private func saveChatSettings() async {
        isSavingSettings = true
        defer { isSavingSettings = false }
        await accountStore.saveUserSettings(
            systemPrompt: systemPrompt,
            webSearchEnabled: webSearchEnabled,
            notificationEnabled: notificationPreferenceEnabled,
            appearancePreference: appearancePreference,
            largeTextAsFileEnabled: largeTextAsFileEnabled,
            advancedParams: advancedParams
        )
        notificationPreferenceEnabled = accountStore.notificationPreferenceEnabled
        appearancePreference = accountStore.appearancePreference
        webSearchEnabled = modelCatalogStore.webSearchEnabled
        loadAdvancedParams(accountStore.advancedModelParams)
    }

    private var advancedParams: AdvancedModelParams {
        AdvancedModelParams(
            temperature: parseDouble(temperature, min: 0, max: 2),
            topP: parseDouble(topP, min: 0, max: 1),
            maxTokens: parseInt(maxTokens, min: 1, max: 200_000),
            reasoningEffort: reasoningEffort
        ).sanitized
    }

    private var setupProfile: UserSetupProfile {
        guard let accountID = sessionStore.setupAccountID else { return .defaults }
        return UserSetupStorage.load(for: accountID) ?? .defaults
    }

    private func openNearCloudSignup() {
        guard let url = URL(string: "https://cloud.near.ai") else { return }
        openURL(url)
    }

    private func openLegalURL(_ url: URL) {
        openURL(url)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }

    private func pasteNearCloudKeyFromClipboard() {
        #if canImport(UIKit)
        let value = UIPasteboard.general.string ?? ""
        #elseif canImport(AppKit)
        let value = NSPasteboard.general.string(forType: .string) ?? ""
        #else
        let value = ""
        #endif
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            accountStore.showBanner("Clipboard has no NEAR AI Cloud key.")
            return
        }
        nearCloudAPIKey = trimmed
        accountStore.showBanner("Key pasted. Tap Connect & Test.")
    }

    private func connectNearCloudAccount() {
        Task { _ = await accountStore.connectNearCloudAccount() }
    }

    private func connectNearCloud() {
        Task {
            let didConnect = await accountStore.connectNearCloudAPIKey(nearCloudAPIKey)
            if didConnect {
                nearCloudAPIKey = ""
            }
        }
    }

    private func loadAdvancedParams(_ params: AdvancedModelParams) {
        temperature = params.temperature.map { formatNumber($0) } ?? ""
        topP = params.topP.map { formatNumber($0) } ?? ""
        maxTokens = params.maxTokens.map(String.init) ?? ""
        reasoningEffort = params.reasoningEffort
    }

    private func loadIronclawBridge() {
        ironclawEnabled = agentStore.ironclawSettings.isEnabled
        ironclawEndpoint = agentStore.ironclawSettings.baseURL
        ironclawThreadID = agentStore.ironclawSettings.threadID
        ironclawToken = ""
    }

    private func openInitialDeepLinkIfNeeded() {
        guard !hasOpenedInitialDeepLink, let initialDeepLink else { return }
        hasOpenedInitialDeepLink = true
        openDeepLink(initialDeepLink)
    }

    private func openDeepLink(_ deepLink: AccountSettingsDeepLink) {
        powerToolsExpanded = true
        switch deepLink {
        case .nearCloudKeys:
            showingAPIKeysPowerTool = true
        case .ironclawAgent:
            showingIronclawPowerTool = true
        }
    }

    private func openIronclawPowerTool() {
        powerToolsExpanded = true
        showingIronclawPowerTool = true
    }

    private func openAPIKeysPowerTool() {
        powerToolsExpanded = true
        showingAPIKeysPowerTool = true
    }

    private func saveIronclawBridge() {
        agentStore.saveIronclawIntegration(
            isEnabled: ironclawEnabled,
            baseURL: ironclawEndpoint,
            authToken: ironclawToken,
            threadID: ironclawThreadID
        )
        loadIronclawBridge()
    }

    private func parseDouble(_ value: String, min: Double, max: Double) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let number = Double(trimmed) else { return nil }
        return Swift.min(Swift.max(number, min), max)
    }

    private func parseInt(_ value: String, min: Int, max: Int) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let number = Int(trimmed) else { return nil }
        return Swift.min(Swift.max(number, min), max)
    }

    private func formatNumber(_ value: Double) -> String {
        let formatted = String(format: "%.2f", value)
        return formatted
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }
}
