import SwiftUI

struct IronclawOutboundTargetsView: View {
    @EnvironmentObject private var agentStore: AgentStore
    private let ironclawAPI = IronclawAPI()
    @State private var targets: [IronclawOutboundTarget] = []
    @State private var isLoading = false

    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.appSecondaryBackground)
            } else if targets.isEmpty {
                Text("No outbound targets configured.")
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.appSecondaryBackground)
            } else {
                ForEach(targets) { target in
                    OutboundTargetRow(target: target)
                }
            }
        }
        .navigationTitle("Outbound Targets")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .task {
            await load()
        }
        .refreshable {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        let token = agentStore.loadIronclawAuthToken() ?? ""
        targets = await ironclawAPI.fetchOutboundTargets(
            settings: agentStore.ironclawSettings,
            authToken: token
        )
        isLoading = false
    }
}

private struct OutboundTargetRow: View {
    let target: IronclawOutboundTarget

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: target.icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.brandAccent)
                .frame(width: 32, height: 32)
                .background(Color.brandAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(target.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                if !target.displayAddress.isEmpty {
                    Text(target.displayAddress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let trigger = target.triggerKind, !trigger.isEmpty {
                    Text("Trigger: \(trigger)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)

            if target.isActive == true {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.proofVerified)
                    .font(.caption)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.appSecondaryBackground)
    }
}
