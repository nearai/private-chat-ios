import SwiftUI

struct AccountSettingsView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let initialDeepLink: AccountSettingsDeepLink?
    let onRunSetupAgain: () -> Void
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
    @State private var isImportingChats = false
    @State private var showingSignOutConfirm = false
    @State private var showingIronclawPowerTool = false
    @State private var showingAPIKeysPowerTool = false
    @State private var hasOpenedInitialDeepLink = false
    @AppStorage("account.powerToolsExpanded") private var powerToolsExpanded = false

    init(
        initialDeepLink: AccountSettingsDeepLink? = nil,
        onRunSetupAgain: @escaping () -> Void
    ) {
        self.initialDeepLink = initialDeepLink
        self.onRunSetupAgain = onRunSetupAgain
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
                systemPrompt = chatStore.systemPrompt
                webSearchEnabled = chatStore.webSearchEnabled
                notificationPreferenceEnabled = chatStore.notificationPreferenceEnabled
                appearancePreference = chatStore.appearancePreference
                largeTextAsFileEnabled = chatStore.largeTextAsFileEnabled
                loadAdvancedParams(chatStore.advancedModelParams)
                nearCloudAPIKey = ""
                loadIronclawBridge()
                if chatStore.billingSnapshot == nil {
                    Task { await chatStore.refreshBilling() }
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
                .environmentObject(chatStore)
            }
            .navigationDestination(isPresented: $showingAPIKeysPowerTool) {
                PowerToolAPIKeysView(
                    nearCloudAPIKey: $nearCloudAPIKey,
                    onPaste: pasteNearCloudKeyFromClipboard,
                    onConnectAccount: connectNearCloudAccount,
                    onConnect: connectNearCloud,
                    onOpenCloud: openNearCloudSignup
                )
                .environmentObject(chatStore)
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
                        isImportingChats = true
                        await chatStore.importChats(from: url)
                        isImportingChats = false
                    }
                case let .failure(error):
                    chatStore.bannerMessage = error.localizedDescription
                }
            }
            .sheet(isPresented: $showingShareGroups) {
                ShareGroupsView()
                    .environmentObject(chatStore)
            }
            .sheet(isPresented: $showingSecurity) {
                SecurityView()
                    .environmentObject(chatStore)
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
                .environmentObject(chatStore)
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
                    Text(sessionStore.profile?.user.email ?? "Signed in")
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
                    .environmentObject(chatStore)
            } label: {
                accountDetailRow(
                    title: "Plan",
                    detail: chatStore.billingSnapshot?.activeSubscription?.plan.capitalized ?? chatStore.currentBillingPlanName.capitalized
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
        }
    }

    /// Friendly name for the active default model, falling back to the
    /// raw id humanized if the catalog hasn't loaded yet.
    private var currentDefaultModelLabel: String {
        let id = chatStore.effectiveDefaultModelID
        if let option = chatStore.pickerModels.first(where: { $0.id == id }) {
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
                Text(isImportingChats ? "Importing Chats" : "Import Chats")
                    .foregroundStyle(.primary)
            }
            .disabled(isImportingChats)

            Text("Export signed transcripts and proof reports from a conversation's Share menu.")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)

        }
    }

    // MARK: - 4. Model defaults

    private var modelDefaultsSection: some View {
        Section("Model Defaults") {
            NavigationLink {
                DefaultModelDetailView()
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
            Text("Web search is explicit by default for private chat; research setup can turn current-source search on.")
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
                powerToolButtonRow(icon: "key", title: "Cloud keys", subtitle: chatStore.nearCloudKeyConfigured ? "NEAR AI Cloud connected" : "Connect NEAR AI Cloud")
            }
            .buttonStyle(.plain)

            Button {
                showingSecurity = true
            } label: {
                powerToolSubRow(icon: "seal", title: "Proof report", subtitle: chatStore.attestationSnapshot == nil ? "No proof report fetched" : "Proof report available")
                    .foregroundStyle(.primary)
            }

            DisclosureGroup(isExpanded: $powerToolsExpanded) {
                NavigationLink {
                    PowerToolDiagnosticsView()
                        .environmentObject(chatStore)
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
            Text("Private chat works now. Connect Cloud or Agent capabilities only when a task needs them.")
                .font(.footnote)
                .fontWeight(.regular)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private var capabilitiesStatusLine: String {
        [
            "Private route",
            chatStore.nearCloudKeyConfigured ? "Cloud connected" : "Cloud not connected",
            agentCapabilityStatus
        ].joined(separator: " · ")
    }

    private var agentCapabilityStatus: String {
        if chatStore.ironclawRemoteWorkstationAvailable {
            return "Agent connected"
        }
        if chatStore.agentModels.contains(where: { $0.id == ModelOption.ironclawMobileModelID }) {
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
                chatStore.bannerMessage = "Acknowledgments: NEAR AI, IronClaw, SwiftUI, WidgetKit, EventKit, CryptoKit, Vision, PDFKit, and the open web sources you choose to use."
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
        await chatStore.saveUserSettings(
            systemPrompt: systemPrompt,
            webSearchEnabled: webSearchEnabled,
            notificationEnabled: notificationPreferenceEnabled,
            appearancePreference: appearancePreference,
            largeTextAsFileEnabled: largeTextAsFileEnabled,
            advancedParams: advancedParams
        )
        notificationPreferenceEnabled = chatStore.notificationPreferenceEnabled
        appearancePreference = chatStore.appearancePreference
        loadAdvancedParams(chatStore.advancedModelParams)
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
            chatStore.bannerMessage = "Clipboard does not contain a NEAR AI Cloud key."
            return
        }
        nearCloudAPIKey = trimmed
        chatStore.bannerMessage = "Key pasted. Tap Connect & Test."
    }

    private func connectNearCloudAccount() {
        Task {
            _ = await chatStore.connectNearCloudAccount()
        }
    }

    private func connectNearCloud() {
        Task {
            let didConnect = await chatStore.connectNearCloudAPIKey(nearCloudAPIKey)
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
        ironclawEnabled = chatStore.ironclawSettings.isEnabled
        ironclawEndpoint = chatStore.ironclawSettings.baseURL
        ironclawThreadID = chatStore.ironclawSettings.threadID
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
        chatStore.saveIronclawIntegration(
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

// MARK: - Account section detail pushes

private struct SignInMethodDetailView: View {
    @EnvironmentObject private var sessionStore: SessionStore

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Method").foregroundStyle(.primary)
                    Spacer()
                    Text(sessionStore.session?.sessionID.isEmpty == false ? "Browser session" : "Session token")
                        .foregroundStyle(Color.textSecondary)
                }
            } footer: {
                Text("Browser session uses the NEAR Private auth flow. Switch to a session token only if instructed.")
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Sign-in method")
        .platformInlineNavigationTitle()
    }
}

private struct PlanDetailView: View {
    @EnvironmentObject private var chatStore: ChatStore

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Plan").foregroundStyle(.primary)
                    Spacer()
                    Text(chatStore.billingSnapshot?.activeSubscription?.plan.capitalized ?? chatStore.currentBillingPlanName.capitalized)
                        .foregroundStyle(Color.textSecondary)
                }
                if let currentPeriodEnd = chatStore.billingSnapshot?.activeSubscription?.currentPeriodEnd {
                    HStack {
                        Text("Renews").foregroundStyle(.primary)
                        Spacer()
                        Text(formattedBillingDate(currentPeriodEnd))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Plan")
        .platformInlineNavigationTitle()
    }

    private func formattedBillingDate(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parsedDate = formatter.date(from: trimmed) ?? {
            let fallback = ISO8601DateFormatter()
            fallback.formatOptions = [.withInternetDateTime]
            return fallback.date(from: trimmed)
        }()
        guard let parsedDate else { return trimmed }
        return parsedDate.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

// MARK: - Appearance section detail pushes

private struct DynamicTypeDetailView: View {
    var body: some View {
        List {
            Section {
                HStack {
                    Text("Source").foregroundStyle(.primary)
                    Spacer()
                    Text("iOS Settings").foregroundStyle(Color.textSecondary)
                }
            } footer: {
                Text("This app respects the Dynamic Type size set in iOS Settings → Display & Brightness → Text Size.")
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Dynamic Type")
        .platformInlineNavigationTitle()
    }
}

// MARK: - Model defaults detail pushes

private struct DefaultModelDetailView: View {
    @EnvironmentObject private var chatStore: ChatStore

    private var candidates: [ModelOption] {
        chatStore.preferredDefaultModelCandidates
    }

    private var currentSelection: String {
        chatStore.effectiveDefaultModelID
    }

    var body: some View {
        List {
            Section {
                if candidates.isEmpty {
                    Text("Loading model catalog…")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                } else {
                    ForEach(candidates) { option in
                        Button {
                            // Writing the SHIPPED default as nil keeps the
                            // store clean for users who never override.
                            let next: String? = option.id == ChatStore.defaultModelID ? nil : option.id
                            chatStore.setPreferredDefaultModel(next)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.displayName)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    if let subtitle = subtitle(for: option) {
                                        Text(subtitle)
                                            .font(.footnote)
                                            .fontWeight(.regular)
                                            .foregroundStyle(Color.textSecondary)
                                    }
                                }
                                Spacer(minLength: 0)
                                if option.id == currentSelection {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(Color.actionPrimary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } footer: {
                Text("Used when starting a new chat. Switch routes per-chat from the model picker.")
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Default model")
        .platformInlineNavigationTitle()
    }

    private func subtitle(for option: ModelOption) -> String? {
        if option.id == ChatStore.defaultModelID {
            return "Shipped default · private route with proof"
        }
        if option.isNearCloudModel {
            return "NEAR AI Cloud · no NEAR Private proof"
        }
        if option.isVerifiable {
            return "NEAR Private · attested when proof is fresh"
        }
        return nil
    }
}

private struct ReasoningEffortDetailView: View {
    @Binding var selection: ModelReasoningEffort
    let onSave: () -> Void

    var body: some View {
        List {
            Section {
                Picker("Reasoning effort", selection: $selection) {
                    ForEach(ModelReasoningEffort.allCases) { effort in
                        Text(effort.title).tag(effort)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text(selection.detail).foregroundStyle(Color.textSecondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Reasoning effort")
        .platformInlineNavigationTitle()
        .onChange(of: selection) { _, _ in onSave() }
    }
}

// MARK: - Capability detail pushes

private struct PowerToolIronclawView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Binding var ironclawEnabled: Bool
    @Binding var ironclawEndpoint: String
    @Binding var ironclawToken: String
    @Binding var ironclawThreadID: String
    let onSave: () -> Void
    let onReload: () -> Void

    var body: some View {
        Form {
            Section("Status") {
                HStack {
                    Text("Agent").foregroundStyle(.primary)
                    Spacer()
                    Text(chatStore.ironclawStatusText).foregroundStyle(Color.textSecondary)
                }
                Toggle("Enable Hosted Agent", isOn: $ironclawEnabled)
            }

            Section("Readiness") {
                IronclawBridgeReadinessCard(
                    endpointConnected: chatStore.ironclawRemoteWorkstationAvailable,
                    tokenConfigured: chatStore.ironclawTokenConfigured,
                    lastVerifiedAt: chatStore.ironclawLastVerifiedAt,
                    isChecking: chatStore.isTestingIronclawWorkstation,
                    toolNames: chatStore.ironclawToolNames
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section("Agent connection") {
                TextField("Hosted IronClaw URL", text: $ironclawEndpoint)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                SecureField(chatStore.ironclawTokenConfigured ? "Token saved" : "Bearer token", text: $ironclawToken)
                TextField("Optional thread id", text: $ironclawThreadID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section {
                Button {
                    onSave()
                } label: {
                    Label("Save Agent Connection", systemImage: "point.3.connected.trianglepath.dotted")
                }

                Button {
                    Task { await chatStore.testIronclawConnection() }
                } label: {
                    Label(chatStore.isTestingIntegration ? "Testing" : "Test Connection", systemImage: "checkmark.circle")
                }
                .disabled(chatStore.isTestingIntegration)

                Button {
                    Task { await chatStore.testIronclawWorkstation() }
                } label: {
                    Label(chatStore.isTestingIronclawWorkstation ? "Checking" : "Check Hosted Tools", systemImage: "terminal")
                }
                .disabled(chatStore.isTestingIronclawWorkstation)
            }

            if chatStore.ironclawSettings.hasEndpoint || chatStore.ironclawTokenConfigured {
                Section {
                    Button(role: .destructive) {
                        chatStore.disconnectIronclaw()
                        onReload()
                    } label: {
                        Label("Disconnect Agent", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Agent connection")
        .platformInlineNavigationTitle()
        .onAppear { onReload() }
    }
}

private struct PowerToolAPIKeysView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Binding var nearCloudAPIKey: String
    let onPaste: () -> Void
    let onConnectAccount: () -> Void
    let onConnect: () -> Void
    let onOpenCloud: () -> Void

    var body: some View {
        Form {
            Section {
                NearCloudConnectionCard(
                    apiKey: $nearCloudAPIKey,
                    isConnected: chatStore.nearCloudKeyConfigured,
                    isConnecting: chatStore.isTestingNearCloudKey,
                    isAutoConnecting: chatStore.isConnectingNearCloudAccount,
                    modelCount: chatStore.cloudModels.count,
                    onConnectAccount: onConnectAccount,
                    onOpenCloud: onOpenCloud,
                    onPasteKey: onPaste,
                    onConnect: onConnect,
                    onRemove: {
                        chatStore.clearNearCloudAPIKey()
                        nearCloudAPIKey = ""
                    }
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } header: {
                Text("NEAR AI Cloud")
            }
        }
        .navigationTitle("NEAR AI Cloud")
        .platformInlineNavigationTitle()
    }
}

private struct PowerToolDiagnosticsView: View {
    @EnvironmentObject private var chatStore: ChatStore

    var body: some View {
        Form {
            Section("Results") {
                if chatStore.diagnosticChecks.isEmpty {
                    HStack {
                        Text("Diagnostics").foregroundStyle(.primary)
                        Spacer()
                        Text("Not run").foregroundStyle(Color.textSecondary)
                    }
                } else {
                    ForEach(chatStore.diagnosticChecks) { check in
                        DiagnosticCheckRow(check: check)
                    }
                }
            }

            Section {
                Button {
                    Task { await chatStore.runDiagnostics() }
                } label: {
                    Label(chatStore.isRunningDiagnostics ? "Running Diagnostics" : "Run Diagnostics", systemImage: "stethoscope")
                }
                .disabled(chatStore.isRunningDiagnostics)
            }
        }
        .navigationTitle("Diagnostics")
        .platformInlineNavigationTitle()
    }
}

private struct PowerToolEndpointsView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @Binding var systemPrompt: String
    @Binding var temperature: String
    @Binding var topP: String
    @Binding var maxTokens: String
    @Binding var largeTextAsFileEnabled: Bool
    @Binding var isSavingSettings: Bool
    let onSave: () -> Void
    let advancedParamsSummary: String

    var body: some View {
        Form {
            Section("Advanced API") {
                InfoRow(title: "Private API", value: AppConfiguration.production.baseURL.absoluteString, monospaced: true)
                InfoRow(title: "Callback", value: AppConfiguration.production.callbackURL.absoluteString, monospaced: true)
                InfoRow(title: "Auth", value: sessionStore.session?.sessionID.isEmpty == false ? "Browser session" : "Session token")
            }

            Section("Model parameters") {
                AdvancedParamField(title: "Temperature", detail: "0-2", placeholder: "Default", text: $temperature, keyboard: .decimalPad)
                AdvancedParamField(title: "Top P", detail: "0-1", placeholder: "Default", text: $topP, keyboard: .decimalPad)
                AdvancedParamField(title: "Max Tokens", detail: "1-200000", placeholder: "Default", text: $maxTokens, keyboard: .numberPad)
                InfoRow(title: "Active", value: advancedParamsSummary)
            }

            Section("System prompt") {
                TextField("System prompt", text: $systemPrompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(3...8)
            }

            Section("Input") {
                Toggle("Large Paste as File", isOn: $largeTextAsFileEnabled)
            }

            Section {
                Button {
                    onSave()
                } label: {
                    Label(isSavingSettings ? "Saving" : "Save Advanced Settings", systemImage: "checkmark.circle")
                }
                .disabled(isSavingSettings)
            }
        }
        .navigationTitle("Advanced API")
        .platformInlineNavigationTitle()
    }
}

// MARK: - CapabilitiesView (unchanged)

private struct CapabilitiesEntryRow: View {
    let statusLine: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.brandBlue)
                .frame(width: 34, height: 34)
                .background(Color.brandBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                    Text("Capabilities")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(statusLine)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.brandBlue)
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
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var sessionStore: SessionStore
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
                        trustLine: "Trust boundary: proof reports cover route evidence, not whether an answer is true.",
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
                        trustLine: "Trust boundary: hosted IronClaw receives prompt text plus file metadata unless source excerpts are included.",
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

    private var capabilityHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Chat about anything. The app starts private, then adds Web, Cloud, Agent, or Council when the task needs them.")
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
            chatStore.nearCloudKeyConfigured ? "Cloud connected" : "Cloud not connected",
            agentStatus
        ].joined(separator: " · ")
    }

    private var privateHeaderStatus: String {
        chatStore.attestationSnapshot == nil ? "Private route" : "Private \(privateStatus.lowercased())"
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
            modelCatalogLoaded: !chatStore.models.isEmpty,
            privateModelAvailable: chatStore.pickerModels.contains { !$0.isExternalModel },
            defaultCouncilModelCount: chatStore.defaultCouncilModels.count,
            ironclawMobileAvailable: chatStore.agentModels.contains { $0.id == ModelOption.ironclawMobileModelID },
            hostedIronclawAvailable: chatStore.ironclawRemoteWorkstationAvailable,
            nearCloudKeyConfigured: chatStore.nearCloudKeyConfigured
        )
    }

    private var setupPlan: AppSetupPlan {
        AppSetupPlan(profile: setupProfile, readiness: readinessSnapshot)
    }

    private var routeBlock: CapabilityRouteBlock? {
        guard let issue = chatStore.routeReadinessIssue else { return nil }
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
        guard let snapshot = chatStore.attestationSnapshot else { return false }
        return AttestationFreshness.classify(attestedAt: snapshot.fetchedAt) != .stale
    }

    private var nextStep: CapabilityNextStep? {
        let recommendation = CapabilityNextStepPlanner.recommend(
            routeBlock: routeBlock,
            setupPlan: setupPlan,
            currentRoute: chatStore.selectedRouteKind,
            hasFreshPrivateProof: hasFreshPrivateProof,
            hostedIronclawAvailable: chatStore.ironclawRemoteWorkstationAvailable,
            autoCouncilReady: chatStore.defaultCouncilModels.count >= 2
        )
        if recommendation?.kind == .rerunSetup, onRunSetupAgain == nil {
            return nil
        }
        return recommendation
    }

    private var privateStatus: String {
        guard let snapshot = chatStore.attestationSnapshot else { return "No proof yet" }
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
        guard let snapshot = chatStore.attestationSnapshot else { return Color.brandBlue }
        switch AttestationFreshness.classify(attestedAt: snapshot.fetchedAt) {
        case .underTwoMinutes, .underOneHour:
            return Color.proofVerified
        case .stale:
            return Color.proofStale
        }
    }

    private var privateDetail: String {
        guard let snapshot = chatStore.attestationSnapshot else {
            return "Current route: \(chatStore.selectedProviderDisplayName). Open Proof report when you need signed private-route evidence."
        }

        let coveredCount = max(snapshot.modelAttestationCount, snapshot.coveredModelIDs.count)
        let freshness = AttestationFreshness.classify(attestedAt: snapshot.fetchedAt).shortLabel
        let countLabel = "\(coveredCount) model\(coveredCount == 1 ? "" : "s")"
        return "Last report: \(countLabel) listed · \(freshness) · Current route: \(chatStore.selectedProviderDisplayName)."
    }

    private var cloudStatus: String {
        chatStore.nearCloudKeyConfigured ? "Connected" : "Not connected"
    }

    private var cloudStatusColor: Color {
        chatStore.nearCloudKeyConfigured ? Color.brandBlue : Color.proofStale
    }

    private var cloudDetail: String {
        if chatStore.nearCloudKeyConfigured {
            let plan = chatStore.billingSnapshot?.activeSubscription?.plan ?? "Cloud connected"
            return chatStore.selectedRouteUsesNearCloud
                ? "Current route uses \(chatStore.selectedModelDisplayName) through NEAR AI Cloud. \(plan)."
                : "Cloud unlocks premium external model rows in the picker. \(plan)."
        }
        return "Connect NEAR AI Cloud before sending with locked Cloud routes or mixed Cloud councils."
    }

    private var agentStatus: String {
        if chatStore.ironclawRemoteWorkstationAvailable {
            return "Hosted connected"
        }
        if chatStore.agentModels.contains(where: { $0.id == ModelOption.ironclawMobileModelID }) {
            return "Phone ready"
        }
        return "Not ready"
    }

    private var agentStatusColor: Color {
        if chatStore.ironclawRemoteWorkstationAvailable {
            return Color.proofVerified
        }
        return chatStore.agentModels.contains(where: { $0.id == ModelOption.ironclawMobileModelID }) ? Color.brandBlue : Color.proofStale
    }

    private var agentDetail: String {
        if let verifiedAt = chatStore.ironclawLastVerifiedAt, chatStore.ironclawRemoteWorkstationAvailable {
            return "Hosted tools last checked \(verifiedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))."
        }
        return chatStore.ironclawStatusText
    }

    private var councilStatus: String {
        let activeCount = chatStore.councilModelIDs.count
        if activeCount >= 2 {
            return "Current lineup ready"
        }
        if chatStore.defaultCouncilModels.count >= 2 {
            return "Auto lineup ready"
        }
        return "Needs one more model"
    }

    private var councilStatusColor: Color {
        (chatStore.councilModelIDs.count >= 2 || chatStore.defaultCouncilModels.count >= 2) ? Color.brandBlue : Color.proofStale
    }

    private var councilDetail: String {
        let models = chatStore.councilModelNames.isEmpty ? chatStore.defaultCouncilModels.map(\.displayName) : chatStore.councilModelNames
        let lineup = models.prefix(3).joined(separator: " · ")
        let suffix = models.count > 3 ? " +\(models.count - 3) more" : ""

        if models.isEmpty {
            return "Council turns on once at least two compatible chat models are available."
        }

        if !chatStore.nearCloudKeyConfigured,
           chatStore.defaultCouncilModels.contains(where: \.isNearCloudModel) {
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
            title: chatStore.nearCloudKeyConfigured ? "Manage Cloud keys" : "Connect Cloud",
            systemImage: chatStore.nearCloudKeyConfigured ? "slider.horizontal.3" : "key",
            role: .primary
        ) {
            dismissThen {
                onOpenAccountSettings(.nearCloudKeys)
            }
        }
    }

    private var agentPrimaryAction: CapabilityCardAction? {
        if chatStore.ironclawRemoteWorkstationAvailable, let onOpenAgentWorkspace {
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
        guard chatStore.ironclawRemoteWorkstationAvailable, let onOpenAccountSettings else { return nil }
        return CapabilityCardAction(title: "Manage Agent Connection", systemImage: "slider.horizontal.3", role: .secondary) {
            dismissThen {
                onOpenAccountSettings(.ironclawAgent)
            }
        }
    }

    private var councilPrimaryAction: CapabilityCardAction? {
        guard chatStore.councilModelIDs.count < 2, chatStore.defaultCouncilModels.count >= 2 else { return nil }
        return CapabilityCardAction(title: "Use recommended Council", systemImage: "square.grid.2x2", role: .primary) {
            chatStore.useDefaultCouncilLineup()
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
                chatStore.useDefaultCouncilLineup()
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

private struct CapabilityStatusItemModel: Identifiable {
    let title: String
    let value: String
    let tint: Color

    var id: String { title }
}

private struct CapabilityStatusStrip: View {
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

private struct CapabilityCardAction {
    enum Role {
        case primary
        case secondary
    }

    let title: String
    let systemImage: String
    let role: Role
    let action: () -> Void
}

private struct CapabilityCard: View {
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

private struct CapabilityActionButton: View {
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

private struct IronclawBridgeReadinessCard: View {
    let endpointConnected: Bool
    let tokenConfigured: Bool
    let lastVerifiedAt: Date?
    let isChecking: Bool
    let toolNames: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "terminal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 28, height: 28)
                    .background(Color.brandBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Agent Readiness")
                        .font(.subheadline.weight(.semibold))
                    Text(statusLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                readinessPill(title: "Connection", value: endpointConnected ? "Hosted" : "Missing", symbolName: "server.rack", active: endpointConnected)
                readinessPill(title: "Token", value: tokenConfigured ? "Saved" : "Optional", symbolName: "key", active: tokenConfigured)
                readinessPill(title: "Tools", value: toolValue, symbolName: "chevron.left.forwardslash.chevron.right", active: toolsAvailable)
                readinessPill(title: "Repo Auth", value: "Gated", symbolName: "lock.shield", active: true)
            }

            if !toolNames.isEmpty {
                Text(toolSummary)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }

    private var toolValue: String {
        if isChecking {
            return "Checking"
        }
        if !toolNames.isEmpty {
            return "\(toolNames.count) tools"
        }
        if let lastVerifiedAt {
            return lastVerifiedAt.formatted(date: .omitted, time: .shortened)
        }
        return "Check"
    }

    private var statusLine: String {
        if isChecking {
            return "Checking shell and git"
        }
        if lastVerifiedAt != nil {
            return toolNames.isEmpty ? "Shell and git checked" : "Shell, git, files, and agent tools checked"
        }
        if !toolNames.isEmpty {
            return "Tool catalog available; check shell/git before running"
        }
        if endpointConnected {
            return "Agent connection ready; check hosted tools"
        }
        return "Add a Hosted IronClaw URL"
    }

    private var toolsAvailable: Bool {
        lastVerifiedAt != nil || !toolNames.isEmpty
    }

    private var toolSummary: String {
        let priority = ["shell", "github", "grep", "read_file", "write_file", "apply_patch", "nearai_web_search"]
        let available = priority.filter { toolNames.contains($0) }
        let names = available.isEmpty ? Array(toolNames.prefix(6)) : available
        return names.joined(separator: " · ")
    }

    private func readinessPill(title: String, value: String, symbolName: String, active: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(active ? Color.brandBlue : .secondary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(active ? Color.brandBlue.opacity(0.07) : Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct NearCloudConnectionCard: View {
    @Binding var apiKey: String
    let isConnected: Bool
    let isConnecting: Bool
    let isAutoConnecting: Bool
    let modelCount: Int
    let onConnectAccount: () -> Void
    let onOpenCloud: () -> Void
    let onPasteKey: () -> Void
    let onConnect: () -> Void
    let onRemove: () -> Void

    private var trimmedKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header — same shape in both states; copy + badge swap.
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isConnected ? "cloud.fill" : "cloud")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isConnected ? Color.brandBlue : Color.textSecondary)
                    .frame(width: 34, height: 34)
                    .background((isConnected ? Color.brandBlue : Color.secondary).opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("NEAR AI Cloud")
                        .font(.subheadline.weight(.bold))
                    Text(isConnected
                         ? "\(max(modelCount, 1)) cloud models ready."
                         : "Link your NEAR account, or paste a key and test it before it is saved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Text(isConnected ? "Connected" : "Not connected")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isConnected ? Color.trustVerified : Color.proofStale)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background((isConnected ? Color.trustVerified : Color.proofStale).opacity(0.12), in: Capsule())
            }

            if isConnected {
                connectedBody
            } else {
                setupBody
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Connected state — minimal: open cloud, disconnect.

    private var connectedBody: some View {
        HStack(spacing: 8) {
            Button(action: onOpenCloud) {
                Label("Open NEAR AI Cloud", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.bordered)

            Spacer(minLength: 0)

            Button(role: .destructive, action: onRemove) {
                Label("Disconnect", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .disabled(isAutoConnecting || isConnecting)
        }
        .font(.caption.weight(.semibold))
    }

    // MARK: Setup state — one-tap account link first, key fallback below.

    private var setupBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onConnectAccount) {
                Label(isAutoConnecting ? "Connecting Account" : "Connect with NEAR account",
                      systemImage: isAutoConnecting ? "arrow.triangle.2.circlepath" : "person.crop.circle.badge.checkmark")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isAutoConnecting || isConnecting)

            // Fallback paste-key flow — inline, single column.
            VStack(alignment: .leading, spacing: 8) {
                Label("Or paste a key", systemImage: "key")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                Text("Open NEAR AI Cloud, create an API key, then paste it here and test before saving.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                SecureField("Paste NEAR AI Cloud key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.appBorder, lineWidth: 1)
                    }

                // Restacked: two small inline utilities up top, the
                // primary Connect & Test action gets its own full-width
                // row below so it reads as the canonical action.
                HStack(spacing: 8) {
                    Button(action: onOpenCloud) {
                        Label("Open Cloud", systemImage: "arrow.up.forward.app")
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(action: onPasteKey) {
                        Label("Paste", systemImage: "doc.on.clipboard")
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Button(action: onConnect) {
                    Label(isConnecting ? "Testing…" : "Connect & Test",
                          systemImage: isConnecting ? "arrow.triangle.2.circlepath" : "checkmark.seal")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAutoConnecting || isConnecting || trimmedKey.isEmpty)
            }
            .padding(12)
            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

private struct AdvancedParamField: View {
    let title: String
    let detail: String
    let placeholder: String
    @Binding var text: String
    let keyboard: UIKeyboardType

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.plain)
                .frame(maxWidth: 120)
        }
    }
}
