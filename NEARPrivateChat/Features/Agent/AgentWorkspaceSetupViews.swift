import SwiftUI

struct AgentWorkspaceHeader: View {
    @EnvironmentObject private var agentStore: AgentStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "terminal")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.brandAccent)
                    .frame(width: 42, height: 42)
                    .background(Color.brandAccent.opacity(0.09), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Connect Agent")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Connect Hosted IronClaw, then launch repo, research, and code tasks from your phone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ChipFlowLayout(spacing: 7, lineSpacing: 7) {
                StatusChip(title: agentStore.ironclawRemoteWorkstationAvailable ? "Hosted on" : "Hosted off", symbolName: "server.rack", isPrimary: agentStore.ironclawRemoteWorkstationAvailable)
                StatusChip(title: agentStore.ironclawToolNames.isEmpty ? "Tools on run" : "\(agentStore.ironclawToolNames.count) tools", symbolName: "terminal", isPrimary: !agentStore.ironclawToolNames.isEmpty)
                StatusChip(title: agentStore.ironclawTokenConfigured ? "Token saved" : "Token needed", symbolName: "key", isPrimary: false)
                StatusChip(title: "Phone controlled", symbolName: "iphone", isPrimary: false)
            }
        }
    }
}

struct AgentWorkspaceSetupPanel: View {
    let onConnectHostedIronclaw: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Connect Agent", systemImage: "server.rack")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
            Text("Add a Hosted IronClaw URL and token in Account. LAN gateways are not phone-ready routes.")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                onConnectHostedIronclaw()
            } label: {
                Label("Connect Hosted IronClaw", systemImage: "point.3.connected.trianglepath.dotted")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.actionPrimary)
        }
        .padding(12)
        .frame(maxWidth: 460, alignment: .leading)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }
}
