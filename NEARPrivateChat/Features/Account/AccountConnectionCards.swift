import SwiftUI

struct IronclawBridgeReadinessCard: View {
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
                    .foregroundStyle(Color.brandAccent)
                    .frame(width: 28, height: 28)
                    .background(Color.brandAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            return toolNames.isEmpty ? "Shell and git checked" : "Shell, git, files, and Agent tools checked"
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
                .foregroundStyle(active ? Color.brandAccent : .secondary)
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
        .background(active ? Color.brandAccent.opacity(0.07) : Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct NearCloudConnectionCard: View {
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
                    .foregroundStyle(isConnected ? Color.brandAccent : Color.textSecondary)
                    .frame(width: 34, height: 34)
                    .background((isConnected ? Color.brandAccent : Color.secondary).opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

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

struct AdvancedParamField: View {
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
