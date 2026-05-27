import Foundation

enum ChatDisplayItem: Identifiable, Hashable {
    case message(ChatMessage)
    case council(batchID: String, messages: [ChatMessage])

    var id: String {
        switch self {
        case let .message(message):
            return message.id
        case let .council(batchID, _):
            return batchID
        }
    }

    static func items(from messages: [ChatMessage]) -> [ChatDisplayItem] {
        MessageTimelineStore.displayItems(from: messages)
    }
}

struct MessageTimelineStore {
    static func displayItems(from messages: [ChatMessage]) -> [ChatDisplayItem] {
        let grouped = Dictionary(
            grouping: messages.filter { $0.role == .assistant && $0.councilBatchID?.isEmpty == false },
            by: { $0.councilBatchID ?? "" }
        )
        let groupCounts = grouped.mapValues(\.count)
        var renderedCouncilIDs = Set<String>()
        var items: [ChatDisplayItem] = []

        for message in messages {
            guard message.role == .assistant,
                  let batchID = message.councilBatchID,
                  (groupCounts[batchID] ?? 0) > 1 else {
                items.append(.message(message))
                continue
            }

            guard !renderedCouncilIDs.contains(batchID) else {
                continue
            }
            let councilMessages = (grouped[batchID] ?? [])
                .sorted { $0.createdAt < $1.createdAt }
            items.append(.council(batchID: batchID, messages: councilMessages))
            renderedCouncilIDs.insert(batchID)
        }
        return items
    }
}
