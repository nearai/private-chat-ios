import SwiftUI
import BackgroundTasks

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

    static var autoPlayDelayNanoseconds: UInt64 {
        let argumentPrefix = "-NEARDemoAutoPlayDelayMS="
        let argumentValue = CommandLine.arguments.first { $0.hasPrefix(argumentPrefix) }
            .flatMap { UInt64(String($0.dropFirst(argumentPrefix.count))) }
        let environmentValue = ProcessInfo.processInfo.environment["NEAR_DEMO_AUTOPLAY_DELAY_MS"].flatMap(UInt64.init)
        return (argumentValue ?? environmentValue ?? 0) * 1_000_000
    }
}
#endif

@main
struct NEARPrivateChatApp: App {
    private let environment: AppEnvironment
    @StateObject private var sessionStore: SessionStore
    @StateObject private var chatStore: ChatStore
    @StateObject private var briefingStore: BriefingStore
    @StateObject private var appRouter = AppRouter()

    init() {
        let environment = AppEnvironment.production()
        self.environment = environment
        _sessionStore = StateObject(wrappedValue: environment.sessionStore)
        _chatStore = StateObject(wrappedValue: environment.chatStore)
        _briefingStore = StateObject(wrappedValue: environment.briefingStore)
    }

    static let briefingRefreshTaskID = "ai.near.privatechat.briefings.refresh"

    /// Asks iOS to run briefings in the background. Timing is OS-controlled;
    /// the handler reschedules itself so the cron keeps running.
    static func scheduleBriefingRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: briefingRefreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(sessionStore)
                .environmentObject(chatStore)
                .environmentObject(briefingStore)
                .environmentObject(appRouter)
                .modifier(AppLifecycleModifier(sessionStore: sessionStore, chatStore: chatStore, briefingStore: briefingStore, router: appRouter))
        }
        .backgroundTask(.appRefresh(Self.briefingRefreshTaskID)) {
            await briefingStore.runDue()
            Self.scheduleBriefingRefresh()
        }
    }
}
