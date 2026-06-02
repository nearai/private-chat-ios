import Foundation

@MainActor
final class ShareStore: ObservableObject {
    @Published private(set) var shareInfo: ConversationSharesListResponse?
    @Published private(set) var sharedWithMe: [SharedConversationInfo] = []
    @Published private(set) var shareGroups: [ShareGroupInfo] = []
    @Published private(set) var sharedPreview: SharedConversationSnapshot?
    @Published private(set) var isLoadingShareInfo = false
    @Published private(set) var isLoadingSharedPreview = false
    @Published private(set) var isLoadingSharedWithMe = false
    @Published private(set) var isLoadingShareGroups = false

    var bannerHandler: (@MainActor (String) -> Void)?

    private let service: SharingService
    private var loadedShareInfoConversationID: String?

    init(service: SharingService) {
        self.service = service
    }

    var shouldShowSharedAuthorNames: Bool {
        Self.shouldShowSharedAuthorNames(sharedPreview: sharedPreview, shareInfo: shareInfo)
    }

    nonisolated static func shouldShowSharedAuthorNames(
        sharedPreview: SharedConversationSnapshot?,
        shareInfo: ConversationSharesListResponse?
    ) -> Bool {
        if sharedPreview != nil {
            return true
        }
        guard let shareInfo else { return false }
        return !shareInfo.isOwner || !shareInfo.shares.isEmpty
    }

    nonisolated static func conversationID(from value: String) -> String? {
        SharingService.conversationID(from: value)
    }

    nonisolated static func shareInviteRecipients(from value: String) -> [ShareInviteRecipient] {
        SharingService.shareInviteRecipients(from: value)
    }

    nonisolated static func normalizedOrganizationEmailPattern(_ value: String) -> String? {
        SharingService.normalizedOrganizationEmailPattern(value)
    }

    func loadShares(for conversation: ConversationSummary, showErrors: Bool = true) async {
        #if DEBUG
        if DemoCapture.isEnabled {
            shareInfo = Self.demoShareInfo(for: conversation)
            loadedShareInfoConversationID = conversation.id
            return
        }
        #endif
        isLoadingShareInfo = true
        defer { isLoadingShareInfo = false }
        do {
            shareInfo = try await service.loadShares(for: conversation.id)
            loadedShareInfoConversationID = conversation.id
        } catch {
            if showErrors {
                showBanner(error.localizedDescription)
            }
        }
    }

    func refreshSharedWithMe(showErrors: Bool = true) async {
        #if DEBUG
        if DemoCapture.isEnabled {
            sharedWithMe = []
            return
        }
        #endif
        guard !isLoadingSharedWithMe else { return }
        isLoadingSharedWithMe = true
        defer { isLoadingSharedWithMe = false }
        do {
            sharedWithMe = try await service.refreshSharedWithMe()
        } catch {
            if showErrors {
                showBanner(error.localizedDescription)
            }
        }
    }

    func enablePublicShare(for conversation: ConversationSummary) async -> URL? {
        do {
            try await service.enablePublicShare(for: conversation.id)
            await loadShares(for: conversation)
            showBanner("Public link enabled.")
            return publicURL(for: conversation)
        } catch {
            showBanner(error.localizedDescription)
            return nil
        }
    }

    func grantDirectShare(
        rawRecipients: String,
        permission: String,
        conversation: ConversationSummary
    ) async {
        do {
            let recipientCount = try await service.grantDirectShare(
                conversationID: conversation.id,
                rawRecipients: rawRecipients,
                permission: permission
            )
            await loadShares(for: conversation)
            showBanner(recipientCount == 1 ? "Access granted." : "Access granted to \(recipientCount) people.")
        } catch {
            showBanner(error.localizedDescription)
        }
    }

    func grantOrganizationShare(
        emailPattern: String,
        permission: String,
        conversation: ConversationSummary
    ) async {
        do {
            try await service.grantOrganizationShare(
                conversationID: conversation.id,
                emailPattern: emailPattern,
                permission: permission
            )
            await loadShares(for: conversation)
            showBanner("Organization access granted.")
        } catch {
            showBanner(error.localizedDescription)
        }
    }

    func refreshShareGroups(showErrors: Bool = true) async {
        #if DEBUG
        if DemoCapture.isEnabled {
            shareGroups = Self.demoShareGroups()
            return
        }
        #endif
        guard !isLoadingShareGroups else { return }
        isLoadingShareGroups = true
        defer { isLoadingShareGroups = false }
        do {
            shareGroups = try await service.refreshShareGroups()
        } catch {
            if showErrors {
                showBanner(error.localizedDescription)
            }
        }
    }

    func createShareGroup(name: String, rawMembers: String) async {
        do {
            let group = try await service.createShareGroup(name: name, rawMembers: rawMembers)
            upsertShareGroup(group)
            showBanner("Share group created.")
        } catch {
            showBanner(error.localizedDescription)
        }
    }

    func updateShareGroup(_ group: ShareGroupInfo, name: String, rawMembers: String) async {
        do {
            let updatedGroup = try await service.updateShareGroup(group.id, name: name, rawMembers: rawMembers)
            upsertShareGroup(updatedGroup)
            showBanner("Share group updated.")
        } catch {
            showBanner(error.localizedDescription)
        }
    }

    func deleteShareGroup(_ group: ShareGroupInfo) async {
        do {
            try await service.deleteShareGroup(group.id)
            shareGroups.removeAll { $0.id == group.id }
            showBanner("Share group deleted.")
        } catch {
            showBanner(error.localizedDescription)
        }
    }

    func grantGroupShare(
        groupID: String,
        permission: String,
        conversation: ConversationSummary
    ) async {
        do {
            try await service.grantGroupShare(
                conversationID: conversation.id,
                groupID: groupID,
                permission: permission
            )
            await loadShares(for: conversation)
            showBanner("Group access granted.")
        } catch {
            showBanner(error.localizedDescription)
        }
    }

    func removeConversationShare(_ share: ConversationShareInfo, conversation: ConversationSummary) async {
        do {
            try await service.removeConversationShare(conversationID: conversation.id, shareID: share.id)
            await loadShares(for: conversation)
            showBanner("Access removed.")
        } catch {
            showBanner(error.localizedDescription)
        }
    }

    func disablePublicShare(for conversation: ConversationSummary) async {
        let currentShareInfo = loadedShareInfoConversationID == conversation.id ? shareInfo : nil
        do {
            try await service.disablePublicShare(conversationID: conversation.id, currentShareInfo: currentShareInfo)
            await loadShares(for: conversation)
            showBanner("Public link disabled.")
        } catch {
            showBanner(error.localizedDescription)
        }
    }

    func publicURL(for conversation: ConversationSummary) -> URL? {
        SharingService.publicURL(for: conversation.id)
    }

    func openSharedConversation(from value: String, knownCanWrite: Bool? = nil, sourceLabel: String? = nil) async {
        isLoadingSharedPreview = true
        defer { isLoadingSharedPreview = false }
        do {
            sharedPreview = try await service.openSharedConversation(
                from: value,
                knownCanWrite: knownCanWrite,
                sourceLabel: sourceLabel
            )
        } catch {
            showBanner(error.localizedDescription)
        }
    }

    func closeSharedPreview() {
        sharedPreview = nil
    }

    func clearConversationShareInfo() {
        shareInfo = nil
        loadedShareInfoConversationID = nil
    }

    func reset() {
        shareInfo = nil
        sharedWithMe = []
        shareGroups = []
        sharedPreview = nil
        loadedShareInfoConversationID = nil
        isLoadingShareInfo = false
        isLoadingSharedPreview = false
        isLoadingSharedWithMe = false
        isLoadingShareGroups = false
    }

    private func upsertShareGroup(_ group: ShareGroupInfo) {
        shareGroups.removeAll { $0.id == group.id }
        shareGroups.append(group)
        shareGroups.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func showBanner(_ message: String) {
        bannerHandler?(message)
    }

    #if DEBUG
    private static func demoShareInfo(for conversation: ConversationSummary) -> ConversationSharesListResponse {
        ConversationSharesListResponse(
            isOwner: true,
            canShare: true,
            canWrite: true,
            shares: [
                ConversationShareInfo(
                    id: "demo-public-share",
                    conversationID: conversation.id,
                    permission: "read",
                    shareType: "public",
                    recipient: nil,
                    groupID: nil,
                    orgEmailPattern: nil,
                    publicToken: "demo-iran-status",
                    createdAt: "2026-05-25T13:39:00Z",
                    updatedAt: "2026-05-25T13:40:00Z"
                )
            ],
            owner: ShareOwner(userID: "demo.capture.near", name: "Demo Account")
        )
    }

    private static func demoShareGroups() -> [ShareGroupInfo] {
        [
            ShareGroupInfo(
                id: "demo-share-group-launch",
                name: "Research Review",
                members: [
                    ShareInviteRecipient(kind: "email", value: "reviewer@example.com")
                ],
                createdAt: "2026-05-25T13:38:00Z",
                updatedAt: "2026-05-25T13:38:00Z"
            )
        ]
    }
    #endif
}
