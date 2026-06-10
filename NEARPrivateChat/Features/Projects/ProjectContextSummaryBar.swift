import SwiftUI

/// "What the model sees" — one tappable row summarizing exactly which project
/// context attaches to sends (instructions, files, links, memory). Tapping
/// opens the full read-only preview so the user never has to guess what the
/// assistant was given.
struct ProjectContextSummaryBar: View {
    let project: ChatProject
    @State private var showingPreview = false

    var body: some View {
        Button {
            showingPreview = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "eye")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 28, height: 28)
                    .background(Color.brandBlue.opacity(0.09), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Model sees")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(summaryLine)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(10)
            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.appBorder, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("project.contextSummary")
        .accessibilityLabel("What the model sees: \(summaryLine)")
        .sheet(isPresented: $showingPreview) {
            ProjectContextPreviewSheet(project: project)
        }
    }

    private var summaryLine: String {
        var parts: [String] = []
        if !project.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("Instructions")
        }
        if !project.attachments.isEmpty {
            parts.append("\(project.attachments.count) file\(project.attachments.count == 1 ? "" : "s")")
        }
        if !project.links.isEmpty {
            parts.append("\(project.links.count) link\(project.links.count == 1 ? "" : "s")")
        }
        if !project.memorySummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("Memory")
        }
        let sharedNotes = project.notes.filter { !$0.isLocalOnly }
        if !sharedNotes.isEmpty {
            parts.append("\(sharedNotes.count) saved answer\(sharedNotes.count == 1 ? "" : "s")")
        }
        return parts.isEmpty ? "Nothing yet — add files or instructions" : parts.joined(separator: " · ")
    }
}

/// Read-only render of the project context exactly as sends attach it.
struct ProjectContextPreviewSheet: View {
    let project: ChatProject
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                let instructions = project.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
                if !instructions.isEmpty {
                    Section("Instructions — applies to every chat in this project") {
                        Text(instructions)
                            .font(.callout)
                    }
                }
                let memory = project.memorySummary.trimmingCharacters(in: .whitespacesAndNewlines)
                if !memory.isEmpty {
                    Section("Memory") {
                        Text(memory)
                            .font(.callout)
                    }
                }
                if !project.attachments.isEmpty {
                    Section("Files — readable text is sent when available") {
                        ForEach(project.attachments) { attachment in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(attachment.name)
                                    .font(.callout)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                if let size = attachment.displaySize {
                                    Text(size)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                if !project.links.isEmpty {
                    Section("Links") {
                        ForEach(project.links) { link in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(link.displayTitle)
                                    .font(.callout)
                                Text(link.urlString)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
                let sharedNotes = project.notes.filter { !$0.isLocalOnly }
                if !sharedNotes.isEmpty {
                    Section("Saved answers") {
                        ForEach(sharedNotes) { note in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(note.title)
                                    .font(.callout.weight(.medium))
                                Text(note.text)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }
                    }
                }
                let localNotes = project.notes.count - sharedNotes.count
                if localNotes > 0 {
                    Section {
                        Label("\(localNotes) local-only note\(localNotes == 1 ? "" : "s") stay on this device and are never sent to cloud or hosted routes.", systemImage: "iphone.and.arrow.forward")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Text("Source mode in the composer controls which of these attach to each message.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("What the model sees")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
