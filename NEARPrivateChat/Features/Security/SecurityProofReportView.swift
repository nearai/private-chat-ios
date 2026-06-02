import SwiftUI

extension SecurityView {
    @ViewBuilder
    var reportCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Proof report")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            if let error = attestationFetchErrorMessage {
                InfoRow(title: "Last fetch", value: error)
            }

            if let snapshot = attestationSnapshot {
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
                    showBanner("Proof report copied.")
                } label: {
                    Label("Copy report", systemImage: "doc.on.doc")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.actionPrimary)
            } else if isLoadingAttestation {
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

    func attestationCoveragePhrase(_ snapshot: AttestationSnapshot) -> String {
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
}
