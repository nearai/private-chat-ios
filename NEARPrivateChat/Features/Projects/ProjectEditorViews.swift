import SwiftUI

struct NewProjectView: View {
    @EnvironmentObject private var projectStore: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var instructions = ""
    @State private var selectedPalette: ProjectPalette = .sky
    @State private var selectedIcon: ProjectIcon = .folder
    @State private var iconSearchText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ProjectIdentityPreview(
                        title: trimmedName.isEmpty ? "Untitled Project" : trimmedName,
                        subtitle: instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Sources, files, and instructions" : "Instructions ready",
                        symbolName: selectedIcon.symbolName,
                        tintColor: selectedPalette.tintColor,
                        backgroundColor: selectedPalette.backgroundColor
                    )

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Project Name")
                            .font(.headline)
                        TextField("Launch research", text: $name)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Identity")
                            .font(.headline)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(ProjectPalette.allCases) { palette in
                                    Button {
                                        selectedPalette = palette
                                    } label: {
                                        Circle()
                                            .fill(palette.tintColor)
                                            .frame(width: 30, height: 30)
                                            .overlay {
                                                Circle()
                                                    .stroke(selectedPalette == palette ? Color.primary : Color.clear, lineWidth: 2)
                                            }
                                            .padding(3)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("\(palette.label) project color")
                                }
                            }
                        }

                        TextField("Search icons", text: $iconSearchText)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .frame(height: 40)
                            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 8)], spacing: 8) {
                            ForEach(filteredProjectIcons) { icon in
                                Button {
                                    selectedIcon = icon
                                } label: {
                                    Image(systemName: icon.symbolName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(selectedIcon == icon ? selectedPalette.tintColor : .secondary)
                                        .frame(height: 42)
                                        .frame(maxWidth: .infinity)
                                        .background(
                                            selectedIcon == icon ? selectedPalette.backgroundColor : Color.appSecondaryBackground,
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(icon.label) project icon")
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Instructions")
                            .font(.headline)
                        TextField("How should the assistant use this Project?", text: $instructions, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(4...8)
                            .padding(12)
                            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))
                    }

                    Text("Sources, instructions, and saved outputs stay available to chats in this Project.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("New Project")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        projectStore.createProject(
                            named: name,
                            instructions: instructions,
                            iconName: selectedIcon.symbolName,
                            paletteName: selectedPalette.rawValue
                        )
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
        .platformMediumDetent()
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredProjectIcons: [ProjectIcon] {
        ProjectIcon.allCases.filter { $0.matches(iconSearchText) }
    }
}

struct EditProjectView: View {
    @EnvironmentObject private var projectStore: ProjectStore
    @Environment(\.dismiss) private var dismiss
    let project: ChatProject
    @State private var name: String
    @State private var instructions: String
    @State private var selectedPalette: ProjectPalette
    @State private var selectedIcon: ProjectIcon
    @State private var iconSearchText = ""

    init(project: ChatProject) {
        self.project = project
        _name = State(initialValue: project.name)
        _instructions = State(initialValue: project.instructions)
        _selectedPalette = State(initialValue: project.projectPalette)
        _selectedIcon = State(
            initialValue: ProjectIcon.allCases.first { $0.symbolName == project.projectIconName } ?? .folder
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ProjectIdentityPreview(
                        title: trimmedName.isEmpty ? project.name : trimmedName,
                        subtitle: projectSubtitle,
                        symbolName: selectedIcon.symbolName,
                        tintColor: selectedPalette.tintColor,
                        backgroundColor: selectedPalette.backgroundColor
                    )

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Project Name")
                            .font(.headline)
                        TextField("Project name", text: $name)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Color")
                            .font(.headline)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(ProjectPalette.allCases) { palette in
                                    Button {
                                        selectedPalette = palette
                                    } label: {
                                        Circle()
                                            .fill(palette.tintColor)
                                            .frame(width: 30, height: 30)
                                            .overlay {
                                                Circle()
                                                    .stroke(selectedPalette == palette ? Color.primary : Color.clear, lineWidth: 2)
                                            }
                                            .padding(3)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("\(palette.label) project color")
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Icon")
                            .font(.headline)
                        TextField("Search icons", text: $iconSearchText)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .frame(height: 40)
                            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 8)], spacing: 8) {
                            ForEach(filteredProjectIcons) { icon in
                                Button {
                                    selectedIcon = icon
                                } label: {
                                    Image(systemName: icon.symbolName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(selectedIcon == icon ? selectedPalette.tintColor : .secondary)
                                        .frame(height: 42)
                                        .frame(maxWidth: .infinity)
                                        .background(
                                            selectedIcon == icon ? selectedPalette.backgroundColor : Color.appSecondaryBackground,
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(icon.label) project icon")
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Instructions")
                            .font(.headline)
                        TextField("How should the assistant use this Project?", text: $instructions, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(4...8)
                            .padding(12)
                            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Edit Project")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        projectStore.updateProject(
                            project.id,
                            name: name,
                            iconName: selectedIcon.symbolName,
                            paletteName: selectedPalette.rawValue,
                            instructions: instructions
                        )
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
        .platformMediumDetent()
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredProjectIcons: [ProjectIcon] {
        ProjectIcon.allCases.filter { $0.matches(iconSearchText) }
    }

    private var projectSubtitle: String {
        var parts: [String] = []
        if !project.conversationIDs.isEmpty {
            parts.append("\(project.conversationIDs.count) chat\(project.conversationIDs.count == 1 ? "" : "s")")
        }
        let sourceCount = project.links.count + project.attachments.count
        if sourceCount > 0 {
            parts.append("\(sourceCount) source\(sourceCount == 1 ? "" : "s")")
        }
        return parts.isEmpty ? "Project identity and instructions" : parts.joined(separator: " / ")
    }
}

private struct ProjectIdentityPreview: View {
    let title: String
    let subtitle: String
    let symbolName: String
    let tintColor: Color
    let backgroundColor: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tintColor)
                .frame(width: 42, height: 42)
                .background(backgroundColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.border, lineWidth: 1)
        }
    }
}
