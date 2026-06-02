import SwiftUI

// MARK: - Project action shelf

enum ProjectActionKind: String, CaseIterable, Identifiable {
    case createPrompt
    case findActions
    case makeTracker
    case askAgent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .createPrompt:
            return "Start conversation"
        case .findActions:
            return "Find next actions"
        case .makeTracker:
            return "Make tracker"
        case .askAgent:
            return "Run Agent"
        }
    }

    var subtitle: String {
        switch self {
        case .createPrompt:
            return "Shape this Project"
        case .findActions:
            return "Tasks, risks, decisions"
        case .makeTracker:
            return "Briefings and reminders"
        case .askAgent:
            return "Preview a run"
        }
    }

    var symbolName: String {
        switch self {
        case .createPrompt:
            return "text.badge.plus"
        case .findActions:
            return "checklist"
        case .makeTracker:
            return "calendar.badge.clock"
        case .askAgent:
            return "point.3.connected.trianglepath.dotted"
        }
    }
}

enum ProjectActionPromptFactory {
    static func prompt(for action: ProjectActionKind, projectName: String?) -> String {
        let subject = projectSubject(projectName)
        switch action {
        case .createPrompt:
            return """
            Help me turn \(subject) into a useful working project. Ask one question at a time until you know what should be remembered, what should be tracked, what should become a recurring briefing, what belongs on my calendar, and what actions should be created. Preview the resulting project instructions and starter commands before saving anything.
            """
        case .findActions:
            return """
            Review \(subject) and turn the context into actionable next moves. Identify trackers, briefings, reminders, calendar-worthy events, tasks, decisions, risks, open questions, and anything I am likely to care about. For each item include why it matters, missing details, structured fields where known (source, date, time, recurrence, timezone, attendees, confidence), and the exact app command that would create or stage it. If useful, emit a near-widget action_plan with missing_fields. Preview first.
            """
        case .makeTracker:
            return """
            Use \(subject) to propose recurring trackers, scheduled briefings, reminders, or calendar invites. Preserve concrete names, quantities, dates, cadences, timing, and caveats from the source context. For each proposal include the trigger or schedule, source, notification behavior, structured fields, missing_fields, confidence, and exact app command. Emit a near-widget action_plan when there is more than one candidate. Do not create anything until I confirm.
            """
        case .askAgent:
            return """
            Use \(subject) to design an agent run. Show what project context or files would be sent, the route and capabilities needed, the steps the agent would take, risks or irreversible actions, and the expected output. Wait for my confirmation before running the agent.
            """
        }
    }

    private static func projectSubject(_ projectName: String?) -> String {
        let trimmed = projectName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "this project" }
        return "the \(trimmed) project"
    }
}

struct ProjectActionShelf: View {
    let projectName: String?
    let hasContext: Bool
    let onSelect: (ProjectActionKind) -> Void

    private var actions: [ProjectActionKind] {
        hasContext ? [.findActions, .makeTracker, .askAgent] : ProjectActionKind.allCases
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(actions) { action in
                Button {
                    onSelect(action)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: action.symbolName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.actionPrimary)
                            .frame(width: 30, height: 30)
                            .background(Color.actionTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                            Text(action.subtitle)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.textTertiary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.appBorder, lineWidth: 0.5)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(action.title), \(action.subtitle)")
            }
        }
    }
}

// MARK: - Section label

struct ProjectSectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.textSecondary)
    }
}

// MARK: - Route/source preview

struct ProjectContextRoutePreviewRow: View {
    let preview: ProjectContextRoutePreview

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: preview.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(preview.usesAttentionStyle ? Color.proofStale : Color.actionPrimary)
                .frame(width: 26, height: 26)
                .background(
                    (preview.usesAttentionStyle ? Color.proofStale.opacity(0.12) : Color.actionTint),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(preview.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = preview.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - File pill

struct ProjectFilePill: View {
    let title: String
    let subtitle: String
    var symbolName: String = "doc.text"
    let action: () -> Void
    let removeAction: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.actionTint)
                        Image(systemName: symbolName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.actionPrimary)
                    }
                    .frame(width: 28, height: 28)

                    Spacer(minLength: 0)

                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 24, height: 24)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.footnote)
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.caption2)
                        .fontWeight(.regular)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(width: 132, height: 116, alignment: .topLeading)
            .padding(12)
            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.appBorder, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                removeAction()
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        .accessibilityLabel("\(title), \(subtitle). Tap to stage an action prompt.")
        .accessibilityAction(named: "Remove", removeAction)
    }
}

// MARK: - Add file pill

struct ProjectAddFilePill: View {
    var title: String = "Add file"
    var symbolName: String = "plus"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbolName)
                    .font(.system(size: 22, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
            }
                .foregroundStyle(Color.actionPrimary)
                .frame(width: 132, height: 116)
                .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.appBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

// MARK: - Instructions card

struct ProjectInstructionsCard: View {
    let text: String
    let isPlaceholder: Bool
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    (
                        Text(text)
                            .foregroundStyle(isPlaceholder ? Color.textSecondary : Color.primary)
                        + Text(" ")
                        + Text("Edit")
                            .foregroundStyle(Color.actionPrimary)
                            .font(.subheadline.weight(.medium))
                    )
                    .font(.subheadline)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
                    .padding(.top, 3)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.appBorder, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Project memory row

struct ProjectMemoryRow: View {
    let title: String
    let text: String
    let symbolName: String
    let showsDivider: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.actionPrimary)
                    .frame(width: 28, height: 28)
                    .background(Color.actionTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsDivider {
                Rectangle()
                    .fill(Color.appHairline)
                    .frame(height: 0.5)
                    .padding(.leading, 54)
            }
        }
    }
}

struct ProjectNoteRow: View {
    let note: ProjectNote
    let showsDivider: Bool
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(alignment: .top, spacing: 10) {
                Button(action: onOpen) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "note.text")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.actionPrimary)
                            .frame(width: 28, height: 28)
                            .background(Color.actionTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(note.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.primary)
                                    .lineLimit(1)
                                ProjectNoteStatusBadge(note: note)
                            }
                            Text(note.text)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Menu {
                    Button {
                        onOpen()
                    } label: {
                        Label("View Details", systemImage: "doc.text.magnifyingglass")
                    }
                    Button {
                        onEdit()
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel("Note actions")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsDivider {
                Rectangle()
                    .fill(Color.appHairline)
                    .frame(height: 0.5)
                    .padding(.leading, 54)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct ProjectNoteStatusBadge: View {
    let note: ProjectNote

    var body: some View {
        Label(note.projectContextStatusTitle, systemImage: note.projectContextStatusSymbolName)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(note.isLocalOnly ? Color.proofStale : Color.actionPrimary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                (note.isLocalOnly ? Color.proofStale.opacity(0.12) : Color.actionTint),
                in: Capsule()
            )
            .accessibilityLabel(note.projectContextStatusDescription)
    }
}

// MARK: - Chat row

struct ProjectChatRow: View {
    let conversation: ConversationSummary
    let showsDivider: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .bottom) {
                HStack(alignment: .center, spacing: 12) {
                    Text(conversation.title)
                        .font(.body)
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(relativeTimeText)
                        .font(.footnote)
                        .fontWeight(.regular)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(minHeight: 60)

                if showsDivider {
                    Rectangle()
                        .fill(Color.appHairline)
                        .frame(height: 0.5)
                        .padding(.leading, 14)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var relativeTimeText: String {
        guard let createdAt = conversation.createdAt else { return "Recent" }
        return ProjectContextFreshness.relativeDateText(for: Date(timeIntervalSince1970: createdAt))
    }
}

// MARK: - Instructions editor sheet

struct ProjectInstructionsEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var instructions: String
    @Binding var memory: String
    let instructionsChanged: Bool
    let memoryChanged: Bool
    let saveAction: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Instructions") {
                    TextField("How should the assistant handle this project?", text: $instructions, axis: .vertical)
                        .lineLimit(4...8)
                }
                Section("Notes") {
                    TextField("What should the assistant remember?", text: $memory, axis: .vertical)
                        .lineLimit(4...8)
                }
            }
            .navigationTitle("Instructions")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAction()
                        dismiss()
                    }
                    .disabled(!instructionsChanged && !memoryChanged)
                }
            }
        }
        .platformMediumDetent()
    }
}

struct ProjectLinkEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var title: String
    @Binding var url: String
    let saveAction: () -> Void

    private var canSave: Bool {
        !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Link") {
                    TextField("Title", text: $title)
                    TextField("https://example.com/source", text: $url)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Add Link")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        saveAction()
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .platformMediumDetent()
    }
}

struct ProjectNoteDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let note: ProjectNote
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(note.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        ProjectNoteStatusBadge(note: note)
                    }

                    Text(note.text)
                        .font(.body)
                        .foregroundStyle(Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let sourceMessageID = note.sourceMessageID {
                        Label("Saved from message \(sourceMessageID)", systemImage: "text.bubble")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(2)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.appBackground)
            .navigationTitle("Project Note")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            onEdit()
                            dismiss()
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Note actions")
                }
            }
        }
        .platformMediumDetent()
    }
}

struct ProjectNoteEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var title: String
    @Binding var text: String
    @Binding var isLocalOnly: Bool
    var navigationTitle = "Add Note"
    var confirmationTitle = "Add"
    let saveAction: () -> Void

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Note") {
                    TextField("Title", text: $title)
                    TextField("Decision, reminder, context, or next action", text: $text, axis: .vertical)
                        .lineLimit(4...8)
                }

                Section {
                    Toggle("Keep on this phone", isOn: $isLocalOnly)
                } footer: {
                    Text("Local-only notes are omitted from Hosted IronClaw and cloud routes.")
                }
            }
            .navigationTitle(navigationTitle)
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmationTitle) {
                        saveAction()
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .platformMediumDetent()
    }
}

// MARK: - Project context freshness helpers

enum ProjectContextFreshness {
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
