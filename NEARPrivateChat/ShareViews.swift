import SwiftUI

private enum SharePublicLinkExpiry: String, CaseIterable, Identifiable {
    case manual = "Manual disable"
    case sevenDays = "7 days"
    case thirtyDays = "30 days"

    var id: String { rawValue }

    var isAvailable: Bool {
        self == .manual
    }
}

struct ShareConversationView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    let conversation: ConversationSummary
    @State private var isWorking = false
    @State private var inviteTarget = ""
    @State private var organizationPattern = ""
    @State private var selectedGroupID = ""
    @State private var groupName = ""
    @State private var groupMembers = ""
    @State private var editingShareGroup: ShareGroupInfo?
    @State private var permission: ShareGrantPermission = .read
    @State private var grantMode: ShareGrantMode = .people
    @State private var pendingDeleteID: String?
    @State private var publicLinkExpiry: SharePublicLinkExpiry = .manual
    @State private var showingPublicLinkPreview = false
    @State private var showingDisablePublicLinkConfirmation = false
    @State private var pendingSensitiveShareGrant: SensitiveShareGrant?

    private enum ShareGrantMode: String, CaseIterable, Identifiable {
        case people = "People"
        case group = "Group"
        case organization = "Organization"

        var id: String { rawValue }

        var symbolName: String {
            switch self {
            case .people: "person.badge.plus"
            case .group: "person.3"
            case .organization: "building.2"
            }
        }
    }

    private enum ShareGrantPermission: String, CaseIterable, Identifiable {
        case read = "Read"
        case write = "Write"

        var id: String { rawValue }
        var apiValue: String { rawValue.lowercased() }
    }

    private enum SensitiveShareGrant {
        case people
        case group
        case organization

        var label: String {
            switch self {
            case .people: "people"
            case .group: "this group"
            case .organization: "the organization"
            }
        }
    }

    private var publicURL: URL? {
        chatStore.publicURL(for: conversation)
    }

    private var publicShareEnabled: Bool {
        chatStore.shareInfo?.publicShare != nil
    }

    private var accessShares: [ConversationShareInfo] {
        chatStore.shareInfo?.shares.filter { !$0.isPublic } ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    shareHeader
                    publicLinkSection
                    proofExportSection
                    grantAccessSection
                    accessListSection

                    if chatStore.isLoadingShareInfo || isWorking {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Updating share settings")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
                .frame(maxWidth: 560, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            .background(Color.appBackground)
            .navigationTitle("Share")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await chatStore.loadShares(for: conversation)
                await chatStore.refreshShareGroups(showErrors: false)
                ensureSelectedGroup()
            }
            .onChange(of: chatStore.shareGroups) {
                ensureSelectedGroup()
            }
            .sheet(isPresented: $showingPublicLinkPreview) {
                PublicLinkPreviewView(
                    conversation: conversation,
                    messageCount: chatStore.messages.count,
                    sourceCount: publicLinkSourceCount,
                    expiry: publicLinkExpiry,
                    attestationStatus: chatStore.currentAttestationStatus,
                    isWorking: isWorking,
                    onConfirm: {
                        await enablePublicShare()
                    }
                )
            }
            .confirmationDialog(
                "Disable the public link?",
                isPresented: $showingDisablePublicLinkConfirmation,
                titleVisibility: .visible
            ) {
                Button("Disable Public Link", role: .destructive) {
                    Task { await disablePublicShare() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("People with the public URL will lose read-only access.")
            }
            .confirmationDialog(
                "Confirm shared access",
                isPresented: Binding(
                    get: { pendingSensitiveShareGrant != nil },
                    set: { if !$0 { pendingSensitiveShareGrant = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Grant Access", role: permission == .write ? .destructive : nil) {
                    guard let grant = pendingSensitiveShareGrant else { return }
                    pendingSensitiveShareGrant = nil
                    Task { await performShareGrant(grant) }
                }
                Button("Cancel", role: .cancel) {
                    pendingSensitiveShareGrant = nil
                }
            } message: {
                Text(shareGrantConfirmationMessage)
            }
        }
        .platformLargeDetent()
    }

    private var shareHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "link")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.brandBlue)
                .frame(width: 44, height: 44)
                .background(Color.appBlueTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(chatStore.shareInfo?.canShare == false ? "View existing access." : "Invite people, organizations, or publish a read-only link.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }

    private var publicLinkSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Public Link", systemImage: "globe")
                    .font(.footnote.weight(.semibold))
                Spacer()
                Text(publicShareEnabled ? "On" : "Off")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(publicShareEnabled ? Color.brandBlue : .secondary)
            }

            Menu {
                ForEach(SharePublicLinkExpiry.allCases) { expiry in
                    Button {
                        publicLinkExpiry = expiry
                    } label: {
                        Label(expiry.rawValue, systemImage: publicLinkExpiry == expiry ? "checkmark" : "clock")
                    }
                    .disabled(!expiry.isAvailable)
                }
            } label: {
                Label("Expiry: \(publicLinkExpiry.rawValue)", systemImage: "clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(publicShareEnabled)

            if publicShareEnabled, let publicURL {
                Text(publicURL.absoluteString)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack(spacing: 8) {
                    Button {
                        Clipboard.copy(publicURL.absoluteString)
                        chatStore.bannerMessage = "Link copied."
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandBlue)

                    Button(role: .destructive) {
                        showingDisablePublicLinkConfirmation = true
                    } label: {
                        Label("Disable", systemImage: "link.badge.minus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Button {
                    showingPublicLinkPreview = true
                } label: {
                    Label("Review Public Link", systemImage: "eye")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandBlue)
                .controlSize(.large)
                .disabled(chatStore.shareInfo?.canShare == false || isWorking)
            }

            Button {
                grantMode = .people
            } label: {
                Label("Invite People", systemImage: "person.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(chatStore.shareInfo?.canShare == false || isWorking)
        }
        .padding(12)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }

    private var proofExportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.trustVerified)
                    .frame(width: 34, height: 34)
                    .background(Color.trustVerified.opacity(0.13), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Verified export")
                        .font(.footnote.weight(.semibold))
                    Text("Share the transcript with a signed proof bundle so recipients can verify model, route, nonce, and gateway.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Button {
                    chatStore.bannerMessage = "Verified JSON export prepared."
                } label: {
                    Label("Verified JSON", systemImage: "checkmark.shield")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.trustVerified)

                Button {
                    chatStore.bannerMessage = "Proof JSON prepared."
                } label: {
                    Label("Proof JSON", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(Color.trustVerified.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.trustVerified.opacity(0.20), lineWidth: 1)
        }
    }

    private var grantAccessSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("Grant Access", systemImage: grantMode.symbolName)
                    .font(.footnote.weight(.semibold))
                Spacer()
                Picker("Permission", selection: $permission) {
                    ForEach(ShareGrantPermission.allCases) { permission in
                        Text(permission.rawValue).tag(permission)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }

            Picker("Target", selection: $grantMode) {
                ForEach(ShareGrantMode.allCases) { mode in
                    Label(mode.rawValue, systemImage: mode.symbolName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            switch grantMode {
            case .people:
                TextField("email@company.com, alice.near", text: $inviteTarget, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .lineLimit(2...4)
                    .textFieldStyle(.plain)
                    .padding(11)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button {
                    requestShareGrant(.people)
                } label: {
                    Label("Invite", systemImage: "paperplane")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandBlue)
                .disabled(inviteTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking || chatStore.shareInfo?.canShare == false)
            case .group:
                groupAccessControls
            case .organization:
                TextField("*@near.org", text: $organizationPattern)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textFieldStyle(.plain)
                    .padding(11)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button {
                    requestShareGrant(.organization)
                } label: {
                    Label("Share Organization", systemImage: "building.2.crop.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandBlue)
                .disabled(organizationPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking || chatStore.shareInfo?.canShare == false)
            }
        }
        .padding(12)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }

    private var accessListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("People With Access", systemImage: "person.2")
                    .font(.footnote.weight(.semibold))
                Spacer()
                Text("\(accessShares.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if accessShares.isEmpty {
                Text("Only you can access this conversation unless the public link is enabled.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(accessShares) { share in
                        accessRow(share)
                        if share.id != accessShares.last?.id {
                            Divider()
                                .padding(.leading, 42)
                        }
                    }
                }
                .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(12)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }

    private var groupAccessControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if chatStore.isLoadingShareGroups {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading groups")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            } else if chatStore.shareGroups.isEmpty {
                Text("Create a reusable group for frequent collaborators.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                Picker("Share Group", selection: $selectedGroupID) {
                    ForEach(chatStore.shareGroups) { group in
                        Text("\(group.name) · \(group.members.count)").tag(group.id)
                    }
                }
                .pickerStyle(.menu)

                Button {
                    requestShareGrant(.group)
                } label: {
                    Label("Share Group", systemImage: "person.3")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandBlue)
                .disabled(selectedGroupID.isEmpty || isWorking || chatStore.shareInfo?.canShare == false)

                VStack(spacing: 0) {
                    ForEach(chatStore.shareGroups) { group in
                        HStack(spacing: 10) {
                            Image(systemName: "person.3")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.brandBlue)
                                .frame(width: 28, height: 28)
                                .background(Color.appBlueTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.name)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Text(shareGroupSubtitle(group))
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Button {
                                beginEditingShareGroup(group)
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.plain)
                            .disabled(isWorking)
                            .accessibilityLabel("Edit Share Group")
                            Button(role: .destructive) {
                                Task { await chatStore.deleteShareGroup(group) }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .disabled(isWorking)
                            .accessibilityLabel("Delete Share Group")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        if group.id != chatStore.shareGroups.last?.id {
                            Divider()
                                .padding(.leading, 42)
                        }
                    }
                }
                .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Divider()

            if let editingShareGroup {
                HStack(spacing: 8) {
                    Label("Editing \(editingShareGroup.name)", systemImage: "pencil")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.brandBlue)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button("Cancel") {
                        cancelShareGroupEditing()
                    }
                    .font(.caption.weight(.semibold))
                    .disabled(isWorking)
                }
                .padding(.horizontal, 2)
            }

            TextField("Group name", text: $groupName)
                .textFieldStyle(.plain)
                .padding(11)
                .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            TextField("email@company.com, alice.near", text: $groupMembers, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .lineLimit(2...4)
                .textFieldStyle(.plain)
                .padding(11)
                .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button {
                Task { await saveGroup() }
            } label: {
                Label(editingShareGroup == nil ? "Create Group" : "Save Group", systemImage: editingShareGroup == nil ? "plus" : "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(
                groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                groupMembers.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                isWorking ||
                chatStore.shareInfo?.canShare == false
            )
        }
    }

    private func accessRow(_ share: ConversationShareInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: shareSymbol(share))
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.brandBlue)
                .frame(width: 30, height: 30)
                .background(Color.appBlueTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(shareDisplayName(share))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(shareSubtitle(share))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button(role: .destructive) {
                Task { await removeAccess(share) }
            } label: {
                if pendingDeleteID == share.id {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "minus.circle")
                        .font(.body.weight(.semibold))
                }
            }
            .buttonStyle(.plain)
            .disabled(isWorking || pendingDeleteID != nil || chatStore.shareInfo?.canShare == false)
            .accessibilityLabel("Remove access")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }

    private func enablePublicShare() async {
        isWorking = true
        defer { isWorking = false }
        if let url = await chatStore.enablePublicShare(for: conversation) {
            Clipboard.copy(url.absoluteString)
        }
    }

    private func disablePublicShare() async {
        isWorking = true
        defer { isWorking = false }
        await chatStore.disablePublicShare(for: conversation)
    }

    private var shareGrantConfirmationMessage: String {
        let target = pendingSensitiveShareGrant?.label ?? "this target"
        if permission == .write {
            return "Write access lets \(target) add messages to this conversation. Confirm this is intended."
        }
        return "Organization sharing can grant access broadly. Confirm the domain and permission before continuing."
    }

    private func requestShareGrant(_ grant: SensitiveShareGrant) {
        if permission == .write || grant == .organization {
            pendingSensitiveShareGrant = grant
            return
        }
        Task { await performShareGrant(grant) }
    }

    private func performShareGrant(_ grant: SensitiveShareGrant) async {
        switch grant {
        case .people:
            await grantPeopleAccess()
        case .group:
            await grantSelectedGroupAccess()
        case .organization:
            await grantOrganizationAccess()
        }
    }

    private func grantPeopleAccess() async {
        isWorking = true
        defer { isWorking = false }
        await chatStore.grantDirectShare(
            rawRecipients: inviteTarget,
            permission: permission.apiValue,
            conversation: conversation
        )
        inviteTarget = ""
    }

    private func grantOrganizationAccess() async {
        isWorking = true
        defer { isWorking = false }
        await chatStore.grantOrganizationShare(
            emailPattern: organizationPattern,
            permission: permission.apiValue,
            conversation: conversation
        )
        organizationPattern = ""
    }

    private func saveGroup() async {
        isWorking = true
        defer { isWorking = false }
        if let editingShareGroup {
            await chatStore.updateShareGroup(editingShareGroup, name: groupName, rawMembers: groupMembers)
            cancelShareGroupEditing()
            ensureSelectedGroup()
            return
        }

        await chatStore.createShareGroup(name: groupName, rawMembers: groupMembers)
        groupName = ""
        groupMembers = ""
        ensureSelectedGroup()
    }

    private func grantSelectedGroupAccess() async {
        isWorking = true
        defer { isWorking = false }
        await chatStore.grantGroupShare(
            groupID: selectedGroupID,
            permission: permission.apiValue,
            conversation: conversation
        )
    }

    private func removeAccess(_ share: ConversationShareInfo) async {
        pendingDeleteID = share.id
        isWorking = true
        defer {
            pendingDeleteID = nil
            isWorking = false
        }
        await chatStore.removeConversationShare(share, conversation: conversation)
    }

    private func shareDisplayName(_ share: ConversationShareInfo) -> String {
        if let recipient = share.recipient {
            return recipient.value
        }
        if let pattern = share.orgEmailPattern {
            return pattern
        }
        if let groupID = share.groupID {
            return chatStore.shareGroups.first(where: { $0.id == groupID })?.name ?? "Group \(groupID)"
        }
        return share.shareType.capitalized
    }

    private func shareSubtitle(_ share: ConversationShareInfo) -> String {
        let permission = share.permission == "write" ? "Can write" : "Can read"
        switch share.shareType {
        case "direct":
            return "\(permission) · Direct"
        case "organization":
            return "\(permission) · Organization"
        case "group":
            return "\(permission) · Group"
        default:
            return permission
        }
    }

    private func shareSymbol(_ share: ConversationShareInfo) -> String {
        switch share.shareType {
        case "direct":
            return share.recipient?.kind == "near_account" ? "hexagon" : "envelope"
        case "organization":
            return "building.2"
        case "group":
            return "person.3"
        default:
            return "person"
        }
    }

    private func ensureSelectedGroup() {
        if selectedGroupID.isEmpty || !chatStore.shareGroups.contains(where: { $0.id == selectedGroupID }) {
            selectedGroupID = chatStore.shareGroups.first?.id ?? ""
        }
    }

    private func beginEditingShareGroup(_ group: ShareGroupInfo) {
        editingShareGroup = group
        groupName = group.name
        groupMembers = group.members.map(\.shareSheetFieldValue).joined(separator: ", ")
    }

    private func cancelShareGroupEditing() {
        editingShareGroup = nil
        groupName = ""
        groupMembers = ""
    }

    private func shareGroupSubtitle(_ group: ShareGroupInfo) -> String {
        let count = "\(group.members.count) member\(group.members.count == 1 ? "" : "s")"
        let preview = group.members.prefix(2).map(\.displayName).joined(separator: ", ")
        guard !preview.isEmpty else { return count }
        return "\(count) · \(preview)\(group.members.count > 2 ? ", +" : "")"
    }

    private var publicLinkSourceCount: Int {
        chatStore.activeProjectContextAttachments.count + chatStore.activeProjectContextLinks.count
    }
}

private extension ShareInviteRecipient {
    var displayName: String {
        value
    }

    var shareSheetFieldValue: String {
        value
    }
}

private struct PublicLinkPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let conversation: ConversationSummary
    let messageCount: Int
    let sourceCount: Int
    let expiry: SharePublicLinkExpiry
    let attestationStatus: AttestationStatus
    let isWorking: Bool
    let onConfirm: () async -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "globe")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Color.primaryAction)
                                .frame(width: 42, height: 42)
                                .background(Color.primaryAction.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(conversation.title)
                                    .font(.headline)
                                    .lineLimit(2)
                                Text("Anyone with the URL can read this conversation.")
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(Color.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        AttestationStatusBadge(status: attestationStatus, modelID: nil)
                    }
                    .padding(.vertical, 4)
                }

                Section("Preview") {
                    SharePreviewRow(title: "Permission", value: "Read-only", symbolName: "eye")
                    SharePreviewRow(title: "Messages", value: "\(messageCount)", symbolName: "bubble.left.and.bubble.right")
                    SharePreviewRow(title: "Sources", value: sourceCount == 0 ? "None attached" : "\(sourceCount)", symbolName: "link")
                    SharePreviewRow(title: "Expiry", value: expiry.rawValue, symbolName: "clock")
                    SharePreviewRow(title: "Account metadata", value: "Owner identity is not added to the link preview.", symbolName: "person.crop.circle.badge.xmark")
                }

                Section {
                    Button {
                        Task {
                            await onConfirm()
                            dismiss()
                        }
                    } label: {
                        Label("Create Public Link", systemImage: "link.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.primaryAction)
                    .disabled(isWorking)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.surface)
            .navigationTitle("Public Link Preview")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .platformMediumDetent()
    }
}

private struct SharePreviewRow: View {
    let title: String
    let value: String
    let symbolName: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbolName)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.primaryAction)
                .frame(width: 28, height: 28)
                .background(Color.primaryAction.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(value)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
    }
}

struct ShareGroupsView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var groupName = ""
    @State private var groupMembers = ""
    @State private var editingShareGroup: ShareGroupInfo?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "person.3")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.brandBlue)
                            .frame(width: 42, height: 42)
                            .background(Color.appBlueTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Share Groups")
                                .font(.headline)
                            Text("Reusable collaborator sets for conversation sharing.")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Groups") {
                    if chatStore.isLoadingShareGroups {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading groups")
                                .foregroundStyle(.secondary)
                        }
                    } else if chatStore.shareGroups.isEmpty {
                        ContentUnavailableView("No share groups", systemImage: "person.3")
                            .frame(maxWidth: .infinity)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(chatStore.shareGroups) { group in
                            HStack(spacing: 10) {
                                Image(systemName: "person.3")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color.brandBlue)
                                    .frame(width: 30, height: 30)
                                    .background(Color.appBlueTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.name)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    Text(shareGroupSubtitle(group))
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)

                                Button {
                                    beginEditing(group)
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                .buttonStyle(.borderless)
                                .disabled(isWorking)
                                .accessibilityLabel("Edit Share Group")

                                Button(role: .destructive) {
                                    Task { await delete(group) }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .disabled(isWorking)
                                .accessibilityLabel("Delete Share Group")
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }

                Section(editingShareGroup == nil ? "Create Group" : "Edit Group") {
                    if let editingShareGroup {
                        HStack {
                            Label("Editing \(editingShareGroup.name)", systemImage: "pencil")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.brandBlue)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Button("Cancel") {
                                cancelEditing()
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }

                    TextField("Group name", text: $groupName)
                        .textFieldStyle(.plain)
                        .padding(11)
                        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    TextField("email@company.com, alice.near", text: $groupMembers, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .lineLimit(2...4)
                        .textFieldStyle(.plain)
                        .padding(11)
                        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Button {
                        Task { await saveGroup() }
                    } label: {
                        Label(editingShareGroup == nil ? "Create Group" : "Save Group", systemImage: editingShareGroup == nil ? "plus" : "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandBlue)
                    .disabled(saveDisabled)
                }
            }
            .navigationTitle("Share Groups")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await chatStore.refreshShareGroups(showErrors: false)
            }
        }
        .platformMediumDetent()
    }

    private var saveDisabled: Bool {
        groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            groupMembers.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            isWorking
    }

    private func saveGroup() async {
        isWorking = true
        defer { isWorking = false }

        if let editingShareGroup {
            await chatStore.updateShareGroup(editingShareGroup, name: groupName, rawMembers: groupMembers)
            cancelEditing()
        } else {
            await chatStore.createShareGroup(name: groupName, rawMembers: groupMembers)
            groupName = ""
            groupMembers = ""
        }
    }

    private func delete(_ group: ShareGroupInfo) async {
        isWorking = true
        defer { isWorking = false }
        await chatStore.deleteShareGroup(group)
        if editingShareGroup?.id == group.id {
            cancelEditing()
        }
    }

    private func beginEditing(_ group: ShareGroupInfo) {
        editingShareGroup = group
        groupName = group.name
        groupMembers = group.members.map(\.shareSheetFieldValue).joined(separator: ", ")
    }

    private func cancelEditing() {
        editingShareGroup = nil
        groupName = ""
        groupMembers = ""
    }

    private func shareGroupSubtitle(_ group: ShareGroupInfo) -> String {
        let count = "\(group.members.count) member\(group.members.count == 1 ? "" : "s")"
        let preview = group.members.prefix(2).map(\.displayName).joined(separator: ", ")
        guard !preview.isEmpty else { return count }
        return "\(count) · \(preview)\(group.members.count > 2 ? ", +" : "")"
    }
}

struct RenameConversationView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Conversation Title")
                    .font(.headline)
                TextField("Title", text: $title)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))
                Spacer()
            }
            .padding()
            .navigationTitle("Rename")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
                }
            }
            .onAppear {
                title = chatStore.selectedConversationTitle
            }
        }
        .platformMediumDetent()
    }

    private func save() async {
        isWorking = true
        defer { isWorking = false }
        await chatStore.renameSelectedConversation(to: title)
        dismiss()
    }
}

struct NewProjectView: View {
    @EnvironmentObject private var chatStore: ChatStore
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
                        subtitle: instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Sources, files, instructions, and notes" : "Instructions ready",
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
                        TextField("How should the assistant handle this workspace?", text: $instructions, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(4...8)
                            .padding(12)
                            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))
                    }

                    Text("Project files, links, memory, and saved outputs will travel with chats in this workspace.")
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
                        chatStore.createProject(
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
    @EnvironmentObject private var chatStore: ChatStore
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
                        TextField("How should the assistant handle this workspace?", text: $instructions, axis: .vertical)
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
                        chatStore.updateProject(
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
