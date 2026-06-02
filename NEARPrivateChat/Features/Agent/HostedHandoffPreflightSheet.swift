import SwiftUI

struct HostedHandoffPreflightSheet: View {
    @Environment(\.dismiss) private var dismiss
    let preflight: HostedIronclawHandoffPreflight
    let onConfirm: (HostedIronclawHandoffPreflight) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "arrow.up.right.square.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.brandBlue)
                            .frame(width: 40, height: 40)
                            .background(Color.brandBlue.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Run on Hosted IronClaw?")
                                .font(.title3.weight(.semibold))
                            Text("Sends the prompt and selected phone context to \(preflight.destinationHost).")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("What leaves the phone")
                            .font(.subheadline.weight(.semibold))
                        ForEach(preflight.disclosedItems, id: \.self) { item in
                            Label(item, systemImage: "checkmark.shield")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    if !preflight.promptPreview.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Prompt preview")
                                .font(.subheadline.weight(.semibold))
                            Text(preflight.promptPreview)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(8)
                                .textSelection(.enabled)
                        }
                    }

                    VStack(spacing: 10) {
                        Button {
                            onConfirm(preflight)
                            dismiss()
                        } label: {
                            Label("Run on Hosted IronClaw", systemImage: "terminal")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button(role: .cancel) {
                            onCancel()
                            dismiss()
                        } label: {
                            Text("Stay in this chat")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .padding(20)
            }
            .background(HomeSurfaceBackground().ignoresSafeArea())
            .navigationTitle("Confirm Handoff")
            .platformInlineNavigationTitle()
        }
    }
}

struct IronclawApprovalCard: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.openURL) private var openURL
    @State private var credentialToken = ""
    @State private var pendingGateURL: URL?
    @State private var confirmingAlways = false
    let messageID: String
    let approval: IronclawPendingGate

    var body: some View {
        if approval.isAuthenticationGate {
            authenticationBody
        } else {
            approvalBody
        }
    }

    private var approvalBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "hand.raised.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 28, height: 28)
                    .background(Color.brandBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Approval required")
                        .font(.subheadline.weight(.semibold))
                    Text(approval.toolName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            Text(approval.description)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let parameterPreview = approval.parameterPreview {
                Text(parameterPreview)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            HStack(spacing: 8) {
                Button {
                    chatStore.resolveIronclawApproval(messageID: messageID, approval: approval, action: .approve)
                } label: {
                    Label("Allow once", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)

                if approval.locallyAllowsAlways {
                    Button {
                        confirmingAlways = true
                    } label: {
                        Label("Always", systemImage: "checkmark.seal")
                    }
                    .buttonStyle(.bordered)
                } else if let reason = approval.alwaysUnavailableReason {
                    Label(reason, systemImage: "lock.shield")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(role: .destructive) {
                    chatStore.resolveIronclawApproval(messageID: messageID, approval: approval, action: .deny)
                } label: {
                    Label("Deny", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(12)
        .frame(maxWidth: 520, alignment: .leading)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
        .confirmationDialog(
            "Always approve this tool?",
            isPresented: $confirmingAlways,
            titleVisibility: .visible
        ) {
            Button("Always approve \(approval.toolName)") {
                chatStore.resolveIronclawApproval(messageID: messageID, approval: approval, action: .always)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Applies only to the Hosted IronClaw scope from the Agent connection. Command, file, network, and credential tools still need per-run approval on phone.")
        }
        .confirmationDialog(
            "Open external site?",
            isPresented: Binding(
                get: { pendingGateURL != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingGateURL = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: pendingGateURL
        ) { url in
            Button("Open \(url.host ?? "site")") {
                openURL(url)
                pendingGateURL = nil
            }
            Button("Cancel", role: .cancel) {
                pendingGateURL = nil
            }
        } message: { url in
            Text("IronClaw returned this HTTPS URL. Continue only if you recognize the host: \(url.host ?? "unknown").")
        }
    }

    private var authenticationBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "key.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 28, height: 28)
                    .background(Color.brandBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tool sign-in required")
                        .font(.subheadline.weight(.semibold))
                    Text("\(approval.authenticationDisplayName) - \(approval.toolName)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            Text(approval.authenticationHelpText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Label("Hosted IronClaw", systemImage: "terminal")
                Label("Credential gated", systemImage: "lock.shield")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.brandBlue)

            if let parameterPreview = approval.parameterPreview {
                Text(parameterPreview)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if let authURL = approval.authURLValue {
                Button {
                    openGateURL(authURL)
                } label: {
                    Label("Open sign-in\(approval.authURLHost.map { " - \($0)" } ?? "")", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.borderedProminent)
                .font(.caption.weight(.semibold))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    SecureField("\(approval.authenticationDisplayName) token", text: $credentialToken)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                        .tokenInputTraits()
                        .onSubmit(submitCredential)

                    HStack(spacing: 8) {
                        Button(action: submitCredential) {
                            Label("Save credential", systemImage: "key")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(trimmedCredentialToken.isEmpty)

                        Button(role: .destructive) {
                            chatStore.resolveIronclawApproval(messageID: messageID, approval: approval, action: .deny)
                        } label: {
                            Label("Cancel", systemImage: "xmark")
                        }
                        .buttonStyle(.bordered)
                    }
                    .font(.caption.weight(.semibold))
                }
            }

            if let setupURL = approval.setupURLValue {
                Button {
                    openGateURL(setupURL)
                } label: {
                    Label("Setup guide\(approval.setupURLHost.map { " - \($0)" } ?? "")", systemImage: "book")
                }
                .buttonStyle(.bordered)
                .font(.caption.weight(.semibold))
            }

            if approval.authURLValue != nil {
                Button(role: .destructive) {
                    chatStore.resolveIronclawApproval(messageID: messageID, approval: approval, action: .deny)
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .font(.caption.weight(.semibold))
            }
        }
        .padding(12)
        .frame(maxWidth: 520, alignment: .leading)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
        .confirmationDialog(
            "Open external site?",
            isPresented: Binding(
                get: { pendingGateURL != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingGateURL = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: pendingGateURL
        ) { url in
            Button("Open \(url.host ?? "site")") {
                openURL(url)
                pendingGateURL = nil
            }
            Button("Cancel", role: .cancel) {
                pendingGateURL = nil
            }
        } message: { url in
            Text("IronClaw returned this HTTPS URL. Continue only if you recognize the host: \(url.host ?? "unknown").")
        }
    }

    private var trimmedCredentialToken: String {
        credentialToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func openGateURL(_ url: URL) {
        guard Self.isFamiliarGateHost(url.host) else {
            pendingGateURL = url
            return
        }
        openURL(url)
    }

    private static func isFamiliarGateHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "github.com" ||
            host == "accounts.google.com" ||
            host == "cloud.near.ai" ||
            host == "near.ai" ||
            host.hasSuffix(".near.ai") ||
            host.hasSuffix(".agents.near.ai")
    }

    private func submitCredential() {
        let token = trimmedCredentialToken
        guard !token.isEmpty else { return }
        chatStore.resolveIronclawCredential(messageID: messageID, approval: approval, token: token)
        credentialToken = ""
    }
}
