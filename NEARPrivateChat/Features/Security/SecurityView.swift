import SwiftUI

struct SecurityView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var localVerificationMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    attestationSummary
                }

                Section("Current Session") {
                    SecurityStateRow(title: "Route", value: routeSummary, symbolName: routeSymbolName)
                    SecurityStateRow(title: "Endpoint", value: endpointSummary, symbolName: "network")
                    SecurityStateRow(title: "Request signing", value: signingSummary, symbolName: "signature")
                    SecurityStateRow(title: "Selected model", value: chatStore.selectedModelDisplayName, symbolName: "cpu")
                }

                Section("Proof Actions") {
                    proofActionsContent
                }

                Section("Proof Facts") {
                    proofFactsContent
                }

                Section("What This Means") {
                    ForEach(AttestationEducation.standard.sections) { section in
                        AttestationEducationRow(section: section)
                    }
                }

                Section("Report") {
                    if let error = chatStore.attestationFetchErrorMessage {
                        InfoRow(title: "Last fetch", value: error)
                    }
                    if let snapshot = chatStore.attestationSnapshot {
                        InfoRow(
                            title: "Fetched",
                            value: snapshot.fetchedAt.formatted(date: .abbreviated, time: .standard)
                        )
                        InfoRow(title: "Nonce", value: snapshot.nonce, monospaced: true)
                        InfoRow(title: "Model", value: proofModelPhrase(snapshot), monospaced: snapshot.model != nil)
                        InfoRow(title: "Coverage", value: attestationCoveragePhrase(snapshot))
                        if let address = snapshot.chatGatewayAddress {
                            InfoRow(title: "Chat gateway", value: address, monospaced: true)
                        }
                        if let address = snapshot.cloudGatewayAddress {
                            InfoRow(title: "Cloud gateway", value: address, monospaced: true)
                        }

                        DisclosureGroup {
                            ScrollView(.horizontal, showsIndicators: true) {
                                Text(snapshot.prettyJSON)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 220)
                        } label: {
                            Label("Raw JSON", systemImage: "curlybraces")
                        }
                        .padding(.vertical, 4)

                        Button {
                            Clipboard.copy(snapshot.prettyJSON)
                            chatStore.bannerMessage = "Attestation copied."
                        } label: {
                            Label("Copy Report", systemImage: "doc.on.doc")
                        }
                    } else if chatStore.isLoadingAttestation {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Fetching attestation")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No report fetched yet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    if canFetchAttestation {
                        Button {
                            Task { await chatStore.refreshAttestationReport() }
                        } label: {
                            Label(
                                chatStore.attestationSnapshot == nil ? "Fetch Attestation" : "Refresh Attestation",
                                systemImage: "arrow.clockwise"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.brandBlue)
                        .disabled(chatStore.isLoadingAttestation)
                    } else {
                        Label(fetchAttestationDisabledText, systemImage: "shield.slash")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Security")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                if canFetchAttestation, chatStore.attestationSnapshot == nil, !chatStore.isLoadingAttestation {
                    await chatStore.refreshAttestationReport()
                }
            }
        }
    }

    @ViewBuilder
    private var proofActionsContent: some View {
        if let snapshot = chatStore.attestationSnapshot {
            Button {
                verifyProofOnDevice(snapshot)
            } label: {
                Label("Verify on-device", systemImage: "checkmark.shield")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityHint("Checks the cached signed report on this device. It does not verify answer truth.")

            ShareLink(
                item: snapshot.prettyJSON,
                subject: Text("NEAR Private Chat attestation JSON"),
                message: Text("Attestation JSON only. It does not include conversation text.")
            ) {
                Label("Share Proof JSON", systemImage: "square.and.arrow.up")
            }
            .accessibilityHint("Shares only the attestation JSON report.")

            if let localVerificationMessage {
                Text(localVerificationMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Label(proofActionsUnavailableText, systemImage: "shield.slash")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {} label: {
                Label("Verify on-device", systemImage: "checkmark.shield")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(true)
            .accessibilityHint("Fetch attestation first to check the signed report on this device.")

            Button {} label: {
                Label("Share Proof JSON", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(true)
            .accessibilityHint("Fetch attestation first to share proof JSON.")
        }
    }

    @ViewBuilder
    private var proofFactsContent: some View {
        if let snapshot = chatStore.attestationSnapshot {
            ProofFactRow(
                title: "Model",
                value: proofModelPhrase(snapshot),
                detail: proofModelDetail(snapshot),
                symbolName: "cpu"
            )
            ProofFactRow(
                title: "Runtime",
                value: proofRuntimePhrase(snapshot),
                detail: endpointSummary,
                symbolName: "server.rack"
            )
            ProofFactRow(
                title: "Runtime",
                value: proofRuntimeEvidencePhrase(snapshot),
                detail: "Proof covers route/model evidence when present. It does not prove answer truthfulness.",
                symbolName: "lock.shield"
            )
            ProofFactRow(
                title: "Freshness",
                value: chatStore.currentAttestationStatus.freshness()?.shortLabel ?? "unknown",
                detail: snapshot.fetchedAt.formatted(date: .abbreviated, time: .standard),
                symbolName: "clock"
            )
        } else {
            ProofFactRow(
                title: "Proof data",
                value: "No attestation JSON on device",
                detail: proofActionsUnavailableText,
                symbolName: "shield.slash"
            )
        }
    }

    private func verifyProofOnDevice(_ snapshot: AttestationSnapshot) {
        let status = chatStore.currentAttestationStatus
        let copy = status.userFacingCopy()
        let nonceText = snapshot.nonce.isEmpty ? "Nonce is missing." : "Nonce is present."
        let message = "On-device check: \(copy.title). \(nonceText) This verifies signed TEE evidence cached on this device, not answer truth."
        localVerificationMessage = message
        chatStore.bannerMessage = message
    }

    private var attestationSummary: some View {
        if chatStore.selectedRouteUsesNearCloud || (chatStore.isCouncilModeEnabled && chatStore.activeCouncilHasNearCloudRoutes) {
            return AnyView(cloudTrustSummary)
        }

        let proof = ProofCapsuleViewModel(
            status: chatStore.currentAttestationStatus,
            isLoading: chatStore.isLoadingAttestation,
            modelID: chatStore.selectedModel
        )
        return AnyView(VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: proof.symbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(proof.tintColor)
                    .frame(width: 44, height: 44)
                    .background(proof.tintColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(proof.title)
                        .font(.headline)
                        .lineLimit(2)
                        .minimumScaleFactor(0.86)
                    Text(proof.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ProofCapsule(viewModel: proof)
                Text(AttestationEducation.standard.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(chatStore.currentAttestationStatus.accessibilityLabel())
        .accessibilityHint(chatStore.currentAttestationStatus.accessibilityHint()))
    }

    private var cloudTrustSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "eye.slash")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 44, height: 44)
                    .background(Color.brandBlue.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("Privacy proxy route")
                        .font(.headline)
                    Text("NEAR Cloud can use app-supplied web and project context, but this route does not carry NEAR Private verification.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            StatusChip(title: "Privacy proxy · unverified", symbolName: "cloud", isPrimary: true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("NEAR Cloud privacy proxy route, unverified")
    }

    private var canFetchAttestation: Bool {
        if chatStore.isCouncilModeEnabled {
            return !chatStore.activeCouncilHasExternalRoutes && chatStore.selectedRouteKind == .nearPrivate
        }
        return chatStore.selectedRouteKind == .nearPrivate
    }

    private var proofActionsUnavailableText: String {
        if chatStore.isLoadingAttestation {
            return "Fetching attestation JSON. Proof actions will unlock when a report is on this device."
        }
        if canFetchAttestation {
            return "Fetch attestation to enable on-device verification and proof JSON sharing."
        }
        return fetchAttestationDisabledText
    }

    private var fetchAttestationDisabledText: String {
        if chatStore.isCouncilModeEnabled, chatStore.activeCouncilHasExternalRoutes {
            return "Verification proof is available for all-private Council lineups. Remove NEAR Cloud models to fetch proof."
        }
        return "Switch to a NEAR Private model to fetch verification proof."
    }

    private func attestationCoveragePhrase(_ snapshot: AttestationSnapshot) -> String {
        if !snapshot.coveredModelIDs.isEmpty {
            if snapshot.coveredModelIDs.count == 1, let model = snapshot.coveredModelIDs.first {
                return "\(model) covered by proof"
            }
            return "\(snapshot.coveredModelIDs.count) models covered by proof"
        }
        if let model = snapshot.model, snapshot.modelAttestationCount <= 1 {
            return "\(model) covered by proof"
        }
        if snapshot.modelAttestationCount > 0 {
            return "\(snapshot.modelAttestationCount) model proof entries"
        }
        return "No model coverage in this report"
    }

    private func proofModelPhrase(_ snapshot: AttestationSnapshot) -> String {
        if !snapshot.coveredModelIDs.isEmpty {
            if snapshot.coveredModelIDs.count == 1, let model = snapshot.coveredModelIDs.first {
                return model
            }
            if snapshot.coveredModelIDs.contains(where: { AttestationEvidence.normalizedModelID($0) == AttestationEvidence.normalizedModelID(chatStore.selectedModel) }) {
                return "\(chatStore.selectedModel) + \(snapshot.coveredModelIDs.count - 1) more"
            }
            return "\(snapshot.coveredModelIDs.count) covered models"
        }
        if let model = snapshot.model {
            return model
        }
        if snapshot.modelAttestationCount > 0 {
            return "\(snapshot.modelAttestationCount) model attestations, IDs unavailable"
        }
        return "Coverage metadata not in report"
    }

    private func proofModelDetail(_ snapshot: AttestationSnapshot) -> String? {
        if !snapshot.coveredModelIDs.isEmpty || snapshot.model != nil {
            return chatStore.currentAttestationStatus.coverage(for: chatStore.selectedModel) == .covered ? "Covered by the current proof." : "Current selected model may need a refreshed proof."
        }
        return "The private model can still run; this report just cannot prove model coverage."
    }

    private func proofRuntimePhrase(_ snapshot: AttestationSnapshot) -> String {
        if snapshot.chatGatewayAddress != nil {
            return "NEAR Private chat gateway"
        }
        if snapshot.cloudGatewayAddress != nil {
            return "NEAR Cloud gateway"
        }
        return routeSummary
    }

    private func proofRuntimeEvidencePhrase(_ snapshot: AttestationSnapshot) -> String {
        if snapshot.modelAttestationCount > 0 {
            return "Model runtime evidence present"
        }
        if snapshot.chatGatewayAddress != nil || snapshot.cloudGatewayAddress != nil {
            return "Gateway evidence present"
        }
        return "Runtime facts not present"
    }

    private var routeSummary: String {
        if chatStore.isCouncilModeEnabled {
            return "LLM Council"
        }
        switch chatStore.selectedRouteKind {
        case .nearPrivate:
            return "NEAR Private"
        case .nearCloud:
            return "NEAR Cloud"
        case .ironclawMobile:
            return "IronClaw Mobile"
        case .ironclawHosted:
            return "IronClaw Hosted"
        }
    }

    private var routeSymbolName: String {
        switch chatStore.selectedRouteKind {
        case .nearPrivate:
            return "lock.shield"
        case .nearCloud:
            return "cloud"
        case .ironclawMobile:
            return "iphone"
        case .ironclawHosted:
            return "terminal"
        }
    }

    private var endpointSummary: String {
        switch chatStore.selectedRouteKind {
        case .nearPrivate:
            return "private.near.ai"
        case .nearCloud:
            return "cloud-api.near.ai"
        case .ironclawMobile:
            return chatStore.ironclawRemoteWorkstationAvailable ? "Phone + workstation" : "Phone runtime"
        case .ironclawHosted:
            return chatStore.ironclawSettings.hasUsableHostedEndpoint ? "Configured gateway" : "Not configured"
        }
    }

    private var signingSummary: String {
        chatStore.attestationSnapshot?.signingAlgorithm.uppercased() ?? "ECDSA"
    }
}

private struct AttestationEducationRow: View {
    let section: AttestationEducationSection

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(section.title)
                .font(.subheadline.weight(.semibold))
            Text(section.body)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    var monospaced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(monospaced ? .caption.monospaced() : .subheadline)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}

private struct ProofFactRow: View {
    let title: String
    let value: String
    let detail: String?
    let symbolName: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.84)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
        .accessibilityHint(detail ?? "")
    }
}

struct DiagnosticCheckRow: View {
    let check: AppDiagnosticCheck

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: check.state.symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(stateColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(check.title)
                    .font(.subheadline.weight(.semibold))
                Text(check.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 3)
    }

    private var stateColor: Color {
        switch check.state {
        case .running: Color.textSecondary
        case .passed: Color.proofVerified
        case .warning: Color.proofStale
        case .failed: Color.proofMismatch
        }
    }
}

private struct SecurityStateRow: View {
    let title: String
    let value: String
    let symbolName: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "circle.fill")
                .font(.caption2)
                .foregroundStyle(Color.textSecondary.opacity(0.38))
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}
