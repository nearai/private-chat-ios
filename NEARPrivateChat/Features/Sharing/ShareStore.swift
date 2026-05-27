import Foundation

struct ShareStore {
    static func shouldShowSharedAuthorNames(
        sharedPreview: SharedConversationSnapshot?,
        shareInfo: ConversationSharesListResponse?
    ) -> Bool {
        if sharedPreview != nil {
            return true
        }
        guard let shareInfo else { return false }
        return !shareInfo.isOwner || !shareInfo.shares.isEmpty
    }
}
