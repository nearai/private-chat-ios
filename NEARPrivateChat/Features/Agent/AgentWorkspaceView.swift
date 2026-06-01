import SwiftUI

struct AgentWorkspaceView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingAccountSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if chatStore.ironclawRemoteWorkstationAvailable {
                        AgentMissionControlPanel()
                            .environmentObject(chatStore)
                    } else {
                        AgentWorkspaceHeader()
                            .environmentObject(chatStore)
                        AgentWorkspaceSetupPanel {
                            showingAccountSettings = true
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 20)
                .frame(maxWidth: 640, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .background(Color.appBackground)
            .navigationTitle(chatStore.ironclawRemoteWorkstationAvailable ? "Agent" : "Connect Agent")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingAccountSettings) {
                AccountSettingsView(initialDeepLink: .ironclawAgent, onRunSetupAgain: {})
                    .environmentObject(chatStore)
                    .environmentObject(sessionStore)
            }
        }
        .platformLargeDetent()
    }
}

private struct AgentWorkspaceHeader: View {
    @EnvironmentObject private var chatStore: ChatStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "terminal")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 42, height: 42)
                    .background(Color.brandBlue.opacity(0.09), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

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
                StatusChip(title: chatStore.ironclawRemoteWorkstationAvailable ? "Hosted on" : "Hosted off", symbolName: "server.rack", isPrimary: chatStore.ironclawRemoteWorkstationAvailable)
                StatusChip(title: chatStore.ironclawToolNames.isEmpty ? "Shell + git" : "\(chatStore.ironclawToolNames.count) tools", symbolName: "terminal", isPrimary: chatStore.ironclawRemoteWorkstationAvailable)
                StatusChip(title: chatStore.ironclawTokenConfigured ? "Token saved" : "Token needed", symbolName: "key", isPrimary: false)
                StatusChip(title: "Phone controlled", symbolName: "iphone", isPrimary: false)
            }
        }
    }
}

private struct AgentWorkspaceSetupPanel: View {
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
            .tint(.brandBlue)
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

private struct AgentWorkspacePrinciples: View {
    private struct Principle: Identifiable {
        var id: String { title }
        let title: String
        let symbolName: String
        let detail: String
    }

    private let rows: [Principle] = [
        Principle(title: "Ask", symbolName: "text.badge.plus", detail: "If a repo, issue, or task brief is missing, the Agent asks before changing anything."),
        Principle(title: "Inspect", symbolName: "magnifyingglass", detail: "Hosted IronClaw checks files, git status, stack, and safe test commands first."),
        Principle(title: "Report", symbolName: "doc.text", detail: "Every run returns commands, changed files, tests, and remaining risk.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Run Contract")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(rows) { row in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: row.symbolName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.brandBlue)
                        .frame(width: 24, height: 24)
                        .background(Color.brandBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(row.detail)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

private struct AgentMissionControlPanel: View {
    @EnvironmentObject private var chatStore: ChatStore
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
            .shadow(color: Color.brandBlue.opacity(0.14), radius: 18, y: 8)

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
            ProjectFilesView()
                .environmentObject(chatStore)
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
                    Task { await chatStore.testIronclawWorkstation() }
                } label: {
                    Image(systemName: chatStore.isTestingIronclawWorkstation ? "arrow.triangle.2.circlepath" : "checkmark.seal")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.brandSky)
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(chatStore.isTestingIronclawWorkstation)
                .accessibilityLabel("Check Hosted IronClaw")
            }
        }
    }

    private var agentContextPanel: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: chatStore.selectedProject == nil ? "folder.badge.plus" : "folder")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.brandSky)
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(chatStore.selectedProject?.name ?? "No project selected")
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

            if chatStore.selectedProject != nil {
                Button {
                    showingProjectFiles = true
                } label: {
                    Label("Context", systemImage: "folder.badge.gearshape")
                        .font(.caption.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(Color.brandSky)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                            .foregroundStyle(Color.brandBlue)
                            .frame(width: 28, height: 28)
                            .background(Color.brandBlue.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

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
                        .frame(height: 34)
                        .background(Color.brandSky, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        guard let project = chatStore.selectedProject else {
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
        if chatStore.isTestingIronclawWorkstation {
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
        let tools = Set(chatStore.ironclawToolNames.map { $0.lowercased() })
        let workstationFallback = chatStore.ironclawRemoteWorkstationAvailable && tools.isEmpty
        func has(_ names: String...) -> Bool {
            workstationFallback || names.contains { tools.contains($0) }
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
            projectName: chatStore.selectedProject?.name
        )
    }

    private func launch() {
        if chatStore.ironclawRemoteWorkstationAvailable {
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

private struct IronclawAgentReadinessPanel: View {
    @EnvironmentObject private var chatStore: ChatStore

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: statusSymbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(statusColor)
                .frame(width: 28, height: 28)
                .background(statusColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Agent Stack")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(statusText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Button {
                Task { await chatStore.testIronclawWorkstation() }
            } label: {
                Image(systemName: chatStore.isTestingIronclawWorkstation ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 30, height: 30)
                    .background(Color.brandBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(chatStore.isTestingIronclawWorkstation || !chatStore.ironclawRemoteWorkstationAvailable)
            .accessibilityLabel("Check Hosted IronClaw tools")
        }
        .padding(12)
        .frame(maxWidth: 460, alignment: .leading)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }

    private var statusSymbol: String {
        if chatStore.isTestingIronclawWorkstation {
            return "arrow.triangle.2.circlepath"
        }
        if chatStore.ironclawLastVerifiedAt != nil {
            return "checkmark.seal.fill"
        }
        if !chatStore.ironclawToolNames.isEmpty {
            return "terminal.fill"
        }
        if chatStore.ironclawRemoteWorkstationAvailable {
            return "terminal"
        }
        return "exclamationmark.triangle.fill"
    }

    private var statusColor: Color {
        if chatStore.ironclawLastVerifiedAt != nil {
            return .green
        }
        if !chatStore.ironclawToolNames.isEmpty {
            return Color.brandBlue
        }
        if chatStore.ironclawRemoteWorkstationAvailable || chatStore.isTestingIronclawWorkstation {
            return Color.brandBlue
        }
        return .orange
    }

    private var statusText: String {
        if chatStore.isTestingIronclawWorkstation {
            return "Checking hosted shell and git"
        }
        if let verifiedAt = chatStore.ironclawLastVerifiedAt {
            if chatStore.ironclawToolNames.isEmpty {
                return "Shell and git checked at \(verifiedAt.formatted(date: .omitted, time: .shortened))"
            }
            return "\(chatStore.ironclawToolNames.count) tools: \(toolbeltSummary)"
        }
        if !chatStore.ironclawToolNames.isEmpty {
            return "\(chatStore.ironclawToolNames.count) tools available: \(toolbeltSummary)"
        }
        if chatStore.ironclawRemoteWorkstationAvailable {
            return "Hosted IronClaw connected; tools need a check"
        }
        return "Hosted IronClaw not connected"
    }

    private var toolbeltSummary: String {
        let available = Set(chatStore.ironclawToolNames.map { $0.lowercased() })
        let labels: [(String, String)] = [
            ("shell", "shell"),
            ("github", "github"),
            ("grep", "grep"),
            ("read_file", "files"),
            ("apply_patch", "patch"),
            ("nearai_web_search", "web")
        ]
        let present = labels.compactMap { name, label in
            available.contains(name) ? label : nil
        }
        return present.isEmpty ? "toolbelt checked" : present.joined(separator: " · ")
    }

}

private struct CapabilityRail: View {
    struct Item: Identifiable {
        var id: String { title }
        let symbolName: String
        let title: String
        let value: String
    }

    let items: [Item]

    var body: some View {
        ChipFlowLayout(spacing: 7, lineSpacing: 7) {
            ForEach(items) { item in
                HStack(spacing: 6) {
                    Image(systemName: item.symbolName)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.brandBlue)
                    Text("\(item.title): \(item.value)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.appPanelBackground, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.appBorder, lineWidth: 1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
