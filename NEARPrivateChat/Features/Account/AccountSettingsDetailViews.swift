import SwiftUI

// MARK: - Account section detail pushes

struct SignInMethodDetailView: View {
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

struct PlanDetailView: View {
    @EnvironmentObject private var accountStore: AccountStore

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Plan").foregroundStyle(.primary)
                    Spacer()
                    Text(accountStore.billingSnapshot?.activeSubscription?.plan.capitalized ?? accountStore.currentBillingPlanName.capitalized)
                        .foregroundStyle(Color.textSecondary)
                }
                if let currentPeriodEnd = accountStore.billingSnapshot?.activeSubscription?.currentPeriodEnd {
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

struct DynamicTypeDetailView: View {
    var body: some View {
        List {
            Section {
                HStack {
                    Text("Source").foregroundStyle(.primary)
                    Spacer()
                    Text("iOS Settings").foregroundStyle(Color.textSecondary)
                }
            } footer: {
                Text("Respects the Dynamic Type size set in iOS Settings → Display & Brightness → Text Size.")
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Dynamic Type")
        .platformInlineNavigationTitle()
    }
}

// MARK: - Model defaults detail pushes

struct DefaultModelDetailView: View {
    @EnvironmentObject private var modelCatalogStore: ModelCatalogStore
    let onSelectDefaultModel: (String?) -> Void

    private var candidates: [ModelOption] {
        modelCatalogStore.preferredDefaultModelCandidates
    }

    private var currentSelection: String {
        modelCatalogStore.effectiveDefaultModelID
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
                            let next: String? = option.id == ModelCatalogStore.defaultModelID ? nil : option.id
                            onSelectDefaultModel(next)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(option.displayName)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.82)
                                    if let badge = routeBadge(for: option) {
                                        Label(badge.title, systemImage: badge.symbolName)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(badge.tint)
                                            .lineLimit(1)
                                            .padding(.horizontal, 8)
                                            .frame(height: 24)
                                            .background(badge.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
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

    private func routeBadge(for option: ModelOption) -> ModelRouteBadge? {
        if option.id == ModelCatalogStore.defaultModelID {
            return ModelRouteBadge(title: "Default private", symbolName: "checkmark.shield", tint: Color.actionPrimary)
        }
        if option.isNearCloudModel {
            return ModelRouteBadge(title: "Cloud route", symbolName: "cloud", tint: Color.textSecondary)
        }
        if option.isVerifiable {
            return ModelRouteBadge(title: "Private proof", symbolName: "checkmark.shield", tint: Color.proofVerified)
        }
        return ModelRouteBadge(title: "External route", symbolName: "network", tint: Color.textSecondary)
    }
}

private struct ModelRouteBadge {
    let title: String
    let symbolName: String
    let tint: Color
}

struct ReasoningEffortDetailView: View {
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

struct PowerToolIronclawView: View {
    @EnvironmentObject private var agentStore: AgentStore
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
                    Text(agentStore.ironclawStatusText).foregroundStyle(Color.textSecondary)
                }
                Toggle("Enable Hosted IronClaw", isOn: $ironclawEnabled)
            }

            Section("Readiness") {
                IronclawBridgeReadinessCard(
                    endpointConnected: agentStore.ironclawRemoteWorkstationAvailable,
                    tokenConfigured: agentStore.ironclawTokenConfigured,
                    lastVerifiedAt: agentStore.ironclawLastVerifiedAt,
                    isChecking: agentStore.isTestingIronclawWorkstation,
                    toolNames: agentStore.ironclawToolNames
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section("Agent connection") {
                TextField("Hosted IronClaw URL", text: $ironclawEndpoint)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                SecureField(agentStore.ironclawTokenConfigured ? "Token saved" : "Bearer token", text: $ironclawToken)
                TextField("Optional thread ID", text: $ironclawThreadID)
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
                    Task { await agentStore.testIronclawConnection() }
                } label: {
                    Label(agentStore.isTestingIntegration ? "Testing" : "Test Connection", systemImage: "checkmark.circle")
                }
                .disabled(agentStore.isTestingIntegration)

                Button {
                    Task { await agentStore.testIronclawWorkstation() }
                } label: {
                    Label(agentStore.isTestingIronclawWorkstation ? "Checking" : "Check Hosted Tools", systemImage: "terminal")
                }
                .disabled(agentStore.isTestingIronclawWorkstation)
            }

            if agentStore.ironclawSettings.hasEndpoint || agentStore.ironclawTokenConfigured {
                Section {
                    Button(role: .destructive) {
                        agentStore.disconnectIronclaw()
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

struct PowerToolAPIKeysView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var modelCatalogStore: ModelCatalogStore
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
                    isConnected: accountStore.nearCloudKeyConfigured,
                    isConnecting: accountStore.isTestingNearCloudKey,
                    isAutoConnecting: accountStore.isConnectingNearCloudAccount,
                    modelCount: modelCatalogStore.cloudModels.count,
                    onConnectAccount: onConnectAccount,
                    onOpenCloud: onOpenCloud,
                    onPasteKey: onPaste,
                    onConnect: onConnect,
                    onRemove: {
                        accountStore.clearNearCloudAPIKey()
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

struct PowerToolDiagnosticsView: View {
    @EnvironmentObject private var accountStore: AccountStore

    var body: some View {
        Form {
            Section("Results") {
                if accountStore.diagnosticChecks.isEmpty {
                    HStack {
                        Text("Diagnostics").foregroundStyle(.primary)
                        Spacer()
                        Text("Not run").foregroundStyle(Color.textSecondary)
                    }
                } else {
                    ForEach(accountStore.diagnosticChecks) { check in
                        DiagnosticCheckRow(check: check)
                    }
                }
            }

            Section {
                Button {
                    Task { await accountStore.runDiagnostics() }
                } label: {
                    Label(accountStore.isRunningDiagnostics ? "Running Diagnostics" : "Run Diagnostics", systemImage: "stethoscope")
                }
                .disabled(accountStore.isRunningDiagnostics)
            }
        }
        .navigationTitle("Diagnostics")
        .platformInlineNavigationTitle()
    }
}

struct PowerToolEndpointsView: View {
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
