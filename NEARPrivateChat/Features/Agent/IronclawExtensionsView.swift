import SwiftUI

struct IronclawExtensionsView: View {
    @EnvironmentObject var agentStore: AgentStore

    @State private var extensions: [IronclawExtension] = []
    @State private var isLoading = true

    private let ironclawAPI = IronclawAPI()

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if extensions.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No extensions installed.\nConnect an IronClaw agent to browse extensions.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(extensions) { ext in
                    ExtensionRow(extension: ext)
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Extensions")
        .background(Color(red: 0.05, green: 0.07, blue: 0.13))
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let token = agentStore.loadIronclawAuthToken(),
              !token.isEmpty,
              agentStore.ironclawSettings.hasUsableHostedEndpoint
        else { return }
        extensions = await ironclawAPI.fetchExtensions(
            settings: agentStore.ironclawSettings,
            authToken: token
        )
    }
}

private struct ExtensionRow: View {
    let `extension`: IronclawExtension

    private let cyanColor = Color(red: 0, green: 0.569, blue: 0.992)

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "puzzlepiece.extension")
                .font(.title2)
                .foregroundColor(`extension`.isInstalled ? cyanColor : .secondary)
                .frame(width: 32, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(`extension`.title)
                    .font(.body.weight(.medium))
                    .foregroundColor(.primary)

                if let desc = `extension`.description, !desc.isEmpty {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Text(`extension`.isInstalled ? "Active" : "Available")
                .font(.caption.weight(.semibold))
                .foregroundColor(`extension`.isInstalled ? cyanColor : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(`extension`.isInstalled
                              ? cyanColor.opacity(0.15)
                              : Color.secondary.opacity(0.1))
                )
        }
        .padding(.vertical, 4)
    }
}
