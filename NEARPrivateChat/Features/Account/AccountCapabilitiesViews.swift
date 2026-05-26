import SwiftUI

struct AccountSettingsView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
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
    @State private var powerToolsUnlocked = false
    @FocusState private var focusedPowerToolField: PowerToolField?

    private enum PowerToolField: Hashable {
        case nearCloudKey
        case ironclawEndpoint
        case temperature
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.brandBlue.opacity(0.13))
                            .frame(width: 44, height: 44)
                            .overlay {
                                Text(String(sessionStore.displayName.prefix(1)).uppercased())
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(Color.brandBlue)
                            }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(sessionStore.displayName)
                                .font(.headline)
                                .lineLimit(1)
                            if let email = sessionStore.profile?.user.email {
                                Text(email)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Defaults") {
                    Button {
                        dismiss()
                        onRunSetupAgain()
                    } label: {
                        Label("Reset Defaults", systemImage: "arrow.counterclockwise")
                    }
                    Text("Keeps your chats, projects, and account. It resets route, model, and composer defaults without opening setup.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Appearance", systemImage: "circle.lefthalf.filled")
                            .font(.subheadline.weight(.semibold))

                        Picker("Appearance", selection: $appearancePreference) {
                            ForEach(AppAppearancePreference.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(appearancePreference.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)

                    Toggle("Notifications preference", isOn: $notificationPreferenceEnabled)
                    Toggle("Web Search by Default", isOn: $webSearchEnabled)
                    Toggle("Large Paste as File", isOn: $largeTextAsFileEnabled)

                    Button {
                        Task { await saveChatSettings() }
                    } label: {
                        Label(isSavingSettings ? "Saving Preferences" : "Save Preferences", systemImage: "checkmark.circle")
                    }
                    .disabled(isSavingSettings)
                } header: {
                    Text("Preferences")
                } footer: {
                    Text("Appearance and notification preference sync with your NEAR Private account. Native push delivery is not enabled in this iPhone build yet.")
                }

                if showsPowerTools {
                    Section("Capabilities") {
                        Button {
                            showingCapabilities = true
                        } label: {
                            CapabilitiesEntryRow(
                                statusLine: capabilitySummary,
                                detail: "Capabilities, trust, and integrations"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Section("Developer Diagnostics") {
                        if chatStore.diagnosticChecks.isEmpty {
                            InfoRow(title: "Preflight", value: "Run before demos to verify models, web, IronClaw, and keys.")
                        } else {
                            ForEach(chatStore.diagnosticChecks) { check in
                                DiagnosticCheckRow(check: check)
                            }
                        }

                        Button {
                            Task { await chatStore.runDiagnostics() }
                        } label: {
                            Label(chatStore.isRunningDiagnostics ? "Running Diagnostics" : "Run Full Diagnostics", systemImage: "stethoscope")
                        }
                        .disabled(chatStore.isRunningDiagnostics)
                    }
                }

                if showsPowerTools {
                    Section("Composer") {
                        TextField("System prompt", text: $systemPrompt, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(3...8)
                            .padding(10)
                            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                Section("Privacy") {
                    Button {
                        showingChatImporter = true
                    } label: {
                        Label(isImportingChats ? "Importing Chats" : "Import Chats", systemImage: "square.and.arrow.down")
                    }
                    .disabled(isImportingChats)
                }

                Section("Sharing") {
                    Button {
                        showingShareGroups = true
                    } label: {
                        Label("Manage Share Groups", systemImage: "person.3")
                    }
                }

                Section("Models & Billing") {
                    InfoRow(title: "Status", value: chatStore.billingSnapshot?.summary ?? "Not loaded")
                    if let active = chatStore.billingSnapshot?.activeSubscription {
                        InfoRow(title: "Provider", value: active.provider)
                        if let currentPeriodEnd = active.currentPeriodEnd {
                            InfoRow(title: "Renews", value: formattedBillingDate(currentPeriodEnd))
                        }
                    }
                    ForEach(Array((chatStore.billingSnapshot?.plans ?? []).prefix(3))) { plan in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(plan.name)
                                .font(.subheadline.weight(.semibold))
                            Text(planDetail(plan))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        Task { await chatStore.refreshBilling() }
                    } label: {
                        Label(chatStore.isLoadingBilling ? "Refreshing Billing" : "Refresh Billing", systemImage: "creditcard")
                    }
                    .disabled(chatStore.isLoadingBilling)
                }

                if showsPowerTools {
                    Section("Developer") {
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 12) {
                                InfoRow(title: "Endpoint", value: AppConfiguration.production.baseURL.absoluteString, monospaced: true)
                                InfoRow(title: "Callback", value: AppConfiguration.production.callbackURL.absoluteString, monospaced: true)
                                InfoRow(title: "Auth", value: sessionStore.session?.sessionID.isEmpty == false ? "Browser session" : "Session token")

                                Divider()

                                AdvancedParamField(
                                    title: "Temperature",
                                    detail: "0-2",
                                    placeholder: "Default",
                                    text: $temperature,
                                    keyboard: .decimalPad
                                )
                                .focused($focusedPowerToolField, equals: .temperature)
                                AdvancedParamField(
                                    title: "Top P",
                                    detail: "0-1",
                                    placeholder: "Default",
                                    text: $topP,
                                    keyboard: .decimalPad
                                )
                                AdvancedParamField(
                                    title: "Max Tokens",
                                    detail: "1-200000",
                                    placeholder: "Default",
                                    text: $maxTokens,
                                    keyboard: .numberPad
                                )
                                InfoRow(title: "Active", value: advancedParams.summary)

                                HStack {
                                    Button {
                                        Task { await saveChatSettings() }
                                    } label: {
                                        Label(isSavingSettings ? "Saving" : "Save", systemImage: "checkmark.circle")
                                    }
                                    .disabled(isSavingSettings)

                                    Spacer()

                                    Button {
                                        temperature = ""
                                        topP = ""
                                        maxTokens = ""
                                        reasoningEffort = .automatic
                                    } label: {
                                        Label("Reset", systemImage: "arrow.counterclockwise")
                                    }
                                }
                            }
                            .padding(.top, 10)
                        } label: {
                            Label("Connection & Advanced Params", systemImage: "hammer")
                        }
                    }

                    Section("Models") {
                        NearCloudConnectionCard(
                            apiKey: $nearCloudAPIKey,
                            isConnected: chatStore.nearCloudKeyConfigured,
                            isConnecting: chatStore.isTestingNearCloudKey,
                            isAutoConnecting: chatStore.isConnectingNearCloudAccount,
                            modelCount: chatStore.cloudModels.count,
                            onConnectAccount: connectNearCloudAccount,
                            onOpenCloud: openNearCloudSignup,
                            onPasteKey: pasteNearCloudKeyFromClipboard,
                            onConnect: connectNearCloud,
                            onRemove: {
                                chatStore.clearNearCloudAPIKey()
                                nearCloudAPIKey = ""
                            }
                        )

                        VStack(alignment: .leading, spacing: 8) {
                            Label("Reasoning effort", systemImage: "brain.head.profile")
                                .font(.subheadline.weight(.semibold))
                            Picker("Reasoning effort", selection: $reasoningEffort) {
                                ForEach(ModelReasoningEffort.allCases) { effort in
                                    Text(effort.title).tag(effort)
                                }
                            }
                            .pickerStyle(.segmented)
                            Text(reasoningEffort.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Applied to NEAR Cloud chat requests as a reasoning budget when the provider supports it. Auto omits the field.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button {
                                Task { await saveChatSettings() }
                            } label: {
                                Label(isSavingSettings ? "Saving" : "Save Cloud Defaults", systemImage: "checkmark.circle")
                            }
                            .disabled(isSavingSettings)
                        }
                        .padding(.vertical, 4)

                        SecureField("Paste key here", text: $nearCloudAPIKey)
                            .tokenInputTraits()
                            .focused($focusedPowerToolField, equals: .nearCloudKey)
                    }

                    Section("Integrations") {
                        InfoRow(title: "Status", value: chatStore.ironclawStatusText)
                        Toggle("Enable Hosted Agent", isOn: $ironclawEnabled)

                        IronclawBridgeReadinessCard(
                            endpointConnected: chatStore.ironclawRemoteWorkstationAvailable,
                            tokenConfigured: chatStore.ironclawTokenConfigured,
                            lastVerifiedAt: chatStore.ironclawLastVerifiedAt,
                            isChecking: chatStore.isTestingIronclawWorkstation,
                            toolNames: chatStore.ironclawToolNames
                        )

                        TextField("https://your-ironclaw.example.com", text: $ironclawEndpoint)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .tokenInputTraits()
                            .focused($focusedPowerToolField, equals: .ironclawEndpoint)

                        SecureField(chatStore.ironclawTokenConfigured ? "Token saved" : "Bearer token", text: $ironclawToken)
                            .tokenInputTraits()

                        TextField("Optional thread id", text: $ironclawThreadID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .tokenInputTraits()

                        Text("Use a public HTTPS bridge from your computer, for example Cloudflare Tunnel, Tailscale Funnel, or ngrok. Direct LAN and localhost URLs are blocked on iPhone builds. Use Tools to verify shell/git before a serious run.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Button {
                                saveIronclawBridge()
                            } label: {
                                Label("Save Bridge", systemImage: "point.3.connected.trianglepath.dotted")
                            }

                            Spacer()

                            Button {
                                Task { await chatStore.testIronclawConnection() }
                            } label: {
                                Label(chatStore.isTestingIntegration ? "Testing" : "Test", systemImage: "checkmark.circle")
                            }
                            .disabled(chatStore.isTestingIntegration)

                            Button {
                                Task { await chatStore.testIronclawWorkstation() }
                            } label: {
                                Label(chatStore.isTestingIronclawWorkstation ? "Checking" : "Tools", systemImage: "terminal")
                            }
                            .disabled(chatStore.isTestingIronclawWorkstation)
                        }

                        if chatStore.ironclawSettings.hasEndpoint || chatStore.ironclawTokenConfigured {
                            Button(role: .destructive) {
                                chatStore.disconnectIronclaw()
                                loadIronclawBridge()
                            } label: {
                                Label("Disconnect IronClaw", systemImage: "trash")
                            }
                        }
                    }
                } else {
                    Section("Capabilities") {
                        PowerToolsUnlockCard(
                            onShowAll: { revealPowerTools() },
                            onCloudKey: { revealPowerTools(focus: .nearCloudKey) },
                            onIronclaw: { revealPowerTools(focus: .ironclawEndpoint) },
                            onAdvanced: { revealPowerTools(focus: .temperature) },
                            onDiagnostics: {
                                revealPowerTools()
                                Task { await chatStore.runDiagnostics() }
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }

                Section {
                    Button(role: .destructive) {
                        sessionStore.signOut()
                        dismiss()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
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
                powerToolsUnlocked = powerToolsUnlocked || isPowerMode
                if chatStore.billingSnapshot == nil {
                    Task { await chatStore.refreshBilling() }
                }
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
                    onOpenAccountSettings: {},
                    onOpenSecurity: { showingSecurity = true },
                    onOpenAgentWorkspace: nil,
                    onRunSetupAgain: onRunSetupAgain
                )
                .environmentObject(chatStore)
                .environmentObject(sessionStore)
            }
        }
        .platformLargeDetent()
    }

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

    private var isPowerMode: Bool {
        setupProfile.experienceMode == .power
    }

    private var showsPowerTools: Bool {
        powerToolsUnlocked || isPowerMode || chatStore.routeReadinessIssue != nil
    }

    private var capabilitySummary: String {
        [
            "Private ready",
            chatStore.nearCloudKeyConfigured ? "Cloud connected" : "Cloud not connected",
            chatStore.ironclawRemoteWorkstationAvailable ? "Agent connected" : "Agent phone ready"
        ].joined(separator: " · ")
    }

    private func revealPowerTools(focus: PowerToolField? = nil) {
        if let accountID = sessionStore.setupAccountID {
            var profile = setupProfile
            profile.experienceMode = .power
            UserSetupStorage.save(profile, for: accountID)
        }
        powerToolsUnlocked = true
        guard let focus else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            focusedPowerToolField = focus
        }
    }

    private func openNearCloudSignup() {
        guard let url = URL(string: "https://cloud.near.ai") else { return }
        openURL(url)
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
            chatStore.bannerMessage = "Clipboard does not contain a NEAR Cloud key."
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

    private func planDetail(_ plan: SubscriptionPlan) -> String {
        var parts: [String] = []
        if let price = plan.price {
            parts.append(price == 0 ? "Free" : String(format: "$%.2f", price))
        }
        if let maxTokens = plan.monthlyTokens?.max {
            parts.append("\(maxTokens.formatted()) tokens")
        }
        if let modelCount = plan.allowedModels?.count, modelCount > 0 {
            parts.append("\(modelCount) models")
        }
        if let trialDays = plan.trialPeriodDays, trialDays > 0 {
            parts.append("\(trialDays)d trial")
        }
        return parts.isEmpty ? "Plan details unavailable" : parts.joined(separator: " · ")
    }
}

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

    let onOpenAccountSettings: (() -> Void)?
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
                        iconName: "lock.shield",
                        title: "Private Inference",
                        status: privateStatus,
                        statusColor: privateStatusColor,
                        summary: "Private chat works immediately on iPhone and can attach proof when the selected route supports it.",
                        trustLine: "Trust boundary: verification proves route evidence, not that an answer is true.",
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
                        trustLine: "Trust boundary: Cloud turns use privacy proxy routing, but they are not NEAR Private verification proof.",
                        detail: cloudDetail,
                        primaryAction: cloudPrimaryAction,
                        secondaryAction: nil
                    )

                    CapabilityCard(
                        iconName: "terminal.fill",
                        title: "IronClaw Agent",
                        status: agentStatus,
                        statusColor: agentStatusColor,
                        summary: "Use phone-safe agent skills now, then hand off repo, shell, and workstation tasks when hosted IronClaw is connected.",
                        trustLine: "Trust boundary: agent runs can read files, use tools, and act with any connected credentials.",
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
            Text("Private chat is ready now. Connect Cloud or hosted agents only when a task needs them.")
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
            "Private ready",
            chatStore.nearCloudKeyConfigured ? "Cloud connected" : "Cloud not connected",
            chatStore.ironclawRemoteWorkstationAvailable ? "Agent connected" : "Agent phone ready"
        ].joined(separator: " · ")
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
        guard let snapshot = chatStore.attestationSnapshot else { return "Ready" }
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
            return "Current route: \(chatStore.selectedProviderDisplayName). Fetch proof from Security when you need a signed private-route report."
        }

        let coveredCount = max(snapshot.modelAttestationCount, snapshot.coveredModelIDs.count)
        let freshness = AttestationFreshness.classify(attestedAt: snapshot.fetchedAt).shortLabel
        let countLabel = "\(coveredCount) model\(coveredCount == 1 ? "" : "s")"
        return "Last report: \(countLabel) covered · \(freshness) · current route \(chatStore.selectedProviderDisplayName)."
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
                ? "Current route uses \(chatStore.selectedModelDisplayName) through NEAR Cloud. \(plan)."
                : "Cloud unlocks premium external model rows in the picker. \(plan)."
        }
        return "Connect NEAR Cloud before sending with locked Cloud routes or mixed Cloud councils."
    }

    private var agentStatus: String {
        if chatStore.ironclawRemoteWorkstationAvailable {
            return "Workstation connected"
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
            return "Hosted tools last verified \(verifiedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))."
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
        return CapabilityCardAction(title: "Open Security", systemImage: "checkmark.shield", role: .primary) {
            dismissThen(onOpenSecurity)
        }
    }

    private var cloudPrimaryAction: CapabilityCardAction? {
        guard let onOpenAccountSettings else { return nil }
        return CapabilityCardAction(
            title: chatStore.nearCloudKeyConfigured ? "Manage Cloud" : "Connect Cloud",
            systemImage: chatStore.nearCloudKeyConfigured ? "slider.horizontal.3" : "key",
            role: .primary
        ) {
            dismissThen(onOpenAccountSettings)
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
            dismissThen(onOpenAccountSettings)
        }
    }

    private var agentSecondaryAction: CapabilityCardAction? {
        guard chatStore.ironclawRemoteWorkstationAvailable, let onOpenAccountSettings else { return nil }
        return CapabilityCardAction(title: "Manage Endpoint", systemImage: "slider.horizontal.3", role: .secondary) {
            dismissThen(onOpenAccountSettings)
        }
    }

    private var councilPrimaryAction: CapabilityCardAction? {
        guard chatStore.councilModelIDs.count < 2, chatStore.defaultCouncilModels.count >= 2 else { return nil }
        return CapabilityCardAction(title: "Use Auto-Council", systemImage: "square.grid.2x2", role: .primary) {
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
                dismissThen(onOpenAccountSettings)
            }
        case .openAgent:
            return CapabilityCardAction(title: nextStep.actionTitle, systemImage: "point.3.connected.trianglepath.dotted", role: .primary) {
                guard let onOpenAccountSettings else { return }
                dismissThen(onOpenAccountSettings)
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
                readinessPill(title: "Endpoint", value: endpointConnected ? "Hosted" : "Missing", symbolName: "server.rack", active: endpointConnected)
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
        return "Verify"
    }

    private var statusLine: String {
        if isChecking {
            return "Checking shell and git"
        }
        if lastVerifiedAt != nil {
            return toolNames.isEmpty ? "Shell and git verified" : "Shell, git, files, and agent tools verified"
        }
        if !toolNames.isEmpty {
            return "Tool catalog available; run Tools for shell/git preflight"
        }
        if endpointConnected {
            return "Endpoint ready; verify tools"
        }
        return "Add a hosted HTTPS endpoint"
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isConnected ? "cloud.fill" : "cloud")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isConnected ? Color.brandBlue : Color.textSecondary)
                    .frame(width: 34, height: 34)
                    .background((isConnected ? Color.brandBlue : Color.secondary).opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("NEAR AI Cloud")
                        .font(.subheadline.weight(.bold))
                    Text(isConnected ? "\(max(modelCount, 1)) Cloud models ready." : "Link your NEAR account when supported, or paste a Cloud key and test it before it is saved.")
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

            if !isConnected {
                Button(action: onConnectAccount) {
                    Label(isAutoConnecting ? "Connecting Account" : "Connect with NEAR account", systemImage: isAutoConnecting ? "arrow.triangle.2.circlepath" : "person.crop.circle.badge.checkmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAutoConnecting || isConnecting)
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("Fallback setup", systemImage: "list.number")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                Text("If one-tap linking is not available yet: open NEAR AI Cloud, sign up or sign in, create an API key, then paste and test it here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 8) {
                Button(action: onOpenCloud) {
                    Label("Open Cloud", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.bordered)

                Button(action: onPasteKey) {
                    Label("Paste Key", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 0)
            }
            .font(.caption.weight(.semibold))

            HStack(spacing: 8) {
                Button(action: onConnect) {
                    Label(isConnecting ? "Testing" : "Connect & Test", systemImage: isConnecting ? "arrow.triangle.2.circlepath" : "checkmark.seal")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAutoConnecting || isConnecting || trimmedKey.isEmpty)

                if isConnected {
                    Button(role: .destructive, action: onRemove) {
                        Label("Disconnect", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isAutoConnecting || isConnecting)
                }
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.vertical, 4)
    }
}

private struct PowerToolsUnlockCard: View {
    let onShowAll: () -> Void
    let onCloudKey: () -> Void
    let onIronclaw: () -> Void
    let onAdvanced: () -> Void
    let onDiagnostics: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.actionPrimary)
                    .frame(width: 38, height: 38)
                    .background(Color.actionPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Add Capabilities")
                        .font(.headline)
                    Text("Keep the app simple by default, then connect Cloud, hosted IronClaw, diagnostics, or advanced model controls only when you need them.")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button(action: onShowAll) {
                Label("Show Capabilities", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.actionPrimary)

            VStack(spacing: 8) {
                PowerToolQuickAction(title: "Connect NEAR Cloud", symbolName: "key", action: onCloudKey)
                PowerToolQuickAction(title: "Connect IronClaw bridge", symbolName: "terminal", action: onIronclaw)
                PowerToolQuickAction(title: "Advanced model params", symbolName: "brain.head.profile", action: onAdvanced)
                PowerToolQuickAction(title: "Run diagnostics", symbolName: "stethoscope", action: onDiagnostics)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct PowerToolQuickAction: View {
    let title: String
    let symbolName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbolName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textSecondary.opacity(0.75))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
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
