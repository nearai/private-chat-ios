import SwiftUI
import UniformTypeIdentifiers

struct ShareConversationView: View {
    @EnvironmentObject private var modelCatalogStore: ModelCatalogStore
    @EnvironmentObject private var projectStore: ProjectStore
    @EnvironmentObject private var conversationStore: ConversationStore
    @EnvironmentObject private var securityStore: SecurityStore
    @EnvironmentObject private var shareStore: ShareStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var transcriptStore: ChatTranscriptStore
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
    @State private var showingPublicLinkPreview = false
    @State private var showingDisablePublicLinkConfirmation = false
    @State private var showingVerifiedExporter = false
    @State private var showingProofReportExporter = false
    @State private var showingSignedExportNotice = false
    @State private var verifiedExportDocument = ConversationExportDocument()
    @State private var verifiedExportFilename = "near-private-chat.signed.json"
    @State private var proofReportDocument = ConversationExportDocument()
    @State private var proofReportFilename = "near-private-chat-proof-report.json"
    @State private var pendingSensitiveShareGrant: SensitiveShareGrant?

    init(conversation: ConversationSummary, transcriptStore: ChatTranscriptStore) {
        self.conversation = conversation
        _transcriptStore = ObservedObject(wrappedValue: transcriptStore)
    }

private var publicURL: URL? {
        shareStore.publicURL(for: conversation)
    }

    private var publicShareEnabled: Bool {
        shareStore.shareInfo?.publicShare != nil
    }

    private var accessShares: [ConversationShareInfo] {
        shareStore.shareInfo?.shares.filter { !$0.isPublic } ?? []
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

                if shareStore.isLoadingShareInfo || isWorking {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Updating share")
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
                await shareStore.loadShares(for: conversation)
                await shareStore.refreshShareGroups(showErrors: false)
                ensureSelectedGroup()
            }
            .onChange(of: shareStore.shareGroups) {
                ensureSelectedGroup()
            }
            .sheet(isPresented: $showingPublicLinkPreview) {
                PublicLinkPreviewView(
                    conversation: conversation,
                    messageCount: transcriptStore.messages.count,
                    sourceCount: publicLinkSourceCount,
                    attestationStatus: currentAttestationStatus,
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
                Button("Disable link", role: .destructive) {
                    Task { await disablePublicShare() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Anyone with the URL loses access.")
            }
            .confirmationDialog(
                "Confirm access",
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
            .confirmationDialog(
                "Signed export",
                isPresented: $showingSignedExportNotice,
                titleVisibility: .visible
            ) {
                Button("Export Signed JSON") {
                    prepareVerifiedJSONExport()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Signs the transcript and route metadata with a stable on-device key. Repeated exports from this device share one signing key id and can be linked.")
            }
            .fileExporter(
                isPresented: $showingVerifiedExporter,
                document: verifiedExportDocument,
                contentType: ConversationExportFormat.signedJSON.contentType,
                defaultFilename: verifiedExportFilename
            ) { result in
                switch result {
                case .success:
                    shareStore.showBanner("Signed JSON exported.")
                case let .failure(error):
                    shareStore.showBanner(error.localizedDescription)
                }
            }
            .fileExporter(
                isPresented: $showingProofReportExporter,
                document: proofReportDocument,
                contentType: ConversationExportFormat.json.contentType,
                defaultFilename: proofReportFilename
            ) { result in
                switch result {
                case .success:
                    shareStore.showBanner("Proof report exported.")
                case let .failure(error):
                    shareStore.showBanner(error.localizedDescription)
                }
            }
        }
        .platformLargeDetent()
    }

    private var shareHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "link")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.brandAccent)
                .frame(width: 44, height: 44)
                .background(Color.appBlueTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(shareStore.shareInfo?.canShare == false ? "View existing access." : "Invite people or publish a read-only link.")
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
                    .foregroundStyle(publicShareEnabled ? Color.brandAccent : .secondary)
            }

            Text("Read-only. Anyone with the URL can read this Conversation until you disable the link.")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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
                        shareStore.showBanner("Link copied.")
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.actionPrimary)

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
                    Label("Review link", systemImage: "eye")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.actionPrimary)
                .controlSize(.large)
                .disabled(shareStore.shareInfo?.canShare == false || isWorking)
            }
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
                    Text("Signed export")
                        .font(.footnote.weight(.semibold))
                    Text("Signed JSON includes the transcript, route metadata, and the Attestation that was available. The proof report omits the transcript.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Button {
                    showingSignedExportNotice = true
                } label: {
                    Label("Signed JSON", systemImage: "checkmark.shield")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.trustVerified)
                .disabled(verifiedJSONExportUnavailableReason != nil)
                .accessibilityHint(verifiedJSONExportUnavailableReason ?? "Exports signed transcript JSON.")

                proofJSONShareAction
            }

            if let reason = verifiedJSONExportUnavailableReason {
                proofExportUnavailableText(reason)
            }

            if let reason = proofJSONExportUnavailableReason {
                proofExportUnavailableText(reason)
            }
        }
        .padding(12)
        .background(Color.trustVerified.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.trustVerified.opacity(0.20), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var proofJSONShareAction: some View {
        Button {
            prepareProofReportExport()
        } label: {
            Label("Proof report", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(proofJSONExportUnavailableReason != nil)
        .accessibilityHint(proofJSONExportUnavailableReason ?? "Exports the cached proof report.")
    }

    private func proofExportUnavailableText(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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
                .frame(width: 176)
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
                .tint(.actionPrimary)
                .disabled(inviteTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking || shareStore.shareInfo?.canShare == false)
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
                    Label("Share org", systemImage: "building.2.crop.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.actionPrimary)
                .disabled(organizationPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking || shareStore.shareInfo?.canShare == false)
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
                Label("People with access", systemImage: "person.2")
                    .font(.footnote.weight(.semibold))
                Spacer()
                Text("\(accessShares.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if accessShares.isEmpty {
                Text("Only you, until you invite people or enable the public link.")
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
            if shareStore.isLoadingShareGroups {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading groups")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            } else if shareStore.shareGroups.isEmpty {
                Text("Create a reusable group for people you share with often.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                Picker("Share Group", selection: $selectedGroupID) {
                    ForEach(shareStore.shareGroups) { group in
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
                .tint(.actionPrimary)
                .disabled(selectedGroupID.isEmpty || isWorking || shareStore.shareInfo?.canShare == false)

                VStack(spacing: 0) {
                    ForEach(shareStore.shareGroups) { group in
                        HStack(spacing: 10) {
                            Image(systemName: "person.3")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.brandAccent)
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
                                Task { await shareStore.deleteShareGroup(group) }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .disabled(isWorking)
                            .accessibilityLabel("Delete Share Group")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        if group.id != shareStore.shareGroups.last?.id {
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
                        .foregroundStyle(Color.brandAccent)
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
                shareStore.shareInfo?.canShare == false
            )
        }
    }

    private func accessRow(_ share: ConversationShareInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: shareSymbol(share))
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.brandAccent)
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
            .disabled(isWorking || pendingDeleteID != nil || shareStore.shareInfo?.canShare == false)
            .accessibilityLabel("Remove access")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }

    private func enablePublicShare() async {
        isWorking = true
        defer { isWorking = false }
        if let url = await shareStore.enablePublicShare(for: conversation) {
            Clipboard.copy(url.absoluteString)
        }
    }

    private func disablePublicShare() async {
        isWorking = true
        defer { isWorking = false }
        await shareStore.disablePublicShare(for: conversation)
    }

    private var shareGrantConfirmationMessage: String {
        let target = pendingSensitiveShareGrant?.label ?? "this target"
        if permission == .write {
            return "\(target.capitalized) can reply in this Conversation."
        }
        return "Org sharing grants access to a whole domain. Check the domain and permission."
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
        await shareStore.grantDirectShare(
            rawRecipients: inviteTarget,
            permission: permission.apiValue,
            conversation: conversation
        )
        inviteTarget = ""
    }

    private func grantOrganizationAccess() async {
        isWorking = true
        defer { isWorking = false }
        await shareStore.grantOrganizationShare(
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
            await shareStore.updateShareGroup(editingShareGroup, name: groupName, rawMembers: groupMembers)
            cancelShareGroupEditing()
            ensureSelectedGroup()
            return
        }

        await shareStore.createShareGroup(name: groupName, rawMembers: groupMembers)
        groupName = ""
        groupMembers = ""
        ensureSelectedGroup()
    }

    private func grantSelectedGroupAccess() async {
        isWorking = true
        defer { isWorking = false }
        await shareStore.grantGroupShare(
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
        await shareStore.removeConversationShare(share, conversation: conversation)
    }

    private var exportMessages: [ChatMessage] {
        guard conversationStore.selectedConversation?.id == conversation.id else { return [] }
        return transcriptStore.messages
    }

    private var verifiedJSONExportUnavailableReason: String? {
        if conversationStore.selectedConversation?.id != conversation.id {
            return "Open this Conversation to export Signed JSON."
        }
        if exportMessages.isEmpty {
            return "No messages to export."
        }
        return nil
    }

    private var proofJSONExportUnavailableReason: String? {
        guard securityStore.attestationSnapshot != nil else {
            return "No proof report cached. Open Proof and fetch it first."
        }
        guard currentAttestationStatus.effectiveState() == .valid else {
            return "Proof report is stale for this route. Open Proof and refresh it."
        }
        return nil
    }

    private func prepareVerifiedJSONExport() {
        if let reason = verifiedJSONExportUnavailableReason {
            shareStore.showBanner(reason)
            return
        }

        do {
            verifiedExportDocument = try ConversationExportBuilder.document(
                for: conversation,
                messages: exportMessages,
                format: .signedJSON,
                signedContext: signedTranscriptExportContext
            )
            verifiedExportFilename = ConversationExportBuilder.filename(
                for: conversation,
                format: .signedJSON
            )
            showingVerifiedExporter = true
        } catch {
            shareStore.showBanner(error.localizedDescription)
        }
    }

    private func prepareProofReportExport() {
        if let reason = proofJSONExportUnavailableReason {
            shareStore.showBanner(reason)
            return
        }
        guard let snapshot = securityStore.attestationSnapshot else {
            shareStore.showBanner("No proof report cached.")
            return
        }
        proofReportDocument = ConversationExportDocument(data: Data(snapshot.prettyJSON.utf8))
        proofReportFilename = "near-private-chat-proof-report.json"
        showingProofReportExporter = true
    }

    private func shareDisplayName(_ share: ConversationShareInfo) -> String {
        if let recipient = share.recipient {
            return recipient.value
        }
        if let pattern = share.orgEmailPattern {
            return pattern
        }
        if let groupID = share.groupID {
            return shareStore.shareGroups.first(where: { $0.id == groupID })?.name ?? "Group \(groupID)"
        }
        return share.shareType.capitalized
    }

    private func shareSubtitle(_ share: ConversationShareInfo) -> String {
        let permission = share.permission == "write" ? "Can reply" : "Read-only"
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
        if selectedGroupID.isEmpty || !shareStore.shareGroups.contains(where: { $0.id == selectedGroupID }) {
            selectedGroupID = shareStore.shareGroups.first?.id ?? ""
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
        let semantics = sourceRoutingSemantics
        let attachmentCount = semantics.attachesProjectFileSourcePack ? projectStore.selectedProjectAttachments.count : 0
        let linkCount = semantics.attachesSavedLinkSourcePack ? projectStore.selectedProjectLinks.count : 0
        return attachmentCount + linkCount
    }

    private var sourceRoutingSemantics: ChatSourceRoutingSemantics {
        modelCatalogStore.sourceRoutingSemantics(for: modelCatalogStore.selectedRouteKind)
    }

    private var currentAttestationStatus: AttestationStatus {
        securityStore.currentAttestationStatus(
            selectedModelID: modelCatalogStore.selectedModel,
            selectedRouteKind: modelCatalogStore.selectedRouteKind,
            isCouncilModeEnabled: modelCatalogStore.isCouncilModeEnabled,
            activeCouncilHasExternalRoutes: modelCatalogStore.activeCouncilHasExternalRoutes
        )
    }

    private var signedTranscriptExportContext: SignedTranscriptExportContext {
        return securityStore.signedTranscriptExportContext(
            selectedProviderDisplayName: modelCatalogStore.selectedProviderDisplayName,
            selectedRouteUsesNearCloud: modelCatalogStore.selectedRouteUsesNearCloud,
            selectedModelIsIronclawMobileRuntime: modelCatalogStore.selectedModelOption?.isIronclawMobileRuntime == true,
            sourceRoutingSemantics: sourceRoutingSemantics,
            projectID: projectStore.selectedProjectID
        )
    }
}
