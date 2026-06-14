import SwiftUI
import UniformTypeIdentifiers

struct SecurityView: View {
    @EnvironmentObject var securityStore: SecurityStore
    @EnvironmentObject var modelCatalogStore: ModelCatalogStore
    @EnvironmentObject var agentStore: AgentStore
    @Environment(\.dismiss) private var dismiss
    @State var localProofCheckMessage: String?
    @State private var isEducationExpanded = false
    @State private var showingProofReportExporter = false
    @State var proofReportDocument = ConversationExportDocument()
    @State var proofReportFilename = "near-private-chat-proof-report.json"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    verifiedHero
                    routeDisclosureCard
                    actionStack
                    detailListCard
                    verificationDetailCard
                    DisclosureGroup(isExpanded: $isEducationExpanded) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(AttestationEducation.standard.sections) { section in
                                AttestationEducationRow(section: section)
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Text("How proof works")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                    }
                    .padding(14)
                    .background(Color.appPanelBackground, in: RoundedRectangle.app(AppRadius.pill))
                    .overlay {
                        RoundedRectangle.app(AppRadius.pill)
                            .stroke(Color.appBorder, lineWidth: 1)
                    }
                    reportCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .background(Color.appBackground)
            .navigationTitle("Proof")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                if canFetchAttestation, attestationSnapshot == nil, !isLoadingAttestation {
                    await refreshAttestationReport()
                }
            }
            .fileExporter(
                isPresented: $showingProofReportExporter,
                document: proofReportDocument,
                contentType: ConversationExportFormat.json.contentType,
                defaultFilename: proofReportFilename
            ) { result in
                switch result {
                case .success:
                    showBanner("Proof report exported.")
                case let .failure(error):
                    showBanner(MessageRepository.displayFailureMessage(error.localizedDescription))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    var attestationSnapshot: AttestationSnapshot? {
        securityStore.attestationSnapshot
    }

    var attestationFetchErrorMessage: String? {
        securityStore.attestationFetchErrorMessage
    }

    var isLoadingAttestation: Bool {
        securityStore.isLoadingAttestation
    }

    var selectedModelID: String {
        modelCatalogStore.selectedModel
    }

    private var selectedRouteKind: ChatRouteKind {
        modelCatalogStore.selectedRouteKind
    }

    private var selectedRouteUsesNearCloud: Bool {
        modelCatalogStore.selectedRouteUsesNearCloud
    }

    private var selectedModelDisplayName: String {
        modelCatalogStore.selectedModelDisplayName
    }

    private var selectedProviderDisplayName: String {
        modelCatalogStore.selectedProviderDisplayName
    }

    private var isCouncilModeEnabled: Bool {
        modelCatalogStore.isCouncilModeEnabled
    }

    private var activeCouncilHasNearCloudRoutes: Bool {
        modelCatalogStore.activeCouncilHasNearCloudRoutes
    }

    private var activeCouncilHasExternalRoutes: Bool {
        modelCatalogStore.activeCouncilHasExternalRoutes
    }

    private var sourceModeDetail: String {
        let semantics = modelCatalogStore.sourceRoutingSemantics(for: selectedRouteKind)
        switch semantics.focus {
        case .auto:
            return semantics.modelNativeWebToolEnabledByDefault || semantics.appWebGroundingPolicy.isEnabledByDefault
                ? "Auto · sources when useful"
                : "Auto · project files"
        case .web:
            if semantics.modelNativeWebToolPolicy != .never {
                return "Web"
            }
            return semantics.appWebGroundingPolicy == .never ? "Web · off" : "Web · app search"
        case .links:
            return "Links"
        case .files:
            return "Files"
        case .project:
            if semantics.modelNativeWebToolPolicy != .never {
                return "Project · live sources"
            }
            return semantics.appWebGroundingPolicy == .never ? "Project" : "Project · app sources"
        case .research:
            if semantics.modelNativeWebToolPolicy != .never {
                return "Research · live sources"
            }
            return semantics.appWebGroundingPolicy == .never ? "Research" : "Research · app sources"
        }
    }

    private var currentAttestationStatus: AttestationStatus {
        securityStore.currentAttestationStatus(
            selectedModelID: selectedModelID,
            selectedRouteKind: selectedRouteKind,
            isCouncilModeEnabled: isCouncilModeEnabled,
            activeCouncilHasExternalRoutes: activeCouncilHasExternalRoutes
        )
    }

    private func refreshAttestationReport() async {
        await securityStore.refreshAttestationReport(
            selectedModelID: selectedModelID,
            selectedRouteKind: selectedRouteKind,
            isCouncilModeEnabled: isCouncilModeEnabled,
            activeCouncilHasExternalRoutes: activeCouncilHasExternalRoutes
        )
    }

    private var currentProofViewModel: ProofCapsuleViewModel {
        if selectedRouteUsesNearCloud || (isCouncilModeEnabled && activeCouncilHasNearCloudRoutes) {
            return ProofCapsuleViewModel(
                state: .proxied,
                title: "Privacy proxy",
                detail: "NEAR AI Cloud anonymizes your prompt before forwarding to the provider. This route carries no NEAR Private proof report.",
                badge: "Privacy proxy",
                symbolName: "eye.slash"
            )
        }

        return ProofCapsuleViewModel(
            status: currentAttestationStatus,
            isLoading: isLoadingAttestation,
            modelID: selectedModelID
        )
    }

    private var verifiedHero: some View {
        let proof = currentProofViewModel
        return VStack(spacing: 14) {
            ZStack {
                // A soft filled disc is a single container for the glyph. The
                // previous thin stroked outline competed with the shield/seal
                // glyph's own outline, reading as two stacked rounded shapes.
                Circle()
                    .fill(proof.tintColor.opacity(0.12))
                    .frame(width: 64, height: 64)
                if proof.state == .verifying {
                    ProgressView()
                } else {
                    Image(systemName: proof.symbolName)
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(proofTextTint(for: proof.state))
                }
            }

            VStack(spacing: 14) {
                Text(proof.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text(proof.detail)
                    .font(.subheadline)
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
                Text(selectedModelDisplayName)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
            Divider().background(Color.appHairline).padding(.leading, 16)

            ClaudeDetailRow(label: "Runtime", trailing: hardwareTrailing) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(hardwareSummary)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Text(hardwareDetail)
                        .font(.footnote)
                        .fontWeight(.regular)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Divider().background(Color.appHairline).padding(.leading, 16)

            ClaudeDetailRow(
                label: "Proof report",
                trailing: AnyView(Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.textTertiary))
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversationSummary)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Text(conversationDetail)
                        .font(.footnote)
                        .fontWeight(.regular)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            // v2: duplicate in-card proof-check preview row removed —
            // the spec's PrimaryButton below is the single tap target. Two
            // identical labels read as redundant. Only the primary CTA in
            // `actionStack` stays.
        }
        .background(Color.appPanelBackground, in: RoundedRectangle.app(AppRadius.control))
        .overlay {
            RoundedRectangle.app(AppRadius.control)
                .stroke(Color.appBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle.app(AppRadius.control))
    }

    private var routeDisclosureCard: some View {
        let proof = currentProofViewModel
        return VStack(alignment: .leading, spacing: 11) {
            Label("This answer used", systemImage: "lock.doc")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.textPrimary)

            disclosureRow(
                label: "What left this phone",
                value: whatLeftPhoneDisclosure,
                symbolName: "iphone.and.arrow.forward"
            )
            disclosureRow(
                label: "Route",
                value: "\(selectedProviderDisplayName) · \(sourceModeDetail)",
                symbolName: selectedRouteKind.disclosureSymbolName
            )
            disclosureRow(
                label: "Verified",
                value: proof.state == .verified ? "Model/runtime proof is available for the private route." : proof.title,
                symbolName: "checkmark.shield"
            )
            disclosureRow(
                label: "Not verified",
                value: unverifiedDisclosure,
                symbolName: "exclamationmark.triangle"
            )
        }
        .padding(12)
        .background(Color.appPanelBackground, in: RoundedRectangle.app(AppRadius.pill))
        .overlay {
            RoundedRectangle.app(AppRadius.pill)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }

    private func disclosureRow(label: String, value: String, symbolName: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.actionPrimaryText)
                .frame(width: 24, height: 24)
                .background(Color.actionTint, in: RoundedRectangle.app(AppRadius.pill))
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
                    .textCase(.uppercase)
                Text(value)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var whatLeftPhoneDisclosure: String {
        if selectedRouteKind == .ironclawHosted {
            return "Your prompt plus approved handoff context goes to Hosted IronClaw."
        }
        if selectedRouteUsesNearCloud || (isCouncilModeEnabled && activeCouncilHasNearCloudRoutes) {
            return "Your prompt is proxied through NEAR AI Cloud before the model provider sees it."
        }
        if sourceModeDetail.lowercased().contains("web") {
            return "Your prompt may use private-route web/source grounding. Local-only notes stay on device unless allowed."
        }
        return "The prompt stays on the selected private route. Local-only documents are excerpted only when the private route can use them."
    }

    private var unverifiedDisclosure: String {
        if selectedRouteKind == .nearPrivate && !selectedRouteUsesNearCloud {
            return "Web pages, uploaded files, and model claims are not magically true; verify sources before sharing."
        }
        return "External cloud or Hosted IronClaw execution is outside the NEAR Private proof report."
    }

    private var verificationDetailCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                Text(verificationDetailTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider().background(Color.appHairline)

            VerificationDetailRow(
                label: "Fresh",
                value: freshnessDetailValue,
                detail: freshnessDetailText,
                symbolName: "clock"
            )
            Divider().background(Color.appHairline).padding(.leading, 14)

            VerificationDetailRow(
                label: "Signer",
                value: signingAddressValue,
                detail: signingAddressDetailText,
                symbolName: "key.horizontal"
            )
            Divider().background(Color.appHairline).padding(.leading, 14)

            VerificationDetailRow(
                label: "Model",
                value: selectedModelCoverageValue,
                detail: selectedModelHashDetailText,
                symbolName: "cpu"
            )
            Divider().background(Color.appHairline).padding(.leading, 14)

            VerificationDetailRow(
                label: "Entries",
                value: modelAttestationCountValue,
                detail: modelAttestationCountDetailText,
                symbolName: "list.bullet.rectangle"
            )
            Divider().background(Color.appHairline).padding(.leading, 14)

            VerificationDetailRow(
                label: "Current route",
                value: routeSummary,
                detail: routeCaveatText,
                symbolName: routeSymbolName
            )
        }
        .background(Color.appPanelBackground, in: RoundedRectangle.app(AppRadius.control))
        .overlay {
            RoundedRectangle.app(AppRadius.control)
                .stroke(Color.appBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle.app(AppRadius.control))
    }

    private var actionStack: some View {
        VStack(spacing: 6) {
            if let snapshot = attestationSnapshot {
                PrimaryButton("Check proof report", systemImage: "lock.shield") {
                    verifyProofOnDevice(snapshot)
                }

                Button {
                    prepareProofReportExport(snapshot)
                } label: {
                    HStack(spacing: 6) {
                        Text("Export proof report")
                        Image(systemName: "arrow.up.right")
                            .font(.subheadline.weight(.semibold))
                    }
                    .font(.headline)
                    .foregroundStyle(Color.actionPrimaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                }
                .disabled(proofReportExportUnavailableReason != nil)
                .accessibilityHint(proofReportExportUnavailableReason ?? "Exports only the cached proof report JSON.")

                if let localProofCheckMessage {
                    Text(localProofCheckMessage)
                        .font(.footnote)
                        .fontWeight(.regular)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            } else if canFetchAttestation {
                PrimaryButton {
                    Task { await refreshAttestationReport() }
                } label: {
                    HStack(spacing: 8) {
                        if isLoadingAttestation {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.body.weight(.semibold))
                        }
                        Text(isLoadingAttestation ? "Fetching proof" : "Fetch proof")
                    }
                }
                .disabled(isLoadingAttestation)
            } else {
                Text(proofActionsUnavailableText)
                    .font(.footnote)
                    .fontWeight(.regular)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    isEducationExpanded = true
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Learn how this works")
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                }
                .font(.footnote)
                .fontWeight(.regular)
                .foregroundStyle(Color.textTertiary)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .padding(.top, 4)
    }

    private var modelTrailing: AnyView {
        AnyView(Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.textTertiary))
    }

    private var hardwareTrailing: AnyView {
        let isCovered = attestationSnapshot != nil &&
            currentAttestationStatus.effectiveState() == .valid
        return AnyView(
            Image(systemName: isCovered ? "checkmark.seal.fill" : "shield")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isCovered ? Color.proofVerifiedText : Color.textTertiary)
        )
    }

    private func proofTextTint(for state: ProofState) -> Color {
        switch state {
        case .verified:
            return .proofVerifiedText
        case .stale, .verifying:
            return .proofStaleText
        case .mismatch:
            return .proofMismatch
        case .unknown, .private_, .proxied, .unverified:
            return .textSecondary
        }
    }

    private var hardwareSummary: String {
        switch selectedRouteKind {
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
        if let snapshot = attestationSnapshot,
           let alg = snapshot.signingAlgorithm.isEmpty ? nil : snapshot.signingAlgorithm {
            return "Signed with \(alg.uppercased())"
        }
        return endpointSummary
    }

    private var conversationSummary: String {
        if let snapshot = attestationSnapshot {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            return "Report fetched at \(formatter.string(from: snapshot.fetchedAt))"
        }
        return "Proof not fetched on this device"
    }

    private var conversationDetail: String {
        attestationSnapshot == nil
            ? "Fetch proof report for the current route"
            : "Checked on this device"
    }

    private var freshnessDetailValue: String {
        guard let snapshot = attestationSnapshot else {
            return isLoadingAttestation ? "Fetching" : (canFetchAttestation ? "Not fetched" : "Unavailable")
        }

        switch AttestationFreshness.classify(attestedAt: snapshot.fetchedAt) {
        case .underTwoMinutes:
            return "Fresh (<2m)"
        case .underOneHour:
            return "Recent (<1h)"
        case .stale:
            return "Stale"
        }
    }

    private var freshnessDetailText: String {
        guard let snapshot = attestationSnapshot else {
            return canFetchAttestation ? "Fetch proof to inspect the report timestamp." : fetchAttestationDisabledText
        }

        let timestamp = snapshot.fetchedAt.formatted(date: .abbreviated, time: .standard)
        switch AttestationFreshness.classify(attestedAt: snapshot.fetchedAt) {
        case .underTwoMinutes, .underOneHour:
            return "Report timestamp \(timestamp). Refresh after route or model changes."
        case .stale:
            return "Report timestamp \(timestamp). Refresh before relying on coverage."
        }
    }

    private var signingAddressValue: String {
        guard let snapshot = attestationSnapshot else {
            return "Not fetched"
        }
        let addresses = gatewaySigningAddresses(snapshot)
        guard !addresses.isEmpty else {
            return "Not included"
        }
        if addresses.count > 1 {
            return "\(addresses.count) addresses"
        }
        let address = addresses[0]
        return "\(address.label) \(shortenedIdentifier(address.value))"
    }

    private var signingAddressDetailText: String {
        guard let snapshot = attestationSnapshot else {
            return "Gateway signing addresses are shown after a proof fetch."
        }
        let addresses = gatewaySigningAddresses(snapshot)
        guard !addresses.isEmpty else {
            return "The cached report did not expose gateway signing addresses."
        }
        return addresses
            .map { "\($0.label): \(shortenedIdentifier($0.value, prefix: 14, suffix: 10))" }
            .joined(separator: " · ")
    }

    private var selectedModelCoverageValue: String {
        guard let snapshot = attestationSnapshot else {
            return "Awaiting proof"
        }

        switch currentAttestationStatus.coverage(for: selectedModelID) {
        case .covered:
            return selectedModelHashPreview(in: snapshot, requireSelectedModelMatch: true) == nil
                ? "Model name listed in proof"
                : "Exact model hash listed"
        case .stale:
            return "Model listing stale"
        case .notCovered:
            return "Selected model not listed"
        case .unknown:
            return "Coverage unknown"
        }
    }

    private var selectedModelHashDetailText: String {
        let modelID = shortenedIdentifier(selectedModelID, prefix: 24, suffix: 12)
        guard let snapshot = attestationSnapshot else {
            return "\(modelID) · fetch proof to inspect model evidence."
        }
        return "\(modelID) · \(selectedModelHashStatus(in: snapshot))"
    }

    private var modelAttestationCountValue: String {
        guard let snapshot = attestationSnapshot else {
            return "Awaiting proof"
        }
        let count = snapshot.modelAttestationCount
        if count == 1 {
            return "1 model proof entry"
        }
        if count > 1 {
            return "\(count) model proof entries"
        }
        return "No model proof entries"
    }

    private var modelAttestationCountDetailText: String {
        guard let snapshot = attestationSnapshot else {
            return "The proof report has not been fetched on this device."
        }
        if snapshot.modelAttestationCount > 0 {
            return attestationCoveragePhrase(snapshot)
        }
        if !snapshot.coveredModelIDs.isEmpty {
            return "\(snapshot.coveredModelIDs.count) listed model IDs parsed outside model_attestations."
        }
        return "Gateway evidence may still be present; model-level entries were not parsed."
    }

    private var routeCaveatText: String {
        if isCouncilModeEnabled, activeCouncilHasExternalRoutes {
            return "Mixed or external Council lineups cannot fetch NEAR Private proof."
        }
        if selectedRouteUsesNearCloud || (isCouncilModeEnabled && activeCouncilHasNearCloudRoutes) {
            return "Privacy proxy forwarding uses a separate trust boundary from NEAR Private proof reports."
        }

        switch selectedRouteKind {
        case .nearPrivate:
            return "Proof covers reported route and model evidence only; it does not verify answer truth or safety."
        case .nearCloud:
            return "NEAR AI Cloud anonymizes prompts through a privacy proxy."
        case .ironclawMobile:
            return "IronClaw Mobile is outside the NEAR Private proof report."
        case .ironclawHosted:
            return "Hosted IronClaw availability is separate from NEAR Private proof coverage."
        }
    }

private func verifyProofOnDevice(_ snapshot: AttestationSnapshot) {
        let status = currentAttestationStatus
        let copy = status.userFacingCopy()
        let nonceText = snapshot.nonce.isEmpty ? " Nonce is missing from the detailed report." : ""
        let message = "Proof report check: \(copy.title). This checks signed TEE evidence cached on this device, not answer truth.\(nonceText)"
        localProofCheckMessage = message
        showBanner(message)
    }

    private var canFetchAttestation: Bool {
        if isCouncilModeEnabled {
            return !activeCouncilHasExternalRoutes && selectedRouteKind == .nearPrivate
        }
        return selectedRouteKind == .nearPrivate
    }

    private var proofActionsUnavailableText: String {
        if isLoadingAttestation {
            return "Fetching signed proof. Proof actions will unlock when the report is on this device."
        }
        if canFetchAttestation {
            return "Fetch proof to enable on-device proof checking and report export."
        }
        return fetchAttestationDisabledText
    }

    private var proofReportExportUnavailableReason: String? {
        guard attestationSnapshot != nil else {
            return "Proof has not been fetched on this device. Fetch proof first."
        }
        guard canFetchAttestation else {
            return fetchAttestationDisabledText
        }
        guard currentAttestationStatus.effectiveState() == .valid else {
            return "Refresh proof before exporting the cached proof report."
        }
        return nil
    }

    private var verificationDetailTitle: String {
        canFetchAttestation ? "Proof details" : "Route trust details"
    }

    private func prepareProofReportExport(_ snapshot: AttestationSnapshot) {
        if let reason = proofReportExportUnavailableReason {
            showBanner(reason)
            return
        }
        proofReportDocument = ConversationExportDocument(data: Data(snapshot.prettyJSON.utf8))
        proofReportFilename = "near-private-chat-proof-report.json"
        showingProofReportExporter = true
    }

    private var fetchAttestationDisabledText: String {
        if isCouncilModeEnabled, activeCouncilHasExternalRoutes {
            return "Proof can be fetched for all-private Council lineups. Remove NEAR AI Cloud models to fetch proof."
        }
        return "Switch to a NEAR Private model to fetch proof."
    }

    private func proofModelPhrase(_ snapshot: AttestationSnapshot) -> String {
        if !snapshot.coveredModelIDs.isEmpty {
            if snapshot.coveredModelIDs.count == 1, let model = snapshot.coveredModelIDs.first {
                return model
            }
            if snapshot.coveredModelIDs.contains(where: { AttestationEvidence.normalizedModelID($0) == AttestationEvidence.normalizedModelID(selectedModelID) }) {
                return "\(selectedModelID) + \(snapshot.coveredModelIDs.count - 1) more"
            }
            return "\(snapshot.coveredModelIDs.count) listed models"
        }
        if let model = snapshot.model {
            return model
        }
        if snapshot.modelAttestationCount > 0 {
            return "\(snapshot.modelAttestationCount) model proof entries, IDs unavailable"
        }
        return "Coverage metadata not in report"
    }

    private func proofModelDetail(_ snapshot: AttestationSnapshot) -> String? {
        if !snapshot.coveredModelIDs.isEmpty || snapshot.model != nil {
            return currentAttestationStatus.coverage(for: selectedModelID) == .covered ? "Model ID listed in the current proof." : "Current selected model may need a refreshed proof."
        }
        return "The private model can still run; this report just cannot prove model coverage."
    }

    private func proofRuntimePhrase(_ snapshot: AttestationSnapshot) -> String {
        if snapshot.chatGatewayAddress != nil {
            return "NEAR Private chat gateway"
        }
        if snapshot.cloudGatewayAddress != nil {
            return "NEAR AI Cloud gateway"
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
        if isCouncilModeEnabled {
            return "LLM Council"
        }
        switch selectedRouteKind {
        case .nearPrivate:
            return "NEAR Private"
        case .nearCloud:
            return "NEAR AI Cloud"
        case .ironclawMobile:
            return "IronClaw Mobile"
        case .ironclawHosted:
            return "Hosted IronClaw"
        }
    }

    private var routeSymbolName: String {
        switch selectedRouteKind {
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
        switch selectedRouteKind {
        case .nearPrivate:
            return "private.near.ai"
        case .nearCloud:
            return "cloud-api.near.ai"
        case .ironclawMobile:
            return agentStore.ironclawRemoteWorkstationAvailable ? "Phone + Hosted IronClaw" : "Phone runtime"
        case .ironclawHosted:
            return agentStore.ironclawSettings.hasUsableHostedEndpoint ? "Agent connection configured" : "Not configured"
        }
    }

    func showBanner(_ message: String) {
        securityStore.bannerHandler?(message)
    }

}
