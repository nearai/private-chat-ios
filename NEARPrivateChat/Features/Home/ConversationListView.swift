import SwiftUI

struct ConversationListView: View {
    let onOpenChat: () -> Void
    let onStartNewChat: () -> Void
    let onRunSetupAgain: () -> Void

    init(
        onOpenChat: @escaping () -> Void = {},
        onStartNewChat: @escaping () -> Void = {},
        onRunSetupAgain: @escaping () -> Void = {}
    ) {
        self.onOpenChat = onOpenChat
        self.onStartNewChat = onStartNewChat
        self.onRunSetupAgain = onRunSetupAgain
    }

    var body: some View {
        HomeScreen(
            onOpenChat: onOpenChat,
            onStartNewChat: onStartNewChat,
            onRunSetupAgain: onRunSetupAgain
        )
    }
}
