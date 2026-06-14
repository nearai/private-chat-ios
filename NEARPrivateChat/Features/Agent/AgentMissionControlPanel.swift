import SwiftUI

struct AgentMissionControlPanel: View {
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var agentStore: AgentStore
    @EnvironmentObject private var projectStore: ProjectStore
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var missionBrief = ""
    @State private var showingProjectFiles = false

    private struct ToolbeltCapability: Identifiable {
        var id: String { title }
        let title: String
        let symbolName: String
        let isAvailable: Bool
    }

    private var availableCapabilities: [ToolbeltCapability] {
        toolbeltCapabilities.filter(\.isAvailable)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 14) {
                launcherHeader
                quickStartRow
                agentComposer
                if !trimmedMissionBrief.isEmpty {
                    agentSkillPreview
                }
                agentContextPanel
            }
            .padding(14)
            .background {
                CommandCardBackground()
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.11), lineWidth: 1)
            }
            .shadow(color: Color.brandAccent.opacity(0.14), radius: 18, y: 8)

        }
        .frame(maxWidth: 520, alignment: .leading)
        .onAppear {
            #if DEBUG
            if DemoCapture.isEnabled, missionBrief.isEmpty {
                missionBrief = "Use the attached project plan and latest nearai/ironclaw PRs to update the plan."
            }
            #endif
        }
        .sheet(isPresented: $showingProjectFiles) {
            ProjectFilesView(
                projectContextRoutePreview: { chatStore.projectContextRoutePreview },
                addProjectAttachment: { url in await chatStore.addProjectAttachment(from: url) },
                removeProjectAttachment: { attachment in chatStore.removeProjectAttachment(attachment) },
                onOpenConversation: { conversation in
                    chatStore.selectConversation(conversation)
                },
                onStagePrompt: { prompt in
                    chatStore.draft = prompt
                    chatStore.bannerMessage = "Project prompt ready."
                }
            )
            .environmentObject(projectStore)
        }
    }

    private var launcherHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                Image(systemName: "terminal")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.brandBlack)
                    .frame(width: 42, height: 42)
                    .background(Color.brandSky, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Agent")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(agentReadinessTitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.66))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Spacer(minLength: 0)

                Button {
                    Task { await agentStore.testIronclawWorkstation() }
                } label: {
                    Image(systemName: agentStore.isTestingIronclawWorkstation ? "arrow.triangle.2.circlepath" : "checkmark.seal")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.brandSky)
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(agentStore.isTestingIronclawWorkstation)
                .accessibilityLabel("Check Hosted IronClaw")
            }
        }
    }

    private var agentContextPanel: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: projectStore.selectedProject == nil ? "folder.badge.plus" : "folder")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.brandSky)
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(projectStore.selectedProject?.name ?? "No project selected")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(agentContextLine)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if projectStore.selectedProject != nil {
                Button {
                    showingProjectFiles = true
                } label: {
                    Label("Context", systemImage: "folder.badge.gearshape")
                        .font(.caption.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(Color.brandSky)
                        .padding(.horizontal, 10)
                        .frame(height: 44)
                        .background(.white.opacity(0.12), in: RoundedRectangle.app(AppRadius.pill))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Project context")
            }
        }
        .padding(12)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }

    private var agentComposer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if trimmedMissionBrief.isEmpty, let setupMissionSuggestion {
                Button {
                    missionBrief = setupMissionSuggestion.prompt
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "sparkles.rectangle.stack")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.brandAccent)
                            .frame(width: 28, height: 28)
                            .background(Color.brandAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(setupMissionSuggestion.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(setupMissionSuggestion.detail)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(setupMissionSuggestion.prompt)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.primaryAction)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "arrow.down.left")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.primaryAction)
                            .padding(.top, 2)
                    }
                    .padding(12)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(setupMissionSuggestion.title)
                .accessibilityHint("Fills the agent brief from your saved setup without sending.")
            }

            TextField("What should the Agent do?", text: $missionBrief, axis: .vertical)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.sentences)
                .lineLimit(4...8)
                .font(.body)
                .frame(minHeight: 112, alignment: .topLeading)
                .accessibilityLabel("Agent mission brief")

            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles")
                        .font(.caption.weight(.bold))
                    Text("Auto tools")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(Color.brandSky)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(Color.brandSky.opacity(0.16), in: Capsule())

                Spacer(minLength: 0)

                Button {
                    launch()
                } label: {
                    Label("Review & Run", systemImage: "arrow.up")
                        .font(.caption.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(Color.brandBlack)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(Color.brandSky, in: RoundedRectangle.app(AppRadius.pill))
                }
                .buttonStyle(.plain)
                .disabled(trimmedMissionBrief.isEmpty)
                .accessibilityLabel("Review and run Agent")
            }
        }
        .padding(14)
        .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
    }

    private var agentSkillPreview: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.brandSky)
                Text("Likely skills")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            ChipFlowLayout(spacing: 7, lineSpacing: 7) {
                ForEach(detectedSkills) { skill in
                    Label(skill.title, systemImage: skill.symbolName)
                        .font(.caption2.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }

    private var quickStartRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(skillShelfTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.54))
                Spacer(minLength: 0)
                Text(skillShelfDetail)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.42))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(featuredSkills) { skill in
                        Button {
                            applySkill(skill)
                        } label: {
                            AgentSkillLaunchCard(skill: skill, isSuggested: detectedSkills.contains(skill))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Use \(skill.title) skill")
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private var featuredSkills: [IronclawSkillProfile] {
        if trimmedMissionBrief.isEmpty, !setupSkills.isEmpty {
            return Array(setupSkills.prefix(5))
        }
        let limit = trimmedMissionBrief.isEmpty ? 5 : 4
        return IronclawSkillCatalog.suggestedSkills(for: missionBrief, limit: limit)
    }

    private var setupProfile: UserSetupProfile? {
        guard let accountID = sessionStore.setupAccountID else { return nil }
        let storedProfile = UserSetupStorage.load(for: accountID) ?? .defaults
        return chatStore.setupProfileSnapshot(storedProfile)
    }

    private var setupMissionSuggestion: SetupAgentMissionSuggestion? {
        setupProfile?.agentMissionSuggestion
    }

    private var setupSkills: [IronclawSkillProfile] {
        setupProfile?.setupSkillSuggestions ?? []
    }

    private var isUsingSetupSkills: Bool {
        trimmedMissionBrief.isEmpty && !setupSkills.isEmpty
    }

    private var skillShelfTitle: String {
        if isUsingSetupSkills {
            return "Start from your setup"
        }
        return trimmedMissionBrief.isEmpty ? "Start from a skill" : "Sharpen this mission"
    }

    private var skillShelfDetail: String {
        isUsingSetupSkills ? "Saved defaults" : "Templates stay editable"
    }

    private var agentContextLine: String {
        guard let project = projectStore.selectedProject else {
            return "Add a repo, issue, PR, source, or file in the brief."
        }

        var parts: [String] = []
        if !project.links.isEmpty {
            parts.append(project.links.count == 1 ? "1 source" : "\(project.links.count) sources")
        }
        if !project.attachments.isEmpty {
            parts.append(project.attachments.count == 1 ? "1 file" : "\(project.attachments.count) files")
        }
        if !project.notes.isEmpty {
            parts.append(project.notes.count == 1 ? "1 saved note" : "\(project.notes.count) saved notes")
        }
        if let primarySource = project.links.first {
            parts.append(primarySource.host ?? primarySource.displayTitle)
        }
        return parts.isEmpty ? "\(project.name) has no saved context yet." : "\(project.name) · \(parts.joined(separator: " · "))"
    }

    private var agentReadinessTitle: String {
        if agentStore.isTestingIronclawWorkstation {
            return "Checking Hosted IronClaw"
        }
        if availableCapabilities.isEmpty {
            return "Describe the outcome; the app will pick the route"
        }

        let priority = ["Shell", "Git", "Web", "Patch", "GitHub"]
        let names = priority.filter { name in
            availableCapabilities.contains(where: { $0.title == name })
        }
        return "Ready: \(names.prefix(3).joined(separator: " + "))"
    }

    private var detectedSkills: [IronclawSkillProfile] {
        if isUsingSetupSkills {
            return Array(setupSkills.prefix(4))
        }
        return IronclawSkillCatalog.suggestedSkills(for: missionBrief, limit: 4)
    }

    private var trimmedMissionBrief: String {
        missionBrief.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var toolbeltCapabilities: [ToolbeltCapability] {
        let tools = Set(agentStore.ironclawToolNames.map { $0.lowercased() })
        func has(_ names: String...) -> Bool {
            names.contains { tools.contains($0) }
        }
        return [
            ToolbeltCapability(title: "Shell", symbolName: "terminal", isAvailable: has("shell")),
            ToolbeltCapability(title: "Git", symbolName: "arrow.triangle.branch", isAvailable: has("git", "shell")),
            ToolbeltCapability(title: "Patch", symbolName: "wrench.and.screwdriver", isAvailable: has("apply_patch")),
            ToolbeltCapability(title: "Web", symbolName: "globe", isAvailable: has("nearai_web_search")),
            ToolbeltCapability(title: "GitHub", symbolName: "chevron.left.forwardslash.chevron.right", isAvailable: has("github"))
        ]
    }

    private func applySkill(_ skill: IronclawSkillProfile) {
            missionBrief = skill.missionPrompt(
                seed: trimmedMissionBrief,
            projectName: projectStore.selectedProject?.name
        )
    }

    private func launch() {
        if agentStore.ironclawRemoteWorkstationAvailable {
            chatStore.selectModel(ModelOption.ironclawModelID)
        } else if chatStore.selectedModelOption?.isIronclawModel != true {
            chatStore.selectModel(ModelOption.ironclawMobileModelID)
        }
        chatStore.sourceMode = .auto
        chatStore.researchModeEnabled = false
        chatStore.draft = "Agent mission: \(trimmedMissionBrief)"
        chatStore.sendDraft()
        dismiss()
    }
}

private struct AgentSkillLaunchCard: View {
    let skill: IronclawSkillProfile
    let isSuggested: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: skill.symbolName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.brandSky)
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Spacer(minLength: 0)

                if isSuggested {
                    Text("Suggested")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.brandSky)
                }
            }

            Text(skill.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(skill.summary)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.64))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Text("Use skill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.88))
        }
        .padding(12)
        .frame(width: 182, alignment: .leading)
        .frame(minHeight: 118, alignment: .topLeading)
        .background(.white.opacity(isSuggested ? 0.15 : 0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSuggested ? Color.brandSky.opacity(0.58) : .white.opacity(0.10), lineWidth: 1)
        }
    }
}
