import SwiftUI

/// Horizontal chip row for files the hosted IronClaw agent produced during a run.
/// Each chip shows the file name and optional size; tapping downloads and presents a share sheet.
struct ProjectFileChipsView: View {
    let files: [IronclawProjectFile]
    let threadID: String
    let settings: IronclawSettings
    let authToken: String?
    let ironclawAPI: IronclawAPI

    @State private var downloading: String? = nil
    @State private var shareItem: ShareItem? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(files) { file in
                    ProjectFileChip(
                        file: file,
                        isDownloading: downloading == file.id
                    ) {
                        Task { await download(file) }
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
        }
    }

    private func download(_ file: IronclawProjectFile) async {
        guard downloading == nil, !threadID.isEmpty else { return }
        downloading = file.id
        defer { downloading = nil }

        var settingsWithThread = settings
        settingsWithThread.threadID = threadID

        guard let data = await ironclawAPI.downloadProjectFile(
            threadID: threadID,
            path: file.path,
            settings: settingsWithThread,
            authToken: authToken
        ) else { return }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(file.displayName)
        do {
            try data.write(to: tempURL, options: .atomic)
            shareItem = ShareItem(url: tempURL)
        } catch {}
    }
}

private struct ProjectFileChip: View {
    let file: IronclawProjectFile
    let isDownloading: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                if isDownloading {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Color.accentColor)
                } else {
                    Image(systemName: "doc.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                Text(file.displayName)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let size = file.size, size > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.secondary.opacity(0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDownloading)
    }
}

private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
