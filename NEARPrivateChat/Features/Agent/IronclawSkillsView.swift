import SwiftUI

struct IronclawSkillsView: View {
    @EnvironmentObject var agentStore: AgentStore

    @State private var skills: [IronclawSkill] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var selectedTab: SkillTab = .installed
    @State private var selectedSkill: IronclawSkill?
    @State private var isInstalling = false
    @State private var installError: String?

    private let ironclawAPI = IronclawAPI()
    private let cyanColor = Color(red: 0, green: 0.569, blue: 0.992)

    private enum SkillTab: String, CaseIterable {
        case installed = "Installed"
        case all = "All"
    }

    private var displayedSkills: [IronclawSkill] {
        let base: [IronclawSkill]
        switch selectedTab {
        case .installed:
            base = skills.filter { $0.isInstalled == true }
        case .all:
            base = skills
        }
        guard !searchText.isEmpty else { return base }
        let q = searchText.lowercased()
        return base.filter {
            $0.name.lowercased().contains(q) ||
            ($0.description?.lowercased().contains(q) == true) ||
            ($0.category?.lowercased().contains(q) == true)
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                searchBar
                tabPicker

                Group {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if displayedSkills.isEmpty {
                        emptyState
                    } else {
                        skillsList
                    }
                }
            }
            .navigationTitle("Skills")
            .background(Color(red: 0.05, green: 0.07, blue: 0.13))
        }
        .task { await load() }
        .sheet(item: $selectedSkill) { skill in
            SkillDetailSheet(
                skill: skill,
                isInstalling: $isInstalling,
                installError: $installError,
                onInstall: { await install(skill: $0) }
            )
            .environmentObject(agentStore)
        }
    }

    // MARK: - Subviews

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search skills", text: $searchText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var tabPicker: some View {
        Picker("Tab", selection: $selectedTab) {
            ForEach(SkillTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var skillsList: some View {
        List(displayedSkills) { skill in
            Button {
                selectedSkill = skill
            } label: {
                SkillRow(skill: skill, cyanColor: cyanColor)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(emptyStateMessage)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateMessage: String {
        if !searchText.isEmpty {
            return "No skills match \"\(searchText)\"."
        }
        switch selectedTab {
        case .installed:
            return "No skills installed.\nSwitch to All to browse available skills."
        case .all:
            return "No skills available.\nConnect an IronClaw agent to browse the marketplace."
        }
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let token = agentStore.loadIronclawAuthToken(),
              !token.isEmpty,
              agentStore.ironclawSettings.hasUsableHostedEndpoint
        else { return }
        skills = await ironclawAPI.fetchSkills(
            settings: agentStore.ironclawSettings,
            authToken: token
        )
    }

    private func install(skill: IronclawSkill) async {
        guard let token = agentStore.loadIronclawAuthToken(),
              !token.isEmpty,
              agentStore.ironclawSettings.hasUsableHostedEndpoint,
              let url = URL(string: agentStore.ironclawSettings.baseURL + "/api/webchat/v2/skills/install")
        else { return }

        isInstalling = true
        installError = nil
        defer { isInstalling = false }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONEncoder().encode(["name": skill.name])

        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                installError = "Install failed. Check the agent connection and try again."
                return
            }
            // Refresh list to reflect new installed state
            await load()
            selectedSkill = nil
        } catch {
            installError = "Install failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Skill Row

private struct SkillRow: View {
    let skill: IronclawSkill
    let cyanColor: Color

    private var isInstalled: Bool { skill.isInstalled == true }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: skill.icon)
                .font(.title2)
                .foregroundStyle(isInstalled ? cyanColor : .secondary)
                .frame(width: 32, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(skill.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)

                if let desc = skill.description, !desc.isEmpty {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if isInstalled {
                Text("Installed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(cyanColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(cyanColor.opacity(0.15))
                    )
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Skill Detail Sheet

private struct SkillDetailSheet: View {
    @EnvironmentObject var agentStore: AgentStore
    @Environment(\.dismiss) private var dismiss

    let skill: IronclawSkill
    @Binding var isInstalling: Bool
    @Binding var installError: String?
    let onInstall: (IronclawSkill) async -> Void

    private let cyanColor = Color(red: 0, green: 0.569, blue: 0.992)
    private var isInstalled: Bool { skill.isInstalled == true }

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: skill.icon)
                            .font(.largeTitle)
                            .foregroundStyle(isInstalled ? cyanColor : .secondary)
                            .frame(width: 48, height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(.secondarySystemBackground))
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(skill.title)
                                .font(.headline)
                            if let version = skill.version {
                                Text("v\(version)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let desc = skill.description, !desc.isEmpty {
                    Section("Description") {
                        Text(desc)
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                }

                Section("Details") {
                    if let author = skill.author, !author.isEmpty {
                        detailRow(label: "Author", value: author)
                    }
                    if let category = skill.category, !category.isEmpty {
                        detailRow(label: "Category", value: category)
                    }
                    detailRow(label: "Status", value: isInstalled ? "Installed" : "Available")
                }

                if let error = installError {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Color.red)
                    }
                }

                Section {
                    if isInstalling {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else if !isInstalled {
                        Button {
                            Task { await onInstall(skill) }
                        } label: {
                            HStack {
                                Spacer()
                                Text("Install Skill")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(cyanColor)
                                Spacer()
                            }
                        }
                    } else {
                        HStack {
                            Spacer()
                            Label("Installed", systemImage: "checkmark.circle.fill")
                                .font(.body.weight(.medium))
                                .foregroundStyle(cyanColor)
                            Spacer()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Skill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
}
