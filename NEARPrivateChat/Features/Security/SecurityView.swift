import SwiftUI
import UniformTypeIdentifiers

struct SecurityView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var localProofCheckMessage: String?
    @State private var isEducationExpanded = false
    @State private var showingProofReportExporter = false
    @State private var proofReportDocument = ConversationExportDocument()
    @State private var proofReportFilename = "near-private-chat-proof-report.json"

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
                            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
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
            .fileExporter(
                isPresented: $showingProofReportExporter,
                document: proofReportDocument,
                contentType: ConversationExportFormat.json.contentType,
                defaultFilename: proofReportFilename
            ) { result in
                switch result {
                case .success:
                    chatStore.bannerMessage = "Proof report exported."
                case let .failure(error):
                    chatStore.bannerMessage = error.localizedDescription
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
                detail: "NEAR AI Cloud anonymizes your prompt before forwarding to the provider. This route carries no NEAR Private proof report.",
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
                Text(chatStore.selectedModelDisplayName)
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
                trailing: AnyView(Image(systemName: "chevron.right").font(.system(size: 14)).foregroundStyle(Color.textTertiary))
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
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                value: "\(chatStore.selectedProviderDisplayName) · \(chatStore.sourceModeDetail)",
                symbolName: chatStore.selectedRouteKind.disclosureSymbolName
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
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }

    private func disclosureRow(label: String, value: String, symbolName: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.actionPrimary)
                .frame(width: 24, height: 24)
                .background(Color.actionTint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
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
        if chatStore.selectedRouteKind == .ironclawHosted {
            return "Your prompt plus approved handoff context goes to Hosted IronClaw."
        }
        if chatStore.selectedRouteUsesNearCloud || (chatStore.isCouncilModeEnabled && chatStore.activeCouncilHasNearCloudRoutes) {
            return "Your prompt is proxied through NEAR AI Cloud before the model provider sees it."
        }
        if chatStore.sourceModeDetail.lowercased().contains("web") {
            return "Your prompt may use private-route web/source grounding. Local-only notes stay on device unless allowed."
        }
        return "The prompt stays on the selected private route. Local-only documents are excerpted only when the private route can use them."
    }

    private var unverifiedDisclosure: String {
        if chatStore.selectedRouteKind == .nearPrivate && !chatStore.selectedRouteUsesNearCloud {
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
                            Text("Check proof report")
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.actionPrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    prepareProofReportExport(snapshot)
                } label: {
                    HStack(spacing: 6) {
                        Text("Export proof report")
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .font(.headline)
                    .foregroundStyle(Color.actionPrimary)
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
                            .font(.headline)
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
                        .font(.system(size: 11, weight: .semibold))
                }
                .font(.footnote)
                .fontWeight(.regular)
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
            return "Report fetched at \(formatter.string(from: snapshot.fetchedAt))"
        }
        return "No proof report on this device"
    }

    private var conversationDetail: String {
        chatStore.attestationSnapshot == nil
            ? "Fetch proof report for the current route"
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
            Text("Proof report")
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
                    Label("Raw proof JSON", systemImage: "curlybraces")
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
                Text("No proof report on this device")
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

    private var freshnessDetailValue: String {
        guard let snapshot = chatStore.attestationSnapshot else {
            return chatStore.isLoadingAttestation ? "Fetching" : (canFetchAttestation ? "Not fetched" : "Unavailable")
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
        guard let snapshot = chatStore.attestationSnapshot else {
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
        guard let snapshot = chatStore.attestationSnapshot else {
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
        guard let snapshot = chatStore.attestationSnapshot else {
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
        guard let snapshot = chatStore.attestationSnapshot else {
            return "Awaiting proof"
        }

        switch chatStore.currentAttestationStatus.coverage(for: chatStore.selectedModel) {
        case .covered:
            return selectedModelHashPreview(in: snapshot, requireSelectedModelMatch: true) == nil
                ? "Selected model listed in proof"
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
        let modelID = shortenedIdentifier(chatStore.selectedModel, prefix: 24, suffix: 12)
        guard let snapshot = chatStore.attestationSnapshot else {
            return "\(modelID) · fetch proof to inspect model evidence."
        }
        return "\(modelID) · \(selectedModelHashStatus(in: snapshot))"
    }

    private var modelAttestationCountValue: String {
        guard let snapshot = chatStore.attestationSnapshot else {
            return "No proof report"
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
        guard let snapshot = chatStore.attestationSnapshot else {
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
        if chatStore.isCouncilModeEnabled, chatStore.activeCouncilHasExternalRoutes {
            return "Mixed or external Council lineups cannot fetch NEAR Private proof."
        }
        if chatStore.selectedRouteUsesNearCloud || (chatStore.isCouncilModeEnabled && chatStore.activeCouncilHasNearCloudRoutes) {
            return "Privacy proxy forwarding uses a separate trust boundary from NEAR Private proof reports."
        }

        switch chatStore.selectedRouteKind {
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

    private func gatewaySigningAddresses(_ snapshot: AttestationSnapshot) -> [(label: String, value: String)] {
        var addresses: [(label: String, value: String)] = []
        if let chatAddress = cleanedIdentifier(snapshot.chatGatewayAddress) {
            addresses.append(("Chat", chatAddress))
        }
        if let cloudAddress = cleanedIdentifier(snapshot.cloudGatewayAddress) {
            addresses.append(("Cloud", cloudAddress))
        }
        return addresses
    }

    private func selectedModelHashStatus(in snapshot: AttestationSnapshot) -> String {
        if let hash = selectedModelHashPreview(in: snapshot, requireSelectedModelMatch: true) {
            return "reported model hash \(shortenedIdentifier(hash, prefix: 14, suffix: 10))"
        }
        if snapshot.modelAttestationCount > 0 {
            return "model hash not exposed in parsed evidence"
        }
        return "no model hash evidence in this report"
    }

    private func selectedModelHashPreview(in snapshot: AttestationSnapshot, requireSelectedModelMatch: Bool = false) -> String? {
        guard let data = snapshot.prettyJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let attestations = value(at: ["model_attestations"], in: object) as? [Any] else {
            return nil
        }

        let attestationDictionaries = attestations.compactMap { $0 as? [String: Any] }
        let selectedModel = AttestationEvidence.normalizedModelID(chatStore.selectedModel)

        if let matchingAttestation = attestationDictionaries.first(where: { modelAttestation($0, matches: selectedModel) }),
           let hash = firstModelHash(in: matchingAttestation) {
            return hash
        }
        guard !requireSelectedModelMatch else { return nil }
        if attestationDictionaries.count == 1,
           let hash = firstModelHash(in: attestationDictionaries[0]) {
            return hash
        }
        return nil
    }

    private func value(at path: [String], in object: Any) -> Any? {
        var current = object
        for key in path {
            guard let dictionary = current as? [String: Any],
                  let next = dictionary[key] else {
                return nil
            }
            current = next
        }
        return current
    }

    private func modelAttestation(_ dictionary: [String: Any], matches normalizedModelID: String) -> Bool {
        func walk(_ value: Any) -> Bool {
            if let dictionary = value as? [String: Any] {
                for key in ["model", "model_id", "modelId", "id", "name"] {
                    if let modelID = dictionary[key] as? String,
                       AttestationEvidence.normalizedModelID(modelID) == normalizedModelID {
                        return true
                    }
                }
                return dictionary.values.contains(where: walk)
            }
            if let array = value as? [Any] {
                return array.contains(where: walk)
            }
            return false
        }
        return walk(dictionary)
    }

    private func firstModelHash(in dictionary: [String: Any]) -> String? {
        func walk(_ value: Any) -> String? {
            if let dictionary = value as? [String: Any] {
                for (key, child) in dictionary where isModelHashKey(key) {
                    if let string = child as? String,
                       let cleaned = cleanedIdentifier(string) {
                        return cleaned
                    }
                }
                for child in dictionary.values {
                    if let hash = walk(child) {
                        return hash
                    }
                }
            } else if let array = value as? [Any] {
                for child in array {
                    if let hash = walk(child) {
                        return hash
                    }
                }
            }
            return nil
        }
        return walk(dictionary)
    }

    private func isModelHashKey(_ key: String) -> Bool {
        let normalized = key
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
        return [
            "hash",
            "digest",
            "sha256",
            "modelhash",
            "modeldigest",
            "weightshash",
            "weightsdigest"
        ].contains(normalized)
    }

    private func cleanedIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func shortenedIdentifier(_ value: String, prefix: Int = 12, suffix: Int = 8) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > prefix + suffix + 3 else {
            return trimmed
        }
        return "\(trimmed.prefix(prefix))...\(trimmed.suffix(suffix))"
    }

    @ViewBuilder
    private var proofActionsContent: some View {
        if let snapshot = chatStore.attestationSnapshot {
            Button {
                verifyProofOnDevice(snapshot)
            } label: {
                Label("Check proof report", systemImage: "checkmark.shield")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityHint("Checks the cached signed report on this device. It does not verify answer truth.")

            Button {
                prepareProofReportExport(snapshot)
            } label: {
                Label("Export Proof Report", systemImage: "square.and.arrow.up")
            }
            .disabled(proofReportExportUnavailableReason != nil)
            .accessibilityHint(proofReportExportUnavailableReason ?? "Exports only the signed proof report JSON.")

            if let localProofCheckMessage {
                Text(localProofCheckMessage)
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
                Label("Check proof report", systemImage: "checkmark.shield")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(true)
            .accessibilityHint("Fetch proof first to check the signed report on this device.")

            Button {} label: {
                Label("Export Proof Report", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(true)
            .accessibilityHint("Fetch proof first to export proof report JSON.")
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
                detail: "Proof covers route/model evidence when present.",
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
                value: "No proof report on this device",
                detail: proofActionsUnavailableText,
                symbolName: "shield.slash"
            )
        }
    }

    private func verifyProofOnDevice(_ snapshot: AttestationSnapshot) {
        let status = chatStore.currentAttestationStatus
        let copy = status.userFacingCopy()
        let nonceText = snapshot.nonce.isEmpty ? "Nonce is missing." : "Nonce is present."
        let message = "Proof report check: \(copy.title). \(nonceText) This checks signed TEE evidence cached on this device, not answer truth."
        localProofCheckMessage = message
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
                    Text("NEAR AI Cloud anonymizes your prompt before forwarding to the provider. This route carries no NEAR Private proof report.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            StatusChip(title: "Privacy proxy · external model", symbolName: "cloud", isPrimary: true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("NEAR AI Cloud privacy proxy route, external model")
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
            return "Fetch proof to enable on-device proof checking and report export."
        }
        return fetchAttestationDisabledText
    }

    private var proofReportExportUnavailableReason: String? {
        guard chatStore.attestationSnapshot != nil else {
            return "No proof report on this device. Fetch proof first."
        }
        guard canFetchAttestation else {
            return fetchAttestationDisabledText
        }
        guard chatStore.currentAttestationStatus.effectiveState() == .valid else {
            return "Refresh proof before exporting the cached proof report."
        }
        return nil
    }

    private var verificationDetailTitle: String {
        canFetchAttestation ? "Proof details" : "Route trust details"
    }

    private func prepareProofReportExport(_ snapshot: AttestationSnapshot) {
        if let reason = proofReportExportUnavailableReason {
            chatStore.bannerMessage = reason
            return
        }
        proofReportDocument = ConversationExportDocument(data: Data(snapshot.prettyJSON.utf8))
        proofReportFilename = "near-private-chat-proof-report.json"
        showingProofReportExporter = true
    }

    private var fetchAttestationDisabledText: String {
        if chatStore.isCouncilModeEnabled, chatStore.activeCouncilHasExternalRoutes {
            return "Proof can be fetched for all-private Council lineups. Remove NEAR AI Cloud models to fetch proof."
        }
        return "Switch to a NEAR Private model to fetch proof."
    }

    private func attestationCoveragePhrase(_ snapshot: AttestationSnapshot) -> String {
        if !snapshot.coveredModelIDs.isEmpty {
            if snapshot.coveredModelIDs.count == 1, let model = snapshot.coveredModelIDs.first {
                return "\(model) listed in proof"
            }
            return "\(snapshot.coveredModelIDs.count) models listed in proof"
        }
        if let model = snapshot.model, snapshot.modelAttestationCount <= 1 {
            return "\(model) listed in proof"
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
            return chatStore.currentAttestationStatus.coverage(for: chatStore.selectedModel) == .covered ? "Model ID listed in the current proof." : "Current selected model may need a refreshed proof."
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
        if chatStore.isCouncilModeEnabled {
            return "LLM Council"
        }
        switch chatStore.selectedRouteKind {
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
            return chatStore.ironclawRemoteWorkstationAvailable ? "Phone + Hosted IronClaw" : "Phone runtime"
        case .ironclawHosted:
            return chatStore.ironclawSettings.hasUsableHostedEndpoint ? "Agent connection configured" : "Not configured"
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
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
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
                    .lineLimit(3)
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
