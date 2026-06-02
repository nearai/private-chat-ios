import Foundation

final class PrivateChatAPI: AuthAPI,
    SettingsAPI,
    BillingAPI,
    ModelAPI,
    ConversationAPI,
    FileAPI,
    ShareAPI,
    AttestationAPI,
    MessageAPI {
    private let client: APIClient
    private let authClient: PrivateChatAuthAPI
    private let settingsClient: PrivateChatSettingsAPI
    private let billingClient: PrivateChatBillingAPI
    private let modelClient: PrivateChatModelAPI
    private let conversationClient: PrivateChatConversationAPI
    private let fileClient: PrivateChatFileAPI
    private let shareClient: PrivateChatShareAPI
    private let attestationClient: PrivateChatAttestationAPI
    private let messageClient: PrivateChatMessageAPI

    static let maxUploadBytes = APIClient.maxUploadBytes
    static let maxFilePreviewBytes = APIClient.maxFilePreviewBytes

    var configuration: AppConfiguration {
        get { client.configuration }
        set { client.configuration = newValue }
    }

    var authToken: String? {
        get { client.authToken }
        set { client.authToken = newValue }
    }

    init(configuration: AppConfiguration) {
        let client = APIClient(configuration: configuration)
        self.client = client
        authClient = PrivateChatAuthAPI(client: client)
        settingsClient = PrivateChatSettingsAPI(client: client)
        billingClient = PrivateChatBillingAPI(client: client)
        modelClient = PrivateChatModelAPI(client: client)
        conversationClient = PrivateChatConversationAPI(client: client)
        fileClient = PrivateChatFileAPI(client: client)
        shareClient = PrivateChatShareAPI(client: client)
        attestationClient = PrivateChatAttestationAPI(client: client)
        messageClient = PrivateChatMessageAPI(client: client)
    }

    func authURL(for provider: OAuthProvider, state: String? = nil, codeChallenge: String? = nil) throws -> URL {
        try authClient.authURL(for: provider, state: state, codeChallenge: codeChallenge)
    }

    func parseAuthCallback(_ url: URL, expectedState: String? = nil) throws -> AuthCodeCallback {
        try authClient.parseAuthCallback(url, expectedState: expectedState)
    }

    func exchangeAuthCode(provider: OAuthProvider, callback: AuthCodeCallback, codeVerifier: String) async throws -> AuthSession {
        try await authClient.exchangeAuthCode(provider: provider, callback: callback, codeVerifier: codeVerifier)
    }

    func fetchProfile() async throws -> UserProfile {
        try await authClient.fetchProfile()
    }

    func signOut(sessionID: String) async throws {
        try await authClient.signOut(sessionID: sessionID)
    }

    func fetchUserSettings() async throws -> UserSettingsResponse {
        try await settingsClient.fetchUserSettings()
    }

    func updateUserSettings(
        systemPrompt: String,
        webSearchEnabled: Bool,
        notificationEnabled: Bool,
        appearance: String,
        largeTextAsFile: Bool,
        advancedParams: AdvancedModelParams
    ) async throws -> UserSettingsResponse {
        try await settingsClient.updateUserSettings(
            systemPrompt: systemPrompt,
            webSearchEnabled: webSearchEnabled,
            notificationEnabled: notificationEnabled,
            appearance: appearance,
            largeTextAsFile: largeTextAsFile,
            advancedParams: advancedParams
        )
    }

    func fetchSubscriptionPlans() async throws -> [SubscriptionPlan] {
        try await billingClient.fetchSubscriptionPlans()
    }

    func fetchSubscriptions(includeInactive: Bool = false) async throws -> [SubscriptionInfo] {
        try await billingClient.fetchSubscriptions(includeInactive: includeInactive)
    }

    func fetchModels() async throws -> [ModelOption] {
        try await modelClient.fetchModels()
    }

    func connectNearCloudAccount() async throws -> NearCloudConnectResponse {
        try await modelClient.connectNearCloudAccount()
    }

    func fetchNearCloudModels(apiKey: String? = nil) async throws -> [ModelOption] {
        try await modelClient.fetchNearCloudModels(apiKey: apiKey)
    }

    func fetchNearCloudChatCompletion(
        apiKey: String,
        model: String,
        prompt: String,
        systemPrompt: String,
        advancedParams: AdvancedModelParams = .defaults
    ) async throws -> String {
        try await modelClient.fetchNearCloudChatCompletion(
            apiKey: apiKey,
            model: model,
            prompt: prompt,
            systemPrompt: systemPrompt,
            advancedParams: advancedParams
        )
    }

    func fetchConversations() async throws -> [ConversationSummary] {
        try await conversationClient.fetchConversations()
    }

    func createConversation(title: String) async throws -> ConversationSummary {
        try await conversationClient.createConversation(title: title)
    }

    func createConversation(title: String, metadata: [String: String]) async throws -> ConversationSummary {
        try await conversationClient.createConversation(title: title, metadata: metadata)
    }

    func addItemsToConversation(_ conversationID: String, items: [ConversationImportItem]) async throws {
        try await conversationClient.addItemsToConversation(conversationID, items: items)
    }

    func updateConversationTitle(_ conversationID: String, title: String) async throws {
        try await conversationClient.updateConversationTitle(conversationID, title: title)
    }

    func fetchConversationItems(_ conversationID: String) async throws -> ConversationItemsResponse {
        try await conversationClient.fetchConversationItems(conversationID)
    }

    func fetchReadableConversation(_ conversationID: String) async throws -> ConversationSummary {
        try await conversationClient.fetchReadableConversation(conversationID)
    }

    func fetchReadableConversationItems(_ conversationID: String) async throws -> ConversationItemsResponse {
        try await conversationClient.fetchReadableConversationItems(conversationID)
    }

    func deleteConversation(_ conversationID: String) async throws {
        try await conversationClient.deleteConversation(conversationID)
    }

    func cloneConversation(_ conversationID: String) async throws -> ConversationSummary {
        try await conversationClient.cloneConversation(conversationID)
    }

    func archiveConversation(_ conversationID: String) async throws {
        try await conversationClient.archiveConversation(conversationID)
    }

    func unarchiveConversation(_ conversationID: String) async throws {
        try await conversationClient.unarchiveConversation(conversationID)
    }

    func pinConversation(_ conversationID: String) async throws {
        try await conversationClient.pinConversation(conversationID)
    }

    func unpinConversation(_ conversationID: String) async throws {
        try await conversationClient.unpinConversation(conversationID)
    }

    func uploadFile(from url: URL) async throws -> ChatAttachment {
        try await fileClient.uploadFile(from: url)
    }

    func uploadTextFile(filename: String, text: String) async throws -> ChatAttachment {
        try await fileClient.uploadTextFile(filename: filename, text: text)
    }

    func fetchFiles() async throws -> RemoteFilesResponse {
        try await fileClient.fetchFiles()
    }

    func fetchFile(_ fileID: String) async throws -> RemoteFileInfo {
        try await fileClient.fetchFile(fileID)
    }

    func fetchFileContent(_ fileID: String) async throws -> Data {
        try await fileClient.fetchFileContent(fileID)
    }

    func fetchFilePreviewContent(_ fileID: String, maxBytes: Int = PrivateChatAPI.maxFilePreviewBytes) async throws -> Data {
        try await fileClient.fetchFilePreviewContent(fileID, maxBytes: maxBytes)
    }

    func deleteFile(_ fileID: String) async throws {
        try await fileClient.deleteFile(fileID)
    }

    func fetchConversationShares(_ conversationID: String) async throws -> ConversationSharesListResponse {
        try await shareClient.fetchConversationShares(conversationID)
    }

    func fetchSharedWithMe() async throws -> [SharedConversationInfo] {
        try await shareClient.fetchSharedWithMe()
    }

    func createPublicShare(_ conversationID: String) async throws -> [ConversationShareInfo] {
        try await shareClient.createPublicShare(conversationID)
    }

    func createDirectShare(
        _ conversationID: String,
        recipients: [ShareInviteRecipient],
        permission: String
    ) async throws -> [ConversationShareInfo] {
        try await shareClient.createDirectShare(conversationID, recipients: recipients, permission: permission)
    }

    func createOrganizationShare(
        _ conversationID: String,
        emailPattern: String,
        permission: String
    ) async throws -> [ConversationShareInfo] {
        try await shareClient.createOrganizationShare(conversationID, emailPattern: emailPattern, permission: permission)
    }

    func createGroupShare(
        _ conversationID: String,
        groupID: String,
        permission: String
    ) async throws -> [ConversationShareInfo] {
        try await shareClient.createGroupShare(conversationID, groupID: groupID, permission: permission)
    }

    func fetchShareGroups() async throws -> [ShareGroupInfo] {
        try await shareClient.fetchShareGroups()
    }

    func createShareGroup(name: String, members: [ShareInviteRecipient]) async throws -> ShareGroupInfo {
        try await shareClient.createShareGroup(name: name, members: members)
    }

    func updateShareGroup(_ groupID: String, name: String, members: [ShareInviteRecipient]) async throws -> ShareGroupInfo {
        try await shareClient.updateShareGroup(groupID, name: name, members: members)
    }

    func deleteShareGroup(_ groupID: String) async throws {
        try await shareClient.deleteShareGroup(groupID)
    }

    func deleteConversationShare(_ conversationID: String, shareID: String) async throws {
        try await shareClient.deleteConversationShare(conversationID, shareID: shareID)
    }

    func fetchAttestationReport(
        nonce: String,
        signingAlgorithm: String = "ecdsa",
        model: String? = nil
    ) async throws -> AttestationSnapshot {
        try await attestationClient.fetchAttestationReport(
            nonce: nonce,
            signingAlgorithm: signingAlgorithm,
            model: model
        )
    }

    func streamResponse(
        model: String,
        text: String,
        attachments: [ChatAttachment],
        conversationID: String,
        previousResponseID: String?,
        webSearchEnabled: Bool,
        systemPrompt: String,
        advancedParams: AdvancedModelParams = .defaults,
        initiator: String = "new_message",
        visibleOutputTimeout: TimeInterval? = nil,
        onEvent: @escaping (ResponseStreamEvent) async -> Void
    ) async throws {
        try await messageClient.streamResponse(
            model: model,
            text: text,
            attachments: attachments,
            conversationID: conversationID,
            previousResponseID: previousResponseID,
            webSearchEnabled: webSearchEnabled,
            systemPrompt: systemPrompt,
            advancedParams: advancedParams,
            initiator: initiator,
            visibleOutputTimeout: visibleOutputTimeout,
            onEvent: onEvent
        )
    }

    func parseStreamEvent(_ data: Data) -> ResponseStreamEvent? {
        messageClient.parseStreamEvent(data)
    }

    static func normalizedNearCloudAPIKey(_ apiKey: String?) -> String {
        PrivateChatModelAPI.normalizedNearCloudAPIKey(apiKey)
    }

    static func isSafeAPIPathID(_ value: String, minimumLength: Int = 1) -> Bool {
        APIClient.isSafeAPIPathID(value, minimumLength: minimumLength)
    }

    static var widgetInstructionForTesting: String {
        PrivateChatMessageAPI.widgetInstructionForTesting
    }

    static func responseInstructionsForTesting(webSearchEnabled: Bool, systemPrompt: String = "") -> String {
        PrivateChatMessageAPI.responseInstructionsForTesting(webSearchEnabled: webSearchEnabled, systemPrompt: systemPrompt)
    }

    static func responseContentDescriptorsForTesting(attachments: [ChatAttachment]) -> [(type: String, fileID: String?)] {
        PrivateChatMessageAPI.responseContentDescriptorsForTesting(attachments: attachments)
    }

    static func mimeType(for url: URL) -> String {
        PrivateChatFileAPI.mimeType(for: url)
    }

    static func uploadPurpose(filename: String, mimeType: String) -> String {
        PrivateChatFileAPI.uploadPurpose(filename: filename, mimeType: mimeType)
    }

    static func needsVisionTranscode(filename: String, mimeType: String) -> Bool {
        PrivateChatFileAPI.needsVisionTranscode(filename: filename, mimeType: mimeType)
    }

    static func normalizedVisionFilename(filename: String, mimeType: String) -> String {
        PrivateChatFileAPI.normalizedVisionFilename(filename: filename, mimeType: mimeType)
    }

    static func normalizedVisionUpload(data: Data, filename: String, mimeType: String) throws -> (data: Data, filename: String, mimeType: String) {
        try PrivateChatFileAPI.normalizedVisionUpload(data: data, filename: filename, mimeType: mimeType)
    }
}
