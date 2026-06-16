import SwiftUI

// MARK: - ProofReportView

/// Full-screen proof report detail view, expanding from the VerifiedFooterButton badge.
struct ProofReportView: View {
    let snapshot: AttestationSnapshot?
    let proofState: ProofState
    let modelID: String?
    let responseID: String?

    @Environment(\.dismiss) private var dismiss
    @State private var showingRawReport = false
    @State private var isEducationExpanded = false
    @State private var copiedField: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    heroSection
                    routeSection
                    signingSection
                    timestampSection
                    if responseID != nil {
                        responseIDSection
                    }
                    educationSection
                    if snapshot?.prettyJSON.isEmpty == false {
                        rawReportButton
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color.appBackground)
            .navigationTitle("Proof Report")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingRawReport) {
                RawAttestationReportView(json: snapshot?.prettyJSON ?? "")
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(heroTintColor.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: heroSymbol)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(heroTintColor)
            }
            VStack(spacing: 4) {
                Text(heroTitle)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                if let modelID {
                    Text(modelID)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .background(Color.appPanelBackground, in: RoundedRectangle.app(AppRadius.pill))
        .overlay {
            RoundedRectangle.app(AppRadius.pill)
                .stroke(heroTintColor.opacity(0.25), lineWidth: 1)
        }
    }

    // MARK: - Route

    private var routeSection: some View {
        ProofDetailCard(title: "Route") {
            ProofDetailRow(label: "Route", value: routeDescription)
            if let teeType = teeType {
                ProofDetailRow(label: "TEE Type", value: teeType)
            }
        }
    }

    // MARK: - Signing

    private var signingSection: some View {
        ProofDetailCard(title: "Signing") {
            if let algo = snapshot?.signingAlgorithm, !algo.isEmpty {
                ProofDetailRow(label: "Algorithm", value: algo)
            }
            if let nonce = snapshot?.nonce, !nonce.isEmpty {
                ProofCopyRow(
                    label: "Signing Key / Nonce",
                    value: nonce,
                    displayValue: truncatedKey(nonce),
                    copiedField: $copiedField,
                    fieldID: "nonce"
                )
            }
            if let chatGW = snapshot?.chatGatewayAddress, !chatGW.isEmpty {
                ProofCopyRow(
                    label: "Chat Gateway",
                    value: chatGW,
                    displayValue: truncatedKey(chatGW),
                    copiedField: $copiedField,
                    fieldID: "chatGW"
                )
            }
            if let cloudGW = snapshot?.cloudGatewayAddress, !cloudGW.isEmpty {
                ProofCopyRow(
                    label: "Cloud Gateway",
                    value: cloudGW,
                    displayValue: truncatedKey(cloudGW),
                    copiedField: $copiedField,
                    fieldID: "cloudGW"
                )
            }
        }
    }

    // MARK: - Timestamp

    private var timestampSection: some View {
        ProofDetailCard(title: "Timestamp") {
            if let fetchedAt = snapshot?.fetchedAt {
                ProofDetailRow(label: "Generated", value: formattedDate(fetchedAt))
                ProofDetailRow(label: "Age", value: ageText(fetchedAt))
                ProofDetailRow(label: "Models Covered", value: "\(snapshot?.modelAttestationCount ?? snapshot?.coveredModelIDs.count ?? 0)")
            } else {
                ProofDetailRow(label: "Generated", value: "Unavailable")
            }
        }
    }

    // MARK: - Response ID

    private var responseIDSection: some View {
        ProofDetailCard(title: "Response") {
            if let rid = responseID {
                ProofCopyRow(
                    label: "Response ID",
                    value: rid,
                    displayValue: truncatedKey(rid),
                    copiedField: $copiedField,
                    fieldID: "responseID"
                )
            }
        }
    }

    // MARK: - Education

    private var educationSection: some View {
        DisclosureGroup(isExpanded: $isEducationExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                Text("This response was generated by a NEAR Private AI inference node running inside a Trusted Execution Environment (TEE). The signing key proves the hardware identity of the node. It does not prove the answer is correct — only that it was generated privately, without the operator seeing your prompt.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                ForEach(AttestationEducation.standard.sections) { section in
                    AttestationEducationRow(section: section)
                }
            }
        } label: {
            Text("What this proves")
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
    }

    // MARK: - Raw Report

    private var rawReportButton: some View {
        Button {
            showingRawReport = true
        } label: {
            HStack {
                Label("View raw attestation report", systemImage: "doc.text")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color.appPanelBackground, in: RoundedRectangle.app(AppRadius.pill))
            .overlay {
                RoundedRectangle.app(AppRadius.pill)
                    .stroke(Color.appBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    // MARK: - Helpers

    private var heroSymbol: String {
        switch proofState {
        case .verified:
            return "checkmark.shield.fill"
        case .stale:
            return "clock.badge.exclamationmark"
        case .mismatch:
            return "exclamationmark.shield.fill"
        case .verifying:
            return "arrow.triangle.2.circlepath"
        case .private_:
            return "lock.shield.fill"
        case .proxied:
            return "arrow.triangle.branch"
        case .unverified, .unknown:
            return "xmark.shield.fill"
        }
    }

    private var heroTintColor: Color {
        switch proofState {
        case .verified:
            return .proofVerified
        case .stale:
            return .proofStale
        case .mismatch:
            return .proofMismatch
        case .private_:
            return .proofVerified
        default:
            return .secondary
        }
    }

    private var heroTitle: String {
        switch proofState {
        case .verified:
            return "Verified Private Response"
        case .stale:
            return "Proof Stale"
        case .mismatch:
            return "Model Not Covered"
        case .verifying:
            return "Checking Proof"
        case .private_:
            return "Private Route"
        case .proxied:
            return "Privacy Proxy Route"
        case .unverified, .unknown:
            return "Verification Unavailable"
        }
    }

    private var routeDescription: String {
        switch proofState {
        case .private_, .verified:
            return "NEAR Private AI (TEE)"
        case .proxied:
            return "NEAR AI Cloud (Privacy Proxy)"
        default:
            return snapshot != nil ? "NEAR Private AI (TEE)" : "NEAR Private AI"
        }
    }

    private var teeType: String? {
        guard proofState == .verified || proofState == .private_ else { return nil }
        return "Trusted Execution Environment"
    }

    private func truncatedKey(_ value: String) -> String {
        guard value.count > 24 else { return value }
        let prefix = String(value.prefix(16))
        let suffix = String(value.suffix(8))
        return "\(prefix)...\(suffix)"
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func ageText(_ date: Date) -> String {
        let delta = max(0, Date().timeIntervalSince(date))
        if delta < 120 { return "< 2 min" }
        if delta < 3600 { return "\(Int(delta / 60)) min" }
        if delta < 86400 { return "\(Int(delta / 3600)) hr" }
        return "\(Int(delta / 86400)) days"
    }
}

// MARK: - ProofDetailCard

private struct ProofDetailCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 8)
            Divider()
                .padding(.horizontal, 14)
            content()
        }
        .background(Color.appPanelBackground, in: RoundedRectangle.app(AppRadius.pill))
        .overlay {
            RoundedRectangle.app(AppRadius.pill)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }
}

// MARK: - ProofDetailRow

private struct ProofDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - ProofCopyRow (monospaced, tap-to-copy)

private struct ProofCopyRow: View {
    let label: String
    let value: String
    let displayValue: String
    @Binding var copiedField: String?
    let fieldID: String

    private var isCopied: Bool { copiedField == fieldID }

    var body: some View {
        Button {
            UIPasteboard.general.string = value
            copiedField = fieldID
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if copiedField == fieldID { copiedField = nil }
            }
        } label: {
            HStack(alignment: .center) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 6) {
                    Text(displayValue)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isCopied ? Color.proofVerified : .secondary)
                        .animation(.easeInOut(duration: 0.2), value: isCopied)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - RawAttestationReportView

private struct RawAttestationReportView: View {
    let json: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(json.isEmpty ? "No raw data available." : json)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .textSelection(.enabled)
            }
            .background(Color.appBackground)
            .navigationTitle("Raw Report")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        UIPasteboard.general.string = json
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
