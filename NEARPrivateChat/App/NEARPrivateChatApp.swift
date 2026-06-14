import SwiftUI
import BackgroundTasks
import AppIntents

enum AppAppearancePreference: String, CaseIterable, Codable, Identifiable, Hashable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }

    init(remoteValue: String?) {
        switch remoteValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "light":
            self = .light
        case "dark":
            self = .dark
        default:
            self = .system
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    var detail: String {
        switch self {
        case .system:
            return "Follow the iPhone setting."
        case .light:
            return "Keep the app bright."
        case .dark:
            return "Use a darker, lower-glare look."
        }
    }
}

#if DEBUG
enum DemoCaptureScreen: String, CaseIterable {
    case onboarding
    case login
    case home
    case fileAttach
    case glmResult
    case chat
    case widgets
    case councilRoom
    case threaded
    case liveData
    case generativeChat
    case chatStarters
    case chatFailure
    case trackerFailure
    case markdownGallery
    case briefingBuilder
    case dashboard
    case councilBriefingLive
    case councilOutput
    case verification
    case models
    case cloudModels
    case council
    case composer
    case agent
    case ironclawThinking
    case ironclaw
    case project
    case share

    init(rawValueOrDefault rawValue: String?) {
        guard let normalized = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              let screen = DemoCaptureScreen.allCases.first(where: { $0.rawValue.lowercased() == normalized }) else {
            self = .onboarding
            return
        }
        self = screen
    }
}

enum DemoCapture {
    static var isEnabled: Bool {
        CommandLine.arguments.contains("-NEARDemoCapture") ||
            ProcessInfo.processInfo.environment["NEAR_DEMO_CAPTURE"] == "1"
    }

    static var isAutoPlayEnabled: Bool {
        CommandLine.arguments.contains("-NEARDemoAutoPlay") ||
            ProcessInfo.processInfo.environment["NEAR_DEMO_AUTOPLAY"] == "1"
    }

    static var initialScreen: DemoCaptureScreen {
        let argumentPrefix = "-NEARDemoScreen="
        let argumentValue = CommandLine.arguments.first { $0.hasPrefix(argumentPrefix) }
            .map { String($0.dropFirst(argumentPrefix.count)) }
        return DemoCaptureScreen(rawValueOrDefault: argumentValue ?? ProcessInfo.processInfo.environment["NEAR_DEMO_SCREEN"])
    }

    /// Prompt the `generativeChat` demo screen types and sends through normal
    /// chat routing. Lets capture runs override the default prompt.
    static var demoPrompt: String? {
        let argumentPrefix = "-NEARDemoPrompt="
        let argumentValue = CommandLine.arguments.first { $0.hasPrefix(argumentPrefix) }
            .map { String($0.dropFirst(argumentPrefix.count)) }
        let value = argumentValue ?? ProcessInfo.processInfo.environment["NEAR_DEMO_PROMPT"]
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    static var autoPlayDelayNanoseconds: UInt64 {
        let argumentPrefix = "-NEARDemoAutoPlayDelayMS="
        let argumentValue = CommandLine.arguments.first { $0.hasPrefix(argumentPrefix) }
            .flatMap { UInt64(String($0.dropFirst(argumentPrefix.count))) }
        let environmentValue = ProcessInfo.processInfo.environment["NEAR_DEMO_AUTOPLAY_DELAY_MS"].flatMap(UInt64.init)
        return (argumentValue ?? environmentValue ?? 0) * 1_000_000
    }
}

/// DEBUG-only live-backend credentials, injected via environment so signed-in
/// flows can be exercised in the demo harness without bundling any secret.
/// Values live only in the launched process's environment — never on disk or
/// in source. Used by the `*Live` demo screens.
enum DebugBackend {
    static var sessionToken: String? { trimmedEnv("NEAR_DEBUG_SESSION_TOKEN") }
    static var cloudKey: String? { trimmedEnv("NEAR_DEBUG_CLOUD_KEY") }
    static var isEnabled: Bool { sessionToken != nil }

    private static func trimmedEnv(_ key: String) -> String? {
        let value = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }
}
#endif

@main
struct NEARPrivateChatApp: App {
    private let environment: AppEnvironment
    @StateObject private var sessionStore: SessionStore
    @StateObject private var modelCatalogStore: ModelCatalogStore
    @StateObject private var fileStore: FileStore
    @StateObject private var projectStore: ProjectStore
    @StateObject private var conversationStore: ConversationStore
    @StateObject private var agentStore: AgentStore
    @StateObject private var accountStore: AccountStore
    @StateObject private var securityStore: SecurityStore
    @StateObject private var chatStore: ChatStore
    @StateObject private var shareStore: ShareStore
    @StateObject private var briefingStore: BriefingStore
    @StateObject private var routeHealthMonitor: RouteHealthMonitor
    @StateObject private var connectionDiagnostics: ConnectionDiagnostics
    @StateObject private var appRouter = AppRouter()

    init() {
        let environment = AppEnvironment.production()
        self.environment = environment
        _sessionStore = StateObject(wrappedValue: environment.sessionStore)
        _modelCatalogStore = StateObject(wrappedValue: environment.modelCatalogStore)
        _fileStore = StateObject(wrappedValue: environment.fileStore)
        _projectStore = StateObject(wrappedValue: environment.projectStore)
        _conversationStore = StateObject(wrappedValue: environment.conversationStore)
        _agentStore = StateObject(wrappedValue: environment.agentStore)
        _accountStore = StateObject(wrappedValue: environment.accountStore)
        _securityStore = StateObject(wrappedValue: environment.securityStore)
        _chatStore = StateObject(wrappedValue: environment.chatStore)
        _shareStore = StateObject(wrappedValue: environment.shareStore)
        _briefingStore = StateObject(wrappedValue: environment.briefingStore)
        _routeHealthMonitor = StateObject(wrappedValue: environment.routeHealthMonitor)
        _connectionDiagnostics = StateObject(wrappedValue: environment.connectionDiagnostics)
    }

    nonisolated static let briefingRefreshTaskID = "ai.near.privatechat.briefings.refresh"

    /// Asks iOS to run briefings in the background. Timing is OS-controlled;
    /// the handler reschedules itself so the cron keeps running.
    nonisolated static func scheduleBriefingRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: briefingRefreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(sessionStore)
                .environmentObject(modelCatalogStore)
                .environmentObject(fileStore)
                .environmentObject(projectStore)
                .environmentObject(conversationStore)
                .environmentObject(agentStore)
                .environmentObject(accountStore)
                .environmentObject(securityStore)
                .environmentObject(chatStore)
                .environmentObject(shareStore)
                .environmentObject(briefingStore)
                .environmentObject(routeHealthMonitor)
                .environmentObject(connectionDiagnostics)
                .environmentObject(appRouter)
                .modifier(AppLifecycleModifier(sessionStore: sessionStore, chatStore: chatStore, shareStore: shareStore, briefingStore: briefingStore, router: appRouter))
        }
        .backgroundTask(.appRefresh(Self.briefingRefreshTaskID)) {
            await briefingStore.runDue()
            Self.scheduleBriefingRefresh()
        }
    }
}

// MARK: - Siri / Shortcuts (App Intents)

/// "Ask Private Chat <question>" — stages the question and opens the app. The
/// running app consumes `ChatStore.pendingSiriPromptKey` on activation. This is
/// the privacy-first answer to a system assistant: the prompt is staged, never
/// auto-sent, and only this app sees it.
struct AskPrivateChatIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Private Chat"
    static var description = IntentDescription("Stage a private question in NEAR Private Chat.")
    static var openAppWhenRun = true

    @Parameter(title: "Question", requestValueDialog: "What do you want to ask privately?")
    var prompt: String

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(prompt, forKey: ChatStore.pendingSiriPromptKey)
        return .result()
    }
}

/// "Run my Private Chat trackers" — refreshes scheduled trackers.
struct RunBriefingsIntent: AppIntent {
    static var title: LocalizedStringResource = "Run my trackers"
    static var description = IntentDescription("Refresh scheduled Private Chat trackers.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: ChatStore.pendingRunBriefingsKey)
        return .result()
    }
}

struct NearAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskPrivateChatIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Ask \(.applicationName) a question"
            ],
            shortTitle: "Ask Private Chat",
            systemImageName: "bubble.left.and.text.bubble.right.fill"
        )
        AppShortcut(
            intent: RunBriefingsIntent(),
            phrases: [
                "Run my \(.applicationName) trackers",
                "Refresh \(.applicationName)"
            ],
            shortTitle: "Run trackers",
            systemImageName: "bell.badge.fill"
        )
    }
}
