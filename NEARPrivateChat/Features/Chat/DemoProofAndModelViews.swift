import SwiftUI

#if DEBUG
struct DemoVerifiedProofCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.trustVerified)
                .frame(width: 36, height: 36)
                .background(Color.trustVerified.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("Proof checked")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.trustVerified)
                Text("Fresh proof for the selected private model on the NEAR Private route. Tap the shield to inspect nonce, model hash, gateway, and signature.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.trustVerified.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.trustVerified.opacity(0.24), lineWidth: 1)
        }
    }
}

struct DemoNearCloudModelsView: View {
    @EnvironmentObject private var chatStore: ChatStore

    private var cloudModels: [ModelOption] {
        chatStore.nearCloudModels.filter { !$0.isDeprecatedPickerModel }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(cloudModels.prefix(8))) { model in
                            DemoCloudModelRow(model: model)
                                .id(model.id)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Route behavior")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Label("Uses the same project files, saved links, and web context when the prompt needs them.", systemImage: "folder.badge.gearshape")
                        Label("Cloud models run through the NEAR AI Cloud privacy proxy, separate from the fully private route.", systemImage: "lock.rotation")
                        Label("The private route stays the default when proof matters; Cloud is an explicit override.", systemImage: "checkmark.shield")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .id("route-behavior")
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
            }
            .background(Color.appBackground)
            .navigationTitle("NEAR AI Cloud")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {}
                }
                ToolbarItem(placement: .primaryAction) {
                    Label("Connected", systemImage: "key.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.trustVerified)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "cloud.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.actionPrimary)
                    .frame(width: 34, height: 34)
                    .background(Color.actionPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current NEAR AI Cloud catalog")
                        .font(.headline.weight(.semibold))
                    Text("Cloud key connected · privacy proxy route")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.trustVerified)
                }
            }
            Text("The app defaults to the private route with proof, and advanced users can deliberately switch to Cloud models without losing project context.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct DemoSingleModelPickerView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        Text("Search models")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(height: 38)
                }

                Section("Selected model") {
                    DemoSingleModelRow(
                        title: "GLM 5.1",
                        subtitle: "Default private model",
                        detail: "NEAR Private route · proof when fresh",
                        symbolName: "checkmark.shield.fill",
                        tint: .trustVerified,
                        isSelected: true
                    )
                }

                Section("Switching modes") {
                    HStack(spacing: 10) {
                        Image(systemName: "square.grid.2x2")
                            .foregroundStyle(Color.actionPrimary)
                            .frame(width: 30, height: 30)
                            .background(Color.actionPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Council is a separate tab")
                                .font(.subheadline.weight(.semibold))
                            Text("Tap Council when you want the private model and independent cloud models to answer together.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Model")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {}
                }
            }
        }
    }
}

private struct DemoSingleModelRow: View {
    let title: String
    let subtitle: String
    let detail: String
    let symbolName: String
    let tint: Color
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                Text(subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.trustVerified)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct DemoCloudModelRow: View {
    let model: ModelOption

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: iconName)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.actionPrimary)
                .frame(width: 30, height: 30)
                .background(Color.actionPrimary.opacity(0.09), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(model.displayName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    Text(costLabel)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(Color.appSecondaryBackground, in: Capsule())
                }
                Text(model.metadata?.modelDescription ?? "Runs through NEAR AI Cloud with privacy proxy routing.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    ForEach(Array(model.capabilityBadges.prefix(3)), id: \.self) { badge in
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(badge == "Not attested" ? Color.orange : Color.secondary)
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background(Color.appSecondaryBackground, in: Capsule())
                    }
                }
            }
        }
        .padding(12)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }

    private var iconName: String {
        let id = model.id.lowercased()
        if id.contains("claude") { return "sparkles" }
        if id.contains("gpt") { return "brain.head.profile" }
        if id.contains("gemini") { return "diamond" }
        if id.contains("kimi") { return "moon.stars" }
        if id.contains("qwen") { return "cpu" }
        return "cloud"
    }

    private var costLabel: String {
        model.id.localizedCaseInsensitiveContains("gpt-oss") ? "Open" : "Cloud"
    }
}

#endif
