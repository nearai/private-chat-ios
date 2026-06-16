import SwiftUI

struct IronclawChannelsView: View {
    @EnvironmentObject var agentStore: AgentStore

    @State private var channels: [IronclawConnectableChannel] = []
    @State private var isLoading = true
    @State private var selectedChannel: IronclawConnectableChannel?

    private let ironclawAPI = IronclawAPI()

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if channels.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No integration channels available on this agent.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(channels) { channel in
                    Button {
                        selectedChannel = channel
                    } label: {
                        ChannelRow(channel: channel)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Channels")
        .background(Color(red: 0.05, green: 0.07, blue: 0.13))
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $selectedChannel) { channel in
            ChannelDetailSheet(channel: channel)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let token = agentStore.loadIronclawAuthToken(),
              !token.isEmpty,
              agentStore.ironclawSettings.hasUsableHostedEndpoint
        else { return }
        channels = await ironclawAPI.fetchConnectableChannels(
            settings: agentStore.ironclawSettings,
            authToken: token
        )
    }
}

// MARK: - Channel Row

private struct ChannelRow: View {
    let channel: IronclawConnectableChannel

    private let connectedColor = Color(red: 0.18, green: 0.70, blue: 0.36)

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: channel.icon)
                .font(.title2)
                .foregroundColor(channel.isConnected == true ? channel.accentColor : .secondary)
                .frame(width: 32, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(channel.title)
                    .font(.body.weight(.medium))
                    .foregroundColor(.primary)

                if let desc = channel.description, !desc.isEmpty {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            let connected = channel.isConnected == true
            Text(connected ? "Connected" : "Available")
                .font(.caption.weight(.semibold))
                .foregroundColor(connected ? connectedColor : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(connected
                              ? connectedColor.opacity(0.15)
                              : Color.secondary.opacity(0.1))
                )
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Channel Detail Sheet

private struct ChannelDetailSheet: View {
    let channel: IronclawConnectableChannel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: channel.icon)
                            .font(.largeTitle)
                            .foregroundColor(channel.accentColor)
                            .frame(width: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(channel.title)
                                .font(.headline)
                            if let type = channel.channelType {
                                Text(type.capitalized)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let desc = channel.description, !desc.isEmpty {
                    Section("About") {
                        Text(desc)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Status") {
                    HStack {
                        Text("Connection")
                        Spacer()
                        let connected = channel.isConnected == true
                        Text(connected ? "Connected" : "Not connected")
                            .foregroundColor(connected
                                             ? Color(red: 0.18, green: 0.70, blue: 0.36)
                                             : .secondary)
                    }
                    HStack {
                        Text("Channel ID")
                        Spacer()
                        Text(channel.id)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }

                if channel.isConnected != true {
                    Section("Setup") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Connect \(channel.title)")
                                .font(.subheadline.weight(.semibold))
                            Text("To connect \(channel.title), ask your IronClaw agent to run the channel setup flow, or configure it from the IronClaw web UI.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.05, green: 0.07, blue: 0.13).ignoresSafeArea())
            .navigationTitle(channel.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
