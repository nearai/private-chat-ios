import SwiftUI
import UniformTypeIdentifiers

struct ProjectFilesView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingFileImporter = false
    @State private var projectInstructions = ""
    @State private var projectMemory = ""
    @State private var projectLinkTitle = ""
    @State private var projectLinkURL = ""
    @State private var showingAddLinkForm = false
    @State private var showingFileLibrary = false
    @State private var selectedTab: ProjectContextTab = .sources
    @State private var previewFile: RemoteFileInfo?
    @State private var pendingLinkDelete: ProjectLink?
    @State private var pendingNoteDelete: ProjectNote?
    @State private var pendingAttachmentDelete: ChatAttachment?
    @State private var pendingRemoteFileDelete: RemoteFileInfo?

    private enum ProjectContextTab: String, CaseIterable, Identifiable {
        case sources = "Sources"
        case instructions = "Instructions"
        case notes = "Notes"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
                headerSection

                Section {
                    Picker("Project Context", selection: $selectedTab) {
                        ForEach(ProjectContextTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Project context section")
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                selectedTabContent
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Project Context")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    projectSourceAddMenu
                }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.pdf, .plainText, .text, .commaSeparatedText, .json, .data],
                allowsMultipleSelection: true
            ) { result in
                if case let .success(urls) = result {
                    Task {
                        for url in urls.prefix(12) {
                            await chatStore.addProjectAttachment(from: url)
                        }
                    }
                }
            }
            .sheet(item: $previewFile) { file in
                RemoteFilePreviewView(file: file)
                    .environmentObject(chatStore)
            }
            .confirmationDialog(
                "Remove this source?",
                isPresented: pendingLinkDeletePresented,
                titleVisibility: .visible
            ) {
                Button("Remove Source", role: .destructive) {
                    if let pendingLinkDelete {
                        chatStore.deleteProjectLink(pendingLinkDelete)
                    }
                    pendingLinkDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingLinkDelete = nil
                }
            }
            .confirmationDialog(
                "Remove this note?",
                isPresented: pendingNoteDeletePresented,
                titleVisibility: .visible
            ) {
                Button("Remove Note", role: .destructive) {
                    if let pendingNoteDelete {
                        chatStore.deleteProjectNote(pendingNoteDelete)
                    }
                    pendingNoteDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingNoteDelete = nil
                }
            }
            .confirmationDialog(
                "Remove this file from the project?",
                isPresented: pendingAttachmentDeletePresented,
                titleVisibility: .visible
            ) {
                Button("Remove File", role: .destructive) {
                    if let pendingAttachmentDelete {
                        chatStore.removeProjectAttachment(pendingAttachmentDelete)
                    }
                    pendingAttachmentDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingAttachmentDelete = nil
                }
            }
            .confirmationDialog(
                "Delete this private file?",
                isPresented: pendingRemoteFileDeletePresented,
                titleVisibility: .visible
            ) {
                Button("Delete File", role: .destructive) {
                    if let pendingRemoteFileDelete {
                        Task { await chatStore.deleteRemoteFile(pendingRemoteFileDelete) }
                    }
                    pendingRemoteFileDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingRemoteFileDelete = nil
                }
            } message: {
                Text("This removes the uploaded file from your private file library.")
            }
        }
        .platformLargeDetent()
        .onAppear {
            syncProjectFields()
        }
        .onChange(of: chatStore.selectedProject?.id) {
            syncProjectFields()
        }
        .task {
            await chatStore.refreshRemoteFiles(showErrors: false)
        }
    }

    @ViewBuilder
    private var projectSourceAddMenu: some View {
        if selectedTab == .sources {
            Menu {
                Button {
                    showingAddLinkForm = true
                } label: {
                    Label("Add Link", systemImage: "link.badge.plus")
                }
                Button {
                    showingFileImporter = true
                } label: {
                    Label("Add Files", systemImage: "paperclip")
                }
                Button {
                    showingFileLibrary.toggle()
                    if showingFileLibrary, chatStore.remoteFiles.isEmpty {
                        Task { await chatStore.refreshRemoteFiles(showErrors: false) }
                    }
                } label: {
                    Label(showingFileLibrary ? "Hide Uploaded Files" : "Browse Uploaded Files", systemImage: "tray.full")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityLabel("Add project source")
        }
    }

    private var pendingLinkDeletePresented: Binding<Bool> {
        Binding(
            get: { pendingLinkDelete != nil },
            set: { if !$0 { pendingLinkDelete = nil } }
        )
    }

    private var pendingNoteDeletePresented: Binding<Bool> {
        Binding(
            get: { pendingNoteDelete != nil },
            set: { if !$0 { pendingNoteDelete = nil } }
        )
    }

    private var pendingAttachmentDeletePresented: Binding<Bool> {
        Binding(
            get: { pendingAttachmentDelete != nil },
            set: { if !$0 { pendingAttachmentDelete = nil } }
        )
    }

    private var pendingRemoteFileDeletePresented: Binding<Bool> {
        Binding(
            get: { pendingRemoteFileDelete != nil },
            set: { if !$0 { pendingRemoteFileDelete = nil } }
        )
    }

    private var headerSection: some View {
        Section {
            ProjectContextHeroCard(
                title: chatStore.selectedProject?.name ?? "Project",
                symbolName: chatStore.selectedProject?.projectIconName ?? ProjectIcon.folder.symbolName,
                tintColor: chatStore.selectedProject?.tintColor ?? Color.trustFreshAccent,
                createdAt: chatStore.selectedProject?.createdAt,
                chats: chatStore.selectedProject?.conversationIDs.count ?? 0,
                sources: projectSourceCount,
                notes: chatStore.selectedProjectNotes.count,
                hasInstructions: !chatStore.selectedProjectInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            .listRowBackground(Color.clear)

            if !projectKnowledgeItems.isEmpty {
                ProjectKnowledgeSnapshotCard(items: projectKnowledgeItems)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 10, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
    }

    private var projectKnowledgeItems: [ProjectKnowledgeSnapshotCard.Item] {
        guard chatStore.selectedProject != nil else { return [] }
        var items: [ProjectKnowledgeSnapshotCard.Item] = []
        let instructions = chatStore.selectedProjectInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let memory = chatStore.selectedProjectMemorySummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !instructions.isEmpty {
            items.append(ProjectKnowledgeSnapshotCard.Item(symbolName: "text.alignleft", title: "Instructions", detail: Self.compactPreview(instructions)))
        }
        if !memory.isEmpty {
            items.append(ProjectKnowledgeSnapshotCard.Item(symbolName: "brain.head.profile", title: "Memory", detail: Self.compactPreview(memory)))
        }
        if !chatStore.selectedProjectLinks.isEmpty || !chatStore.selectedProjectAttachments.isEmpty {
            let linkHosts = chatStore.selectedProjectLinks
                .compactMap(\.host)
                .prefix(2)
                .joined(separator: ", ")
            let fileNames = chatStore.selectedProjectAttachments
                .map(\.name)
                .prefix(2)
                .joined(separator: ", ")
            let sourceParts = [linkHosts, fileNames].filter { !$0.isEmpty }
            let fallback = "\(projectSourceCount) saved source\(projectSourceCount == 1 ? "" : "s")"
            items.append(ProjectKnowledgeSnapshotCard.Item(symbolName: "folder.badge.gearshape", title: "Sources", detail: sourceParts.isEmpty ? fallback : sourceParts.joined(separator: " / ")))
        }
        if let note = chatStore.selectedProjectNotes.first {
            items.append(ProjectKnowledgeSnapshotCard.Item(symbolName: "bookmark", title: "Latest note", detail: Self.compactPreview(note.title.isEmpty ? note.text : note.title)))
        }
        return Array(items.prefix(3))
    }

    private static func compactPreview(_ text: String) -> String {
        let collapsed = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let clipped = String(collapsed.prefix(104))
        return collapsed.count > clipped.count ? "\(clipped)..." : clipped
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .sources:
            sourcesSections
        case .instructions:
            guidanceSections
        case .notes:
            savedSections
        }
    }

    @ViewBuilder
    private var sourcesSections: some View {
        Section(projectSourceCount == 0 ? "Sources" : "Sources (\(projectSourceCount))") {
            if showingAddLinkForm {
                addLinkForm
            }

            if projectSourceCount == 0 {
                ProjectContextEmptyActionRow(
                    title: "No sources yet",
                    message: "Tap + to add a link or file so project chats can use the same context.",
                    systemImage: "link.badge.plus"
                ) {
                    Button {
                        showingAddLinkForm = true
                    } label: {
                        Label("Add Link", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandBlue)

                    Button {
                        showingFileImporter = true
                    } label: {
                        Label("Add Files", systemImage: "paperclip")
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
            } else {
                ForEach(chatStore.selectedProjectLinks) { link in
                    ProjectLinkRow(link: link) {
                        pendingLinkDelete = link
                    }
                }

                ForEach(chatStore.selectedProjectAttachments) { attachment in
                    ProjectAttachmentRow(
                        attachment: attachment,
                        freshnessText: attachmentFreshnessText(for: attachment)
                    ) {
                        pendingAttachmentDelete = attachment
                    }
                }
            }
        }

        if showingFileLibrary {
            fileLibrarySections
        }
    }

    private var addLinkForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Source title", text: $projectLinkTitle)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            TextField("https://example.com/report", text: $projectLinkURL)
                .textFieldStyle(.plain)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack {
                Text("Saved links stay with this project.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Cancel") {
                    resetProjectLinkForm()
                    showingAddLinkForm = false
                }
                .buttonStyle(.borderless)
                Button("Add") {
                    chatStore.addSelectedProjectLink(title: projectLinkTitle, url: projectLinkURL)
                    resetProjectLinkForm()
                    showingAddLinkForm = false
                }
                .buttonStyle(.bordered)
                .disabled(projectLinkURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var fileLibrarySections: some View {
        Section("Uploaded Files") {
            if chatStore.isLoadingRemoteFiles && chatStore.remoteFiles.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading private files")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 18)
            } else if chatStore.remoteFiles.isEmpty {
                ProjectContextEmptyActionRow(
                    title: "No uploaded files",
                    message: "Tap + to upload a file into this project. Files up to 10 MB are supported.",
                    systemImage: "tray"
                ) {
                    Button {
                        showingFileImporter = true
                    } label: {
                        Label("Add Files", systemImage: "paperclip")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandBlue)

                    Button {
                        Task { await chatStore.refreshRemoteFiles(showErrors: true) }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(chatStore.isLoadingRemoteFiles)
                }
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
            } else {
                ForEach(chatStore.remoteFiles) { file in
                    RemoteFileRow(
                        file: file,
                        onPreview: { previewFile = file },
                        onAttach: { chatStore.attachRemoteFileToPrompt(file) },
                        onAddToProject: { chatStore.addRemoteFileToSelectedProject(file) },
                        onDelete: {
                            pendingRemoteFileDelete = file
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var guidanceSections: some View {
        Section("Instructions") {
            TextField("How should the assistant handle this project?", text: $projectInstructions, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(4...8)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack {
                Text("Used with every request in this project.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Save") {
                    chatStore.updateSelectedProjectInstructions(projectInstructions)
                }
                .buttonStyle(.bordered)
                .disabled(!instructionsChanged)
            }
        }

        Section("Project Notes") {
            TextField("What should the assistant remember about this project?", text: $projectMemory, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(4...10)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack {
                Text("Saved locally and injected into every project request.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Save") {
                    chatStore.updateSelectedProjectMemory(projectMemory)
                }
                .buttonStyle(.bordered)
                .disabled(!memoryChanged)
            }
        }
    }

    @ViewBuilder
    private var savedSections: some View {
        Section("Notes") {
            if chatStore.selectedProjectNotes.isEmpty {
                ProjectContextEmptyActionRow(
                    title: "No notes yet",
                    message: "Save useful assistant answers from chat to keep them with this project.",
                    systemImage: "bookmark"
                ) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Back to Chat", systemImage: "bubble.left")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandBlue)
                }
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
            } else {
                ForEach(chatStore.selectedProjectNotes) { note in
                    ProjectNoteRow(note: note) {
                        pendingNoteDelete = note
                    }
                }
            }
        }
    }

    private var projectSourceCount: Int {
        chatStore.selectedProjectLinks.count + chatStore.selectedProjectAttachments.count
    }

    private var instructionsChanged: Bool {
        projectInstructions.trimmingCharacters(in: .whitespacesAndNewlines) !=
            chatStore.selectedProjectInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var memoryChanged: Bool {
        projectMemory.trimmingCharacters(in: .whitespacesAndNewlines) !=
            chatStore.selectedProjectMemorySummary.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func syncProjectFields() {
        projectInstructions = chatStore.selectedProjectInstructions
        projectMemory = chatStore.selectedProjectMemorySummary
    }

    private func resetProjectLinkForm() {
        projectLinkTitle = ""
        projectLinkURL = ""
    }

    private func attachmentFreshnessText(for attachment: ChatAttachment) -> String? {
        guard let remoteFile = chatStore.remoteFiles.first(where: { $0.id == attachment.id }) else {
            return nil
        }
        return ProjectContextFreshness.label(for: remoteFile.createdAt, prefix: "Added")
    }

}

private struct ProjectKnowledgeSnapshotCard: View {
    struct Item: Identifiable, Hashable {
        let id = UUID()
        let symbolName: String
        let title: String
        let detail: String
    }

    let items: [Item]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("What this project knows", systemImage: "sparkles")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textSecondary)
                Spacer(minLength: 0)
            }

            VStack(spacing: 8) {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: item.symbolName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.brandBlue)
                            .frame(width: 24, height: 24)
                            .background(Color.brandBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(item.detail)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }
}

private struct ProjectContextHeroCard: View {
    let title: String
    let symbolName: String
    let tintColor: Color
    let createdAt: Date?
    let chats: Int
    let sources: Int
    let notes: Int
    let hasInstructions: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: symbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tintColor)
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(metadataText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.66))
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                HStack(spacing: 5) {
                    Circle()
                        .fill(isActive ? Color.brandSky : Color.brandGrey)
                        .frame(width: 7, height: 7)
                    Text(isActive ? "Active" : "Ready")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.76))
                        .lineLimit(1)
                }
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(.white.opacity(0.12), in: Capsule())
            }

            if metrics.isEmpty {
                ProjectContextHeroMetric(title: "Add sources", symbolName: "plus.circle", active: false)
            } else {
                HStack(spacing: 7) {
                    ForEach(metrics) { metric in
                        ProjectContextHeroMetric(title: metric.title, symbolName: metric.symbolName, active: true)
                    }
                }
            }
        }
        .padding(14)
        .background {
            CommandCardBackground(cornerRadius: 8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.11), lineWidth: 1)
        }
        .shadow(color: Color.brandBlue.opacity(0.14), radius: 18, y: 8)
    }

    private func countLabel(_ count: Int, singular: String) -> String {
        "\(count) \(singular)\(count == 1 ? "" : "s")"
    }

    private var isActive: Bool {
        sources > 0 || notes > 0 || hasInstructions
    }

    private var metadataText: String {
        var parts: [String] = []
        if let createdAt {
            parts.append("Created \(ProjectContextFreshness.relativeDateText(for: createdAt))")
        }
        if chats > 0 {
            parts.append(countLabel(chats, singular: "chat"))
        }
        if parts.isEmpty {
            return "Sources, instructions, and notes for this workspace"
        }
        return parts.joined(separator: " / ")
    }

    private var metrics: [HeroMetric] {
        var items: [HeroMetric] = []
        if sources > 0 {
            items.append(HeroMetric(title: countLabel(sources, singular: "source"), symbolName: "link"))
        }
        if hasInstructions {
            items.append(HeroMetric(title: "Instructions", symbolName: "text.alignleft"))
        }
        if notes > 0 {
            items.append(HeroMetric(title: countLabel(notes, singular: "note"), symbolName: "bookmark"))
        }
        return items
    }

    private struct HeroMetric: Identifiable {
        let id = UUID()
        let title: String
        let symbolName: String
    }
}

private struct ProjectContextHeroMetric: View {
    let title: String
    let symbolName: String
    let active: Bool

    var body: some View {
        Label(title, systemImage: symbolName)
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(active ? Color.brandSky : .white.opacity(0.64))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background(.white.opacity(active ? 0.14 : 0.09), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private enum ProjectContextFreshness {
    static func label(for timeInterval: TimeInterval?, prefix: String) -> String? {
        guard let timeInterval else { return nil }
        return label(for: Date(timeIntervalSince1970: timeInterval), prefix: prefix)
    }

    static func label(for date: Date, prefix: String) -> String {
        "\(prefix) \(relativeDateText(for: date))"
    }

    static func relativeDateText(for date: Date) -> String {
        let elapsed = max(0, Date().timeIntervalSince(date))
        if elapsed < 60 {
            return "just now"
        }
        if elapsed < 3600 {
            return "\(Int(elapsed / 60))m ago"
        }
        if elapsed < 86_400 {
            return "\(Int(elapsed / 3600))h ago"
        }
        if elapsed < 604_800 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

private struct ProjectContextActionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.brandBlue)
                .frame(width: 28, height: 28)
                .background(Color.brandBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct ProjectContextEmptyActionRow<Actions: View>: View {
    let title: String
    let message: String
    let systemImage: String
    let actions: Actions

    init(
        title: String,
        message: String,
        systemImage: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.brandBlue)
                .frame(width: 38, height: 38)
                .background(Color.brandBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                actions
            }
            .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

private struct ProjectAttachmentRow: View {
    let attachment: ChatAttachment
    let freshnessText: String?
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: attachment.systemImageName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.brandBlue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove File")
        }
        .padding(.vertical, 3)
    }

    private var detailText: String {
        var parts = [attachment.displayKind]
        if let displaySize = attachment.displaySize {
            parts.append(displaySize)
        }
        if let freshnessText {
            parts.append(freshnessText)
        }
        return parts.joined(separator: " / ")
    }
}

private struct ProjectNoteRow: View {
    let note: ProjectNote
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bookmark.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.brandBlue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(note.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(note.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(note.createdAt, style: .date)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                Clipboard.copy(note.text)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Copy Note")

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete Note")
        }
        .padding(.vertical, 3)
    }
}

private struct ProjectLinkRow: View {
    @Environment(\.openURL) private var openURL
    let link: ProjectLink
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "link")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.brandBlue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(link.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(link.urlString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)

            if let url = link.url {
                Button {
                    openURL(url)
                } label: {
                    Image(systemName: "safari")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Open Link")
            }

            Button {
                Clipboard.copy(link.urlString)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Copy Link")

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete Link")
        }
        .padding(.vertical, 3)
    }

    private var detailText: String {
        let host = link.host ?? link.urlString
        return "\(host) / \(ProjectContextFreshness.label(for: link.createdAt, prefix: "Added"))"
    }
}

private struct RemoteFileRow: View {
    let file: RemoteFileInfo
    let onPreview: () -> Void
    let onAttach: () -> Void
    let onAddToProject: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: file.systemImageName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.brandBlue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(file.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let freshnessText = ProjectContextFreshness.label(for: file.createdAt, prefix: "Uploaded") {
                    Text(freshnessText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Button(action: onPreview) {
                Image(systemName: "eye")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Preview File")

            Menu {
                Button(action: onAttach) {
                    Label("Attach to Prompt", systemImage: "paperclip")
                }
                Button(action: onAddToProject) {
                    Label("Add to Project", systemImage: "folder.badge.plus")
                }
                Button(action: onPreview) {
                    Label("Preview", systemImage: "eye")
                }
                Button(role: .destructive, action: onDelete) {
                    Label("Delete from NEAR", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("File Actions")
        }
        .padding(.vertical, 3)
    }

    private var detailText: String {
        if let displaySize = file.displaySize {
            return "\(file.displayKind) / \(displaySize)"
        }
        return file.displayKind
    }
}

private struct RemoteFilePreviewView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    let file: RemoteFileInfo

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    previewBody
                }
                .padding(16)
            }
            .background(Color.appBackground)
            .navigationTitle("File Preview")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            chatStore.attachRemoteFileToPrompt(file)
                        } label: {
                            Label("Attach to Prompt", systemImage: "paperclip")
                        }
                        Button {
                            chatStore.addRemoteFileToSelectedProject(file)
                        } label: {
                            Label("Add to Project", systemImage: "folder.badge.plus")
                        }
                        if let preview = chatStore.remoteFilePreview, preview.id == file.id {
                            Button {
                                Clipboard.copy(preview.text)
                            } label: {
                                Label("Copy Preview", systemImage: "doc.on.doc")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("File Preview Actions")
                }
            }
            .task {
                await chatStore.previewRemoteFile(file)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: file.systemImageName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.brandBlue)
                .frame(width: 40, height: 40)
                .background(Color.brandBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(file.name)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            Text(headerDetail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var previewBody: some View {
        if chatStore.isLoadingRemoteFilePreview {
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading preview")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 28)
        } else if let preview = chatStore.remoteFilePreview, preview.id == file.id {
            VStack(alignment: .leading, spacing: 10) {
                if preview.isTruncated {
                    Label("Showing the first \(ByteCountFormatter.string(fromByteCount: Int64(preview.byteCount), countStyle: .file)) preview window.", systemImage: "scissors")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(preview.text)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        } else {
            ContentUnavailableView("No preview available", systemImage: "doc.text.magnifyingglass")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        }
    }

    private var headerDetail: String {
        var parts = [file.displayKind]
        if let displaySize = file.displaySize {
            parts.append(displaySize)
        }
        if let freshnessText = ProjectContextFreshness.label(for: file.createdAt, prefix: "Uploaded") {
            parts.append(freshnessText)
        }
        return parts.joined(separator: " · ")
    }
}

struct ArchivedChatsView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var showingArchiveExporter = false
    @State private var archiveDocument = ConversationExportDocument()

    private var archived: [ConversationSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return chatStore.archivedConversations }
        return chatStore.archivedConversations.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
                $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    private var archivedJSON: String {
        guard let data = try? JSONEncoder().encode(chatStore.archivedConversations),
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
              let pretty = String(data: prettyData, encoding: .utf8) else {
            return "[]"
        }
        return pretty
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "archivebox")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.brandBlue)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(chatStore.archivedConversations.count) archived conversations")
                                .font(.headline)
                            Text("Restore chats when you need them back, or delete them permanently.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Conversations") {
                    if archived.isEmpty {
                        ContentUnavailableView("No archived conversations", systemImage: "archivebox")
                            .frame(maxWidth: .infinity)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(archived) { conversation in
                            HStack(spacing: 10) {
                                Image(systemName: "bubble.left")
                                    .foregroundStyle(Color.brandBlue)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(conversation.title)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                    if let createdAt = conversation.createdAt {
                                        Text(Date(timeIntervalSince1970: createdAt), style: .date)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer(minLength: 0)

                                Button {
                                    chatStore.unarchiveConversation(conversation)
                                } label: {
                                    Image(systemName: "arrow.uturn.backward")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Unarchive")

                                Button(role: .destructive) {
                                    chatStore.requestDeleteConversation(conversation)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Delete")
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }

                if !chatStore.archivedConversations.isEmpty {
                    Section {
                        Button {
                            chatStore.unarchiveAllConversations()
                        } label: {
                            Label("Unarchive All", systemImage: "arrow.uturn.backward.circle")
                        }

                        Button {
                            Clipboard.copy(archivedJSON)
                            chatStore.bannerMessage = "Archived JSON copied."
                        } label: {
                            Label("Copy Archive JSON", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            archiveDocument = ConversationExportDocument(data: Data(archivedJSON.utf8))
                            showingArchiveExporter = true
                        } label: {
                            Label("Export Archive JSON", systemImage: "square.and.arrow.up.on.square")
                        }
                    }
                }
            }
            .navigationTitle("Archived")
            .platformInlineNavigationTitle()
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search archived chats")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onChange(of: chatStore.openSelectedConversationToken) { _, token in
                if token != nil {
                    dismiss()
                }
            }
            .fileExporter(
                isPresented: $showingArchiveExporter,
                document: archiveDocument,
                contentType: .json,
                defaultFilename: archiveFilename
            ) { result in
                switch result {
                case .success:
                    chatStore.bannerMessage = "Archive JSON exported."
                case let .failure(error):
                    chatStore.bannerMessage = error.localizedDescription
                }
            }
        }
    }

    private var archiveFilename: String {
        let date = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return "near-private-chat-archive-\(date).json"
    }
}
