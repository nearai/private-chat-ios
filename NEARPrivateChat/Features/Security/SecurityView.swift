import SwiftUI

struct SecurityView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var localVerificationMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    verifiedHero
                    detailListCard
                    actionStack
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(AttestationEducation.standard.sections) { section in
                                AttestationEducationRow(section: section)
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Text("How verification works")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .padding(14)
                    .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.appBorder, lineWidth: 1)
                    }
                    reportCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .background(Color.appBackground)
            .navigationTitle("")
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var currentProofViewModel: ProofCapsuleViewModel {
        if chatStore.selectedRouteUsesNearCloud || (chatStore.isCouncilModeEnabled && chatStore.activeCouncilHasNearCloudRoutes) {
            return ProofCapsuleViewModel(
                state: .proxied,
                title: "Privacy proxy",
                detail: "NEAR Cloud can use app-supplied web and project context, but this route does not carry NEAR Private verification.",
                badge: "Privacy proxy",
                symbolName: "eye.slash"
            )
        }

        return ProofCapsuleViewModel(
            status: chatStore.currentAttestationStatus,
            isLoading: chatStore.isLoadingAttestation,
            modelID: chatStore.selectedModel
        )
    }

    private var verifiedHero: some View {
        let proof = currentProofViewModel
        return VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(proof.tintColor.opacity(0.25), lineWidth: 0.5)
                    .frame(width: 64, height: 64)
                if proof.state == .verifying {
                    ProgressView()
                } else {
                    Image(systemName: proof.symbolName)
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(proof.tintColor)
                }
            }

            VStack(spacing: 14) {
                Text(proof.title)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text(proof.detail)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 320)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    private var detailListCard: some View {
        VStack(spacing: 0) {
            ClaudeDetailRow(label: "Model", trailing: modelTrailing) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(chatStore.selectedModelDisplayName)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                    if let hash = modelHashShort {
                        Text("·")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.textTertiary)
                        Text(hash)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.primary)
                    }
                }
            }
            Divider().background(Color.appHairline).padding(.leading, 16)

            ClaudeDetailRow(label: "Hardware", trailing: hardwareTrailing) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(hardwareSummary)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                    Text(hardwareDetail)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Divider().background(Color.appHairline).padding(.leading, 16)

            ClaudeDetailRow(
                label: "Conversation",
                trailing: AnyView(Image(systemName: "chevron.right").font(.system(size: 14)).foregroundStyle(Color.textTertiary))
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversationSummary)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                    Text(conversationDetail)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textSecondary)
                }
            }

            // Action-tint preview row that mirrors the primary CTA below.
            if let snapshot = chatStore.attestationSnapshot {
                Button {
                    verifyProofOnDevice(snapshot)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Verify on-device")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(Color.actionPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56)
                    .background(Color.actionTint)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var actionStack: some View {
        VStack(spacing: 6) {
            if let snapshot = chatStore.attestationSnapshot {
                Button {
                    verifyProofOnDevice(snapshot)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Verify on-device")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.actionPrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                ShareLink(
                    item: snapshot.prettyJSON,
                    subject: Text("NEAR Private Chat proof JSON"),
                    message: Text("Proof JSON only. It does not include conversation text.")
                ) {
                    HStack(spacing: 6) {
                        Text("Share with proof")
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.actionPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                }

                if let localVerificationMessage {
                    Text(localVerificationMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            } else if canFetchAttestation {
                Button {
                    Task { await chatStore.refreshAttestationReport() }
                } label: {
                    HStack(spacing: 8) {
                        if chatStore.isLoadingAttestation {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        Text(chatStore.isLoadingAttestation ? "Fetching proof" : "Fetch proof")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.actionPrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(chatStore.isLoadingAttestation)
            } else {
                Text(proofActionsUnavailableText)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Button {
                // Toggling the disclosure card below is the simplest route;
                // a real navigation to a "how this works" article would be
                // wired here if/when one exists.
            } label: {
                HStack(spacing: 4) {
                    Text("Learn how this works")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .font(.system(size: 13))
                .foregroundStyle(Color.textTertiary)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .padding(.top, 4)
    }

    private var modelTrailing: AnyView {
        AnyView(Image(systemName: "chevron.right").font(.system(size: 14)).foregroundStyle(Color.textTertiary))
    }

    private var hardwareTrailing: AnyView {
        let isCovered = chatStore.attestationSnapshot != nil &&
            chatStore.currentAttestationStatus.effectiveState() == .valid
        return AnyView(
            Image(systemName: isCovered ? "checkmark.seal.fill" : "shield")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isCovered ? Color.proofVerified : Color.textTertiary)
        )
    }

    private var modelHashShort: String? {
        guard let snapshot = chatStore.attestationSnapshot else { return nil }
        let raw = snapshot.nonce.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.count >= 8 else { return nil }
        let prefix = raw.prefix(4)
        let suffix = raw.suffix(4)
        return "\(prefix)…\(suffix)"
    }

    private var hardwareSummary: String {
        switch chatStore.selectedRouteKind {
        case .nearPrivate:
            return "TEE-supported runtime"
        case .nearCloud:
            return "Privacy proxy"
        case .ironclawMobile:
            return "On-device runtime"
        case .ironclawHosted:
            return "Hosted gateway"
        }
    }

    private var hardwareDetail: String {
        if let snapshot = chatStore.attestationSnapshot,
           let alg = snapshot.signingAlgorithm.isEmpty ? nil : snapshot.signingAlgorithm {
            return "Signed with \(alg.uppercased())"
        }
        return endpointSummary
    }

    private var conversationSummary: String {
        if let snapshot = chatStore.attestationSnapshot {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            return "Sealed at \(formatter.string(from: snapshot.fetchedAt))"
        }
        return "Not sealed yet"
    }

    private var conversationDetail: String {
        chatStore.attestationSnapshot == nil
            ? "Fetch proof to seal this turn"
            : "Checked on this device"
    }

    private var educationCard: some View {
        DisclosureGroup {
            Text(AttestationEducation.standard.summary)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        } label: {
            Text("Why this matters")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(14)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var reportCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Report")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            if let error = chatStore.attestationFetchErrorMessage {
                InfoRow(title: "Last fetch", value: error)
            }

            if let snapshot = chatStore.attestationSnapshot {
                InfoRow(title: "Fetched", value: snapshot.fetchedAt.formatted(date: .abbreviated, time: .standard))
                InfoRow(title: "Nonce", value: snapshot.nonce, monospaced: true)
                InfoRow(title: "Coverage", value: attestationCoveragePhrase(snapshot))

                DisclosureGroup {
                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(snapshot.prettyJSON)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 220)
                    .padding(.top, 6)
                } label: {
                    Label("Raw JSON", systemImage: "curlybraces")
                        .font(.subheadline.weight(.semibold))
                }

                Button {
                    Clipboard.copy(snapshot.prettyJSON)
                    chatStore.bannerMessage = "Proof report copied."
                } label: {
                    Label("Copy report", systemImage: "doc.on.doc")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.actionPrimary)
            } else if chatStore.isLoadingAttestation {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Fetching proof report")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No proof report fetched yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }

    private var modelDetailText: String {
        guard let snapshot = chatStore.attestationSnapshot else {
            return "Selected for this chat"
        }
        return proofModelDetail(snapshot) ?? proofModelPhrase(snapshot)
    }

    private var signingDetailText: String {
        guard chatStore.attestationSnapshot != nil else {
            return "Available after proof fetch"
        }
        return "Checked locally from the signed report"
    }

    private var freshnessSummary: String {
        chatStore.currentAttestationStatus.freshness()?.shortLabel ?? (chatStore.attestationSnapshot == nil ? "Not fetched" : "Unknown")
    }

    private var freshnessDetailText: String {
        chatStore.attestationSnapshot?.fetchedAt.formatted(date: .abbreviated, time: .standard) ?? "Fetch proof to check freshness"
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
                subject: Text("NEAR Private Chat proof JSON"),
                message: Text("Proof JSON only. It does not include conversation text.")
            ) {
                Label("Share Proof JSON", systemImage: "square.and.arrow.up")
            }
            .accessibilityHint("Shares only the signed proof JSON.")

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
            .accessibilityHint("Fetch proof first to check the signed report on this device.")

            Button {} label: {
                Label("Share Proof JSON", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(true)
            .accessibilityHint("Fetch proof first to share proof JSON.")
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
            return "Fetching signed proof. Proof actions will unlock when the report is on this device."
        }
        if canFetchAttestation {
            return "Fetch proof to enable on-device verification and proof JSON sharing."
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

private struct ClaudeDetailRow<Content: View>: View {
    let label: String
    let trailing: AnyView?
    @ViewBuilder let content: () -> Content

    init(label: String, trailing: AnyView? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(label.uppercased())
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
                .kerning(0.5)
                .frame(width: 96, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
            if let trailing {
                trailing
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .accessibilityElement(children: .combine)
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

private struct VerificationDetailRow: View {
    let label: String
    let value: String
    let detail: String
    let symbolName: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 24, height: 24)

            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textSecondary)
                .textCase(.uppercase)
                .frame(width: 62, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.84)
                Text(detail)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value). \(detail)")
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
