import SwiftUI

// MARK: - IronclawLLMProvidersView

struct IronclawLLMProvidersView: View {
    let settings: IronclawSettings
    let authToken: String

    @State private var providers: [IronclawLLMProvider] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showAddProvider = false

    private let api = IronclawAPI()

    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if providers.isEmpty {
                emptyState
            } else {
                providerRows
            }

            disclaimerSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("LLM Providers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddProvider = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddProvider) {
            AddLLMProviderView(settings: settings, authToken: authToken) {
                Task { await loadProviders() }
            }
        }
        .task { await loadProviders() }
        .refreshable { await loadProviders() }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var emptyState: some View {
        if let errorMessage {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .listRowBackground(Color.clear)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "cpu.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("No LLM providers configured on this agent.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var providerRows: some View {
        Section {
            ForEach(providers) { provider in
                NavigationLink {
                    LLMProviderDetailView(provider: provider)
                } label: {
                    LLMProviderRow(provider: provider)
                }
            }
        }
    }

    @ViewBuilder
    private var disclaimerSection: some View {
        Section {
            Text("API keys entered here are sent directly to your hosted IronClaw server and are never stored on this device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Data

    @MainActor
    private func loadProviders() async {
        isLoading = true
        errorMessage = nil
        providers = await api.fetchLLMProviders(settings: settings, authToken: authToken)
        if providers.isEmpty {
            // leave errorMessage nil — empty state handles it
        }
        isLoading = false
    }
}

// MARK: - LLMProviderRow

private struct LLMProviderRow: View {
    let provider: IronclawLLMProvider

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: provider.icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(provider.displayName)
                        .font(.body)
                    if provider.isActive == true {
                        Text("Active")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(.tint)
                            .clipShape(Capsule())
                    }
                }
                if let modelName = provider.modelName, !modelName.isEmpty {
                    Text(modelName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - LLMProviderDetailView

struct LLMProviderDetailView: View {
    let provider: IronclawLLMProvider

    var body: some View {
        List {
            Section("Identity") {
                LabeledContent("Name", value: provider.displayName)
                if let type_ = provider.providerType, !type_.isEmpty {
                    LabeledContent("Type", value: type_)
                }
            }

            Section("Configuration") {
                if let baseURL = provider.baseURL, !baseURL.isEmpty {
                    LabeledContent("Base URL") {
                        Text(baseURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }
                if let modelName = provider.modelName, !modelName.isEmpty {
                    LabeledContent("Model", value: modelName)
                }
            }

            Section("Status") {
                LabeledContent("Active") {
                    Text(provider.isActive == true ? "Yes" : "No")
                        .foregroundStyle(provider.isActive == true ? .green : .secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(provider.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - AddLLMProviderView

struct AddLLMProviderView: View {
    let settings: IronclawSettings
    let authToken: String
    let onSuccess: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var providerType = ""
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var modelName = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Provider") {
                    TextField("Name", text: $name)
                        .autocorrectionDisabled()
                    TextField("Type (e.g. openai, anthropic)", text: $providerType)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                }

                Section("Endpoint") {
                    TextField("Base URL (optional)", text: $baseURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    SecureField("API Key", text: $apiKey)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }

                Section("Model") {
                    TextField("Model name (optional)", text: $modelName)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                }

                Section {
                    Text("The API key is sent directly to your hosted IronClaw server when you tap Add. It is not stored on this device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add Provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task { await save() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    // MARK: - Save

    @MainActor
    private func save() async {
        isSaving = true
        errorMessage = nil

        var payload: [String: String] = [
            "name": name.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        let trimmedType = providerType.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedType.isEmpty { payload["provider_type"] = trimmedType }
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedURL.isEmpty { payload["base_url"] = trimmedURL }
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty { payload["api_key"] = trimmedKey }
        let trimmedModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModel.isEmpty { payload["model_name"] = trimmedModel }

        guard let url = URL(string: settings.baseURL + "/api/webchat/v2/llm/providers"),
              let body = try? JSONEncoder().encode(payload) else {
            errorMessage = "Invalid server URL."
            isSaving = false
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = body
        req.timeoutInterval = 20

        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                errorMessage = "Server returned \(http.statusCode). Check the provider details and retry."
                isSaving = false
                return
            }
            onSuccess()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
