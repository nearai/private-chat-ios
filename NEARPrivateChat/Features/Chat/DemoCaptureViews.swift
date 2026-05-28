import SwiftUI

#if DEBUG
struct DemoCaptureRootView: View {
    @EnvironmentObject private var chatStore: ChatStore
    let screen: DemoCaptureScreen
    let autoPlay: Bool
    @State private var currentScreen: DemoCaptureScreen

    private let autoPlayScreens: [DemoCaptureScreen] = [
        .onboarding,
        .login,
        .home,
        .composer,
        .models,
        .glmResult,
        .verification,
        .council,
        .councilOutput,
        .project,
        .fileAttach,
        .agent,
        .ironclawThinking,
        .ironclaw,
        .share
    ]

    init(screen: DemoCaptureScreen, autoPlay: Bool) {
        self.screen = screen
        self.autoPlay = autoPlay
        _currentScreen = State(initialValue: screen)
    }

    var body: some View {
        DemoCaptureScreenHost(screen: currentScreen)
            .environmentObject(chatStore)
            .id(currentScreen.rawValue)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.25), value: currentScreen)
            .overlay {
                DemoSceneOverlay(screen: currentScreen)
                    .allowsHitTesting(false)
            }
            .task {
                guard autoPlay else { return }
                let delay = DemoCapture.autoPlayDelayNanoseconds
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }
                for screen in autoPlayScreens {
                    await MainActor.run {
                        currentScreen = screen
                        chatStore.prepareDemoCapture(screen: screen)
                    }
                    try? await Task.sleep(nanoseconds: duration(for: screen))
                }
            }
            .onAppear {
                chatStore.prepareDemoCapture(screen: currentScreen)
            }
    }

    private func duration(for screen: DemoCaptureScreen) -> UInt64 {
        switch screen {
        case .onboarding:
            return 2_000_000_000
        case .login:
            return 5_000_000_000
        case .home:
            return 4_000_000_000
        case .fileAttach:
            return 9_000_000_000
        case .glmResult:
            return 14_000_000_000
        case .chat, .widgets:
            return 3_500_000_000
        case .councilOutput:
            return 12_000_000_000
        case .verification:
            return 7_000_000_000
        case .cloudModels:
            return 4_000_000_000
        case .models:
            return 4_000_000_000
        case .council, .councilRoom:
            return 6_000_000_000
        case .composer:
            return 5_500_000_000
        case .agent:
            return 7_000_000_000
        case .ironclawThinking:
            return 10_000_000_000
        case .ironclaw:
            return 9_000_000_000
        case .project:
            return 5_000_000_000
        case .share:
            return 6_000_000_000
        }
    }
}

private func demoCouncilRoomModel() -> CouncilRoomModel {
    let now = Date()
    let batch = "demo-council"
    func message(_ id: String, _ model: String, _ text: String) -> ChatMessage {
        ChatMessage(id: id, role: .assistant, text: text, model: model, createdAt: now, status: "completed", responseID: "\(id)-r", councilBatchID: batch, isStreaming: false)
    }
    let messages = [
        message("c-glm", "glm-5.1", "I concur. The architecture is sound and the streaming path is stable in main, so shipping is reasonable."),
        message("c-claude", "claude-opus-4-7", "Yes, with caveats. The latency budget on the streaming side is the one risk. If we cap concurrent models at 3 we hold the SLA at p95 < 1.4s."),
        message("c-gemini", "gemini-2.5-pro", "I disagree. Per-message proof for cross-model consensus is not landed in main; however, shipping without it means the verification footer is silently wrong on Council answers."),
        message("c-syn", "llm-council/synthesis", "Synthesis: the council broadly supports shipping Council v2.\n\nAgreement: two of three models back shipping; the architecture and streaming path are considered stable.\n\nDisagreement: one model flags that per-message cross-model proof is not yet in main.\n\nRecommended next step: ship behind a flag, land the proof path, then enable by default.")
    ]
    return CouncilRoomModel.from(councilMessages: messages)
}

private struct DemoCaptureScreenHost: View {
    @EnvironmentObject private var chatStore: ChatStore
    let screen: DemoCaptureScreen

    var body: some View {
        Group {
            switch screen {
            case .onboarding:
                DemoOnboardingPreviewView()
            case .login:
                DemoMockLoginView()
            case .home:
                AppShellView()
            case .fileAttach:
                DemoFileAttachmentFlowView()
            case .glmResult:
                DemoGLMAnswerView()
            case .councilOutput:
                DemoCouncilComparisonView()
            case .chat, .composer, .widgets:
                NavigationStack {
                    ChatView()
                        .navigationTitle(chatStore.selectedConversationTitle)
                        .platformInlineNavigationTitle()
                }
            case .ironclaw:
                DemoIronClawResultView()
            case .ironclawThinking:
                DemoIronClawThinkingView()
            case .agent:
                DemoIronClawModesView()
            case .verification:
                SecurityView()
            case .models:
                DemoSingleModelPickerView()
            case .cloudModels:
                DemoNearCloudModelsView()
            case .council:
                DemoCouncilLineupView()
            case .councilRoom:
                CouncilRoomView(
                    model: demoCouncilRoomModel(),
                    onSend: { _, _ in },
                    onSynthesize: {}
                )
            case .project:
                ProjectFilesView()
            case .share:
                if let conversation = chatStore.selectedConversation {
                    ShareConversationView(conversation: conversation)
                } else {
                    AppShellView()
                }
            }
        }
        .tint(.brandBlue)
    }
}

private struct DemoSceneOverlay: View {
    let screen: DemoCaptureScreen

    var body: some View {
        ZStack {
            switch screen {
            case .composer:
                DemoTimedTapPulse(delay: 4.25, x: 0.79, y: 0.18)
            case .glmResult:
                DemoFocusBox(delay: 1.0, duration: 2.0, x: 0.04, y: 0.23, width: 0.92, height: 0.58, tint: .actionPrimary)
                DemoFocusBox(delay: 11.4, duration: 2.1, x: 0.06, y: 0.76, width: 0.88, height: 0.13, tint: .trustVerified)
                DemoTimedTapPulse(delay: 12.4, x: 0.14, y: 0.82, tint: .trustVerified)
            case .verification:
                DemoFocusBox(delay: 0.8, duration: 2.0, x: 0.07, y: 0.11, width: 0.86, height: 0.13, tint: .trustVerified)
                DemoFocusBox(delay: 3.3, duration: 2.2, x: 0.07, y: 0.37, width: 0.86, height: 0.30, tint: .actionPrimary)
            case .cloudModels:
                DemoFocusBox(delay: 1.1, duration: 2.2, x: 0.08, y: 0.35, width: 0.84, height: 0.18, tint: .orange)
            case .council:
                DemoFocusBox(delay: 1.0, duration: 2.1, x: 0.06, y: 0.28, width: 0.88, height: 0.35, tint: .actionPrimary)
                DemoFocusBox(delay: 3.7, duration: 1.8, x: 0.08, y: 0.56, width: 0.84, height: 0.14, tint: .trustVerified)
            case .chat:
                DemoTimedTapPulse(delay: 2.4, x: 0.91, y: 0.09)
            case .agent:
                DemoFocusBox(delay: 3.0, duration: 2.2, x: 0.06, y: 0.48, width: 0.88, height: 0.30, tint: .actionPrimary)
                DemoTimedTapPulse(delay: 5.9, x: 0.50, y: 0.62)
            case .ironclawThinking:
                DemoFocusBox(delay: 1.0, duration: 2.0, x: 0.06, y: 0.16, width: 0.88, height: 0.20, tint: .trustVerified)
                DemoFocusBox(delay: 4.0, duration: 2.0, x: 0.06, y: 0.36, width: 0.88, height: 0.19, tint: .actionPrimary)
                DemoFocusBox(delay: 7.0, duration: 2.2, x: 0.16, y: 0.60, width: 0.78, height: 0.20, tint: .actionPrimary)
            case .share:
                DemoFocusBox(delay: 1.0, duration: 2.0, x: 0.06, y: 0.18, width: 0.88, height: 0.18, tint: .trustVerified)
                DemoFocusBox(delay: 3.3, duration: 2.1, x: 0.06, y: 0.42, width: 0.88, height: 0.18, tint: .actionPrimary)
            default:
                EmptyView()
            }
        }
    }
}

private struct DemoTimedTapPulse: View {
    let delay: Double
    let x: CGFloat
    let y: CGFloat
    var tint: Color = .actionPrimary

    @State private var isVisible = false
    @State private var isExpanded = false

    var body: some View {
        GeometryReader { geometry in
            if isVisible {
                ZStack {
                    Circle()
                        .stroke(tint.opacity(0.28), lineWidth: 2)
                        .frame(width: isExpanded ? 74 : 28, height: isExpanded ? 74 : 28)
                        .opacity(isExpanded ? 0 : 1)
                    Circle()
                        .fill(tint.opacity(0.18))
                        .frame(width: 32, height: 32)
                    Circle()
                        .fill(tint)
                        .frame(width: 9, height: 9)
                }
                .position(x: geometry.size.width * x, y: geometry.size.height * y)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.72).repeatCount(3, autoreverses: false)) {
                        isExpanded = true
                    }
                }
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await MainActor.run {
                isVisible = true
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                isVisible = false
            }
        }
    }
}

private struct DemoFocusBox: View {
    let delay: Double
    let duration: Double
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    var tint: Color = .actionPrimary

    @State private var isVisible = false
    @State private var isExpanded = false

    var body: some View {
        GeometryReader { geometry in
            if isVisible {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(tint.opacity(isExpanded ? 0.16 : 0.55), lineWidth: 3)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(tint.opacity(0.045))
                    }
                    .frame(width: geometry.size.width * width, height: geometry.size.height * height)
                    .position(x: geometry.size.width * (x + width / 2), y: geometry.size.height * (y + height / 2))
                    .scaleEffect(isExpanded ? 1.018 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isExpanded)
                    .onAppear {
                        isExpanded = true
                    }
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await MainActor.run {
                isVisible = true
            }
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            await MainActor.run {
                isVisible = false
            }
        }
    }
}

private struct DemoOnboardingPreviewView: View {
    private let signInRows: [(title: String, symbol: String)] = [
        ("Continue with NEAR", "sparkles"),
        ("Continue with Google", "g.circle"),
        ("Continue with GitHub", "chevron.left.forwardslash.chevron.right")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                AuthHeroCard()

                VStack(alignment: .leading, spacing: 12) {
                    Label("Terms & Conditions", systemImage: "doc.text.magnifyingglass")
                        .font(.headline.weight(.semibold))
                    Text("Review terms once, then sign in with NEAR, Google, or GitHub.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: 360, alignment: .leading)
                .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.appBorder, lineWidth: 1)
                }

                VStack(spacing: 10) {
                    ForEach(signInRows, id: \.title) { row in
                        HStack(spacing: 10) {
                            Image(systemName: row.symbol)
                                .font(.subheadline.weight(.bold))
                                .frame(width: 24)
                            Text(row.title)
                                .font(.subheadline.weight(.bold))
                            Spacer()
                        }
                        .foregroundStyle(row.title.contains("NEAR") ? Color.white : Color.primary)
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .background(row.title.contains("NEAR") ? Color.actionPrimary : Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(row.title.contains("NEAR") ? Color.clear : Color.appBorder, lineWidth: 1)
                        }
                    }

                    HStack {
                        Label("Open shared link", systemImage: "link")
                        Spacer()
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.actionPrimary)
                    .padding(.horizontal, 2)

                    HStack {
                        Label("More sign-in options", systemImage: "ellipsis.circle")
                        Spacer()
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
                }
                .frame(maxWidth: 360)

                Text("https://private.near.ai")
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(28)
        }
        .background { HomeSurfaceBackground().ignoresSafeArea() }
    }
}

private struct DemoMockLoginView: View {
    @State private var passwordCount = 0
    @State private var isVerifying = false
    @State private var isComplete = false

    private let passwordLength = 12

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                googleWordmark

                VStack(alignment: .leading, spacing: 7) {
                    Text("Sign in")
                        .font(.largeTitle.weight(.regular))
                    Text("to continue to NEAR Private Chat")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.actionPrimary.opacity(0.12))
                        .frame(width: 24, height: 24)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.actionPrimary)
                        }
                    Text("maya.launch@example.com")
                        .font(.subheadline.weight(.medium))
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .frame(height: 38)
                .overlay {
                    Capsule()
                        .stroke(Color.appBorder, lineWidth: 1)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Enter your password")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.actionPrimary)
                    HStack {
                        Text(String(repeating: "•", count: max(passwordCount, 1)))
                            .font(.title3.monospaced().weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 54)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.actionPrimary, lineWidth: 1.5)
                    }
                }

                HStack {
                    Button("Forgot password?") {}
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.actionPrimary)
                    Spacer()
                    Button {} label: {
                        HStack(spacing: 7) {
                            if isVerifying {
                                ProgressView()
                                    .controlSize(.mini)
                                    .tint(.white)
                            }
                            Text(isComplete ? "Continue" : "Next")
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .frame(height: 42)
                        .background(Color.actionPrimary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(true)
                }

                if isComplete {
                    Label("Google account verified", systemImage: "checkmark.shield.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.trustVerified)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(26)
            .frame(maxWidth: 430, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 76)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground.ignoresSafeArea())
        .task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            for count in 1...passwordLength {
                try? await Task.sleep(nanoseconds: 95_000_000)
                await MainActor.run {
                    passwordCount = count
                }
            }
            try? await Task.sleep(nanoseconds: 380_000_000)
            await MainActor.run {
                isVerifying = true
            }
            try? await Task.sleep(nanoseconds: 900_000_000)
            await MainActor.run {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                    isVerifying = false
                    isComplete = true
                }
            }
        }
    }

    private var googleWordmark: some View {
        HStack(spacing: 0) {
            Text("G").foregroundStyle(Color.googleBlue)
            Text("o").foregroundStyle(Color.googleRed)
            Text("o").foregroundStyle(Color.googleYellow)
            Text("g").foregroundStyle(Color.googleBlue)
            Text("l").foregroundStyle(Color.googleGreen)
            Text("e").foregroundStyle(Color.googleRed)
        }
        .font(.title2.weight(.medium))
        .accessibilityLabel("Google")
    }
}

private struct DemoFileAttachmentFlowView: View {
    @State private var phase = 0

    private let files = [
        ("reborn-project-plan.md", "Markdown plan · 42 KB", "doc.text"),
        ("latest-ironclaw-prs.json", "GitHub PR snapshot · 19 KB", "curlybraces")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if phase < 2 {
                    List {
                        Section {
                            ForEach(Array(files.enumerated()), id: \.offset) { index, file in
                                HStack(spacing: 12) {
                                    Image(systemName: file.2)
                                        .font(.headline.weight(.medium))
                                        .foregroundStyle(Color.actionPrimary)
                                        .frame(width: 34, height: 34)
                                        .background(Color.actionPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(file.0)
                                            .font(.subheadline.weight(.semibold))
                                        Text(file.1)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: index <= phase ? "checkmark.circle.fill" : "circle")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(index <= phase ? Color.trustVerified : Color.secondary)
                                }
                                .frame(height: 52)
                            }
                        } header: {
                            Text("iCloud Drive / IronClaw Reborn")
                        }
                    }
                    .listStyle(.insetGrouped)
                    .navigationTitle("Files")
                    .platformInlineNavigationTitle()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {}
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(phase >= 1 ? "Open" : "Add") {}
                                .fontWeight(.semibold)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("New chat")
                                .font(.headline.weight(.semibold))
                            Spacer()
                            ComposerRouteChip(title: "Hosted IronClaw", symbolName: "terminal", isActive: true, showsChevron: true)
                        }

                        Text("Attached from Files")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        VStack(spacing: 8) {
                            ForEach(files, id: \.0) { file in
                                HStack(spacing: 10) {
                                    Image(systemName: file.2)
                                        .foregroundStyle(Color.actionPrimary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(file.0)
                                            .font(.subheadline.weight(.semibold))
                                        Text(file.1)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.appBorder, lineWidth: 1)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Update this project plan based on the latest IronClaw PRs.")
                                .font(.body)
                                .foregroundStyle(.primary)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            HStack {
                                Image(systemName: "paperclip")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Image(systemName: "arrow.up")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Color.actionPrimary, in: Circle())
                            }
                        }

                        Spacer()
                    }
                    .padding(18)
                    .background(Color.appBackground)
                    .navigationTitle("New chat")
                    .platformInlineNavigationTitle()
                }
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            await MainActor.run {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    phase = 1
                }
            }
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            await MainActor.run {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                    phase = 2
                }
            }
        }
    }
}

private struct DemoGLMAnswerView: View {
    @EnvironmentObject private var chatStore: ChatStore

    private var answer: ChatMessage? {
        chatStore.messages.first { $0.role == .assistant && $0.model == "zai-org/GLM-5.1-FP8" }
            ?? chatStore.messages.last { $0.role == .assistant }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                            .id("top")

                        if let user = chatStore.messages.first(where: { $0.role == .user }) {
                            Text(user.text)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.actionPrimary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }

                        if let answer {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    AssistantAvatar()
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("GLM 5.1")
                                            .font(.subheadline.weight(.bold))
                                        Text("NEAR Private route")
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                MarkdownMessageText(text: answer.text, sources: answer.sources)
                                    .font(.body)

                                SearchContextStrip(query: answer.searchQuery, sources: answer.sources)
                                    .id("sources")

                                DemoVerifiedProofCard()
                                    .id("proof")
                            }
                            .padding(12)
                            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.appBorder, lineWidth: 1)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
                }
                .background(Color.appBackground)
                .navigationTitle("Private GLM")
                .platformInlineNavigationTitle()
                .task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 2.8)) {
                            proxy.scrollTo("proof", anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(Color.trustVerified)
                .frame(width: 34, height: 34)
                .background(Color.trustVerified.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("GLM answer first")
                    .font(.headline.weight(.semibold))
                Text("One private model, live web sources, then proof.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DemoVerifiedProofCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.trustVerified)
                .frame(width: 36, height: 36)
                .background(Color.trustVerified.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("Verified")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.trustVerified)
                Text("Fresh proof for GLM 5.1 on the NEAR Private route. Tap the shield to inspect nonce, model hash, gateway, and signature.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.trustVerified.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.trustVerified.opacity(0.24), lineWidth: 1)
        }
    }
}

private struct DemoNearCloudModelsView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @State private var scrollTarget: String?

    private var cloudModels: [ModelOption] {
        chatStore.nearCloudModels
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header

                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(cloudModels.prefix(3))) { model in
                                DemoCloudModelRow(model: model)
                                    .id(model.id)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Route behavior")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            Label("Uses the same project files, saved links, and web context when the prompt needs them.", systemImage: "folder.badge.gearshape")
                            Label("Cloud models run through the NEAR AI Cloud privacy proxy, separate from the fully private GLM route.", systemImage: "lock.rotation")
                            Label("GLM 5.1 stays the default verified private model; Cloud is an explicit SOTA override.", systemImage: "checkmark.shield")
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .id("route-behavior")
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
                }
                .background(Color.appBackground)
                .navigationTitle("NEAR AI Cloud")
                .platformInlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {}
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Label("Connected", systemImage: "key.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.trustVerified)
                    }
                }
                .task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 1.1)) {
                            proxy.scrollTo("route-behavior", anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "cloud.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.actionPrimary)
                    .frame(width: 34, height: 34)
                    .background(Color.actionPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("SOTA models through NEAR AI Cloud")
                        .font(.headline.weight(.semibold))
                    Text("Cloud key connected · privacy proxy route")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.trustVerified)
                }
            }
            Text("The app defaults to private verified GLM, but advanced users can deliberately switch to frontier Cloud models without losing project context.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct DemoSingleModelPickerView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        Text("Search models")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(height: 38)
                }

                Section("Selected model") {
                    DemoSingleModelRow(
                        title: "GLM 5.1",
                        subtitle: "Default private model",
                        detail: "NEAR Private route · verified when proof is fresh",
                        symbolName: "checkmark.shield.fill",
                        tint: .trustVerified,
                        isSelected: true
                    )
                }

                Section("Switching modes") {
                    HStack(spacing: 10) {
                        Image(systemName: "square.grid.2x2")
                            .foregroundStyle(Color.actionPrimary)
                            .frame(width: 30, height: 30)
                            .background(Color.actionPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Council is a separate tab")
                                .font(.subheadline.weight(.semibold))
                            Text("Tap Council when you want GLM, Qwen Max, and Opus to answer together.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Model")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {}
                }
            }
        }
    }
}

private struct DemoSingleModelRow: View {
    let title: String
    let subtitle: String
    let detail: String
    let symbolName: String
    let tint: Color
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                Text(subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.trustVerified)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct DemoCloudModelRow: View {
    let model: ModelOption

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: iconName)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.actionPrimary)
                .frame(width: 30, height: 30)
                .background(Color.actionPrimary.opacity(0.09), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(model.displayName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    Text(costLabel)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(Color.appSecondaryBackground, in: Capsule())
                }
                Text(model.metadata?.modelDescription ?? "Runs through NEAR AI Cloud with privacy proxy routing.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    ForEach(Array(model.capabilityBadges.prefix(3)), id: \.self) { badge in
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(badge == "Not attested" ? Color.orange : Color.secondary)
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background(Color.appSecondaryBackground, in: Capsule())
                    }
                }
            }
        }
        .padding(12)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }

    private var iconName: String {
        let id = model.id.lowercased()
        if id.contains("claude") { return "sparkles" }
        if id.contains("gpt") { return "brain.head.profile" }
        if id.contains("gemini") { return "diamond" }
        if id.contains("kimi") { return "moon.stars" }
        if id.contains("qwen") { return "cpu" }
        return "cloud"
    }

    private var costLabel: String {
        model.id.localizedCaseInsensitiveContains("gpt-oss") ? "Open" : "Cloud"
    }
}

private struct DemoIronClawThinkingView: View {
    private let sources = [
        ("reborn-project-plan.md", "Attached plan"),
        ("#4066 lifecycle registry", "GitHub PR"),
        ("#4065 SSE replay fallback", "GitHub PR"),
        ("#4064 GitHub WASM install", "GitHub PR")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Thinking")
                        .font(.largeTitle.weight(.medium))
                        .foregroundStyle(.secondary)

                    DemoAgentTimelineStep(
                        symbolName: "folder",
                        title: "Reading attached project plan",
                        detail: "IronClaw is loading reborn-project-plan.md and the project instruction to update the plan from live GitHub evidence.",
                        chips: sources
                    )

                    DemoAgentTimelineStep(
                        symbolName: "magnifyingglass",
                        title: "Fetching latest IronClaw PRs",
                        detail: "Checking nearai/ironclaw open PRs and grouping the work into lifecycle, SSE replay, and first-party GitHub WASM milestones.",
                        chips: [
                            ("#4066", "Lifecycle"),
                            ("#4065", "SSE replay"),
                            ("#4064", "GitHub WASM")
                        ]
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Updating project plan", systemImage: "chevron.left.forwardslash.chevron.right")
                            .font(.title3.weight(.semibold))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("markdown")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text("""
                            ## Release train
                            1. Lifecycle registry (#4066)
                            2. SSE replay fallback (#4065)
                            3. GitHub WASM install (#4064)
                            4. Integration QA across activate -> replay
                            """)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.primary)
                        }
                        .padding(12)
                        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .padding(.leading, 36)

                    DemoAgentTimelineStep(
                        symbolName: "checkmark.seal",
                        title: "Preparing completed output",
                        detail: "The final answer returns what changed, why it changed, PR links, risks, and the updated plan inside the chat.",
                        chips: []
                    )
                }
                .padding(22)
            }
            .background(Color.appBackground)
            .navigationTitle("IronClaw")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {}
                }
            }
        }
    }
}

private struct DemoAgentTimelineStep: View {
    let symbolName: String
    let title: String
    let detail: String
    let chips: [(String, String)]

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbolName)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !chips.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.trustVerified.opacity(0.80))
                                    .frame(width: 18, height: 18)
                                    .overlay {
                                        Image(systemName: "arrow.up.right")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(chip.0)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                    Text(chip.1)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 42)
                            .background(Color.appSecondaryBackground, in: Capsule())
                        }
                    }
                }
            }
        }
    }
}

private struct DemoCouncilLineupView: View {
    private let models = [
        ("GLM 5.1", "Private model answer", "NEAR Private · verified", "checkmark.shield.fill"),
        ("Qwen Max", "Independent model answer", "NEAR AI Cloud · privacy proxy", "list.bullet.rectangle"),
        ("Claude Opus 4.7", "Independent model answer", "NEAR AI Cloud · privacy proxy", "sparkles")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Council lineup matches the synthesis", systemImage: "square.grid.2x2")
                            .font(.headline.weight(.semibold))
                        Text("The same Iran prompt goes to GLM, Qwen Max, and Opus 4.7; the next screen shows each view and the synthesis.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 10) {
                        ForEach(Array(models.enumerated()), id: \.offset) { index, model in
                            HStack(spacing: 12) {
                                Image(systemName: model.3)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(index == 0 ? Color.trustVerified : Color.actionPrimary)
                                    .frame(width: 34, height: 34)
                                    .background((index == 0 ? Color.trustVerified : Color.actionPrimary).opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.0)
                                        .font(.subheadline.weight(.bold))
                                    Text(model.1)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(model.2)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(index == 0 ? Color.trustVerified : .secondary)
                                    .padding(.horizontal, 8)
                                    .frame(height: 22)
                                    .background(Color.appSecondaryBackground, in: Capsule())
                            }
                            .padding(12)
                            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.appBorder, lineWidth: 1)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Synthesizer")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(Color.actionPrimary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("GLM 5.1 writes the final answer")
                                    .font(.subheadline.weight(.semibold))
                                Text("The synthesis keeps the headline, mechanics, and risks visible instead of hiding disagreement.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .padding(18)
            }
            .background(Color.appBackground)
            .navigationTitle("Council")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {}
                }
            }
        }
    }
}

private struct DemoIronClawModesView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("IronClaw")
                            .font(.title2.weight(.bold))
                        Text("Mobile for local, bounded tasks. Hosted for full workstation runs with shell, Git, tests, and GitHub.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    DemoIronClawModeCard(
                        title: "IronClaw Mobile",
                        subtitle: "Runs on the phone",
                        bodyText: "Good for reading the attached plan, drafting lightweight edits, and checking project context without connecting a workstation.",
                        chips: ["Attached plan", "Phone-safe", "No repo access"],
                        symbolName: "iphone",
                        tint: .trustVerified
                    )

                    DemoIronClawModeCard(
                        title: "Hosted IronClaw",
                        subtitle: "Connected workstation agent",
                        bodyText: "The hosted run can fetch live GitHub PRs, update the attached plan, inspect repo context, and return a concrete artifact while the phone stays the control surface.",
                        chips: ["GitHub", "Shell", "Plan update", "Repo context", "Web"],
                        symbolName: "terminal",
                        tint: .actionPrimary
                    )
                }
                .padding(18)
            }
            .background(Color.appBackground)
            .navigationTitle("Agent")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {}
                }
            }
        }
    }
}

private struct DemoIronClawModeCard: View {
    let title: String
    let subtitle: String
    let bodyText: String
    let chips: [String]
    let symbolName: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                Image(systemName: symbolName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text(bodyText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ChipFlowLayout(spacing: 7, lineSpacing: 7) {
                ForEach(chips, id: \.self) { chip in
                    Text(chip)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 9)
                        .frame(height: 26)
                        .background(tint.opacity(0.09), in: Capsule())
                }
            }
        }
        .padding(14)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 1)
        }
    }
}

private struct DemoCouncilComparisonView: View {
    @EnvironmentObject private var chatStore: ChatStore

    private var councilMessages: [ChatMessage] {
        let messages = chatStore.messages.filter { $0.councilBatchID?.isEmpty == false }
        return messages.sorted { $0.createdAt < $1.createdAt }
    }

    private var synthesis: ChatMessage? {
        councilMessages.first { $0.model == ModelOption.llmCouncilSynthesisModelID } ?? councilMessages.first
    }

    private var rawModels: [ChatMessage] {
        councilMessages.filter { $0.model != ModelOption.llmCouncilSynthesisModelID }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                            .id("top")

                        if let synthesis {
                            CouncilFocusedCard(
                                title: "Synthesis",
                                subtitle: "Combined answer with visible disagreement",
                                symbolName: "sparkles",
                                tint: .brandBlue,
                                text: synthesis.text,
                                sources: synthesis.sources,
                                searchQuery: synthesis.searchQuery
                            )
                            .id("synthesis")
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Model Differences")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)

                            ForEach(rawModels) { message in
                                CouncilFocusedCard(
                                    title: message.modelDisplayName,
                                    subtitle: modelAngle(for: message),
                                    symbolName: "cpu",
                                    tint: .trustVerified,
                                    text: message.text,
                                    sources: message.sources,
                                    searchQuery: message.searchQuery
                                )
                                .id(message.id)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 20)
                }
                .background(Color.appBackground)
                .navigationTitle("Council")
                .platformInlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {}
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Image(systemName: "rectangle.expand.vertical")
                            .foregroundStyle(Color.actionPrimary)
                            .accessibilityLabel("Expanded Council output")
                    }
                }
                .task {
                    guard let last = rawModels.last else { return }
                    try? await Task.sleep(nanoseconds: 3_200_000_000)
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 2.6)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Same prompt. Three model views. One synthesis.", systemImage: "square.grid.2x2")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
            Text("The comparison shows why Council is useful: it exposes disagreement before turning it into a better answer.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func modelAngle(for message: ChatMessage) -> String {
        switch message.model {
        case "zai-org/GLM-5.1-FP8":
            return "Private model answer"
        case ModelOption.nearCloudQwenMaxModelID:
            return "Independent model answer"
        case "near-cloud/anthropic/claude-opus-4-7":
            return "Independent model answer"
        default:
            return "Raw model view"
        }
    }
}

private struct DemoIronClawResultView: View {
    @EnvironmentObject private var chatStore: ChatStore

    private var userMessage: ChatMessage? {
        chatStore.messages.first { $0.role == .user }
    }

    private var resultMessage: ChatMessage? {
        chatStore.messages.first { $0.role == .assistant && $0.model == ModelOption.ironclawModelID }
            ?? chatStore.messages.last { $0.role == .assistant }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                            .id("top")

                        if let userMessage {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Task")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                Text(userMessage.text)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(12)
                            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }

                        if let resultMessage {
                            CouncilFocusedCard(
                                title: "Hosted IronClaw",
                                subtitle: "Completed agent output returned to chat",
                                symbolName: "terminal",
                                tint: .brandBlue,
                                text: resultMessage.text,
                                sources: resultMessage.sources,
                                searchQuery: resultMessage.searchQuery
                            )
                            .id("result")
                        }

                        HStack(spacing: 8) {
                            Label("IronClaw Reborn Plan", systemImage: "folder")
                            Label("reborn-project-plan.md", systemImage: "paperclip")
                            Label("3 PRs", systemImage: "link")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .id("bottom")
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 20)
                }
                .background(Color.appBackground)
                .navigationTitle("IronClaw")
                .platformInlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {}
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Image(systemName: "rectangle.expand.vertical")
                            .foregroundStyle(Color.actionPrimary)
                            .accessibilityLabel("Expanded IronClaw output")
                    }
                }
                .task {
                    try? await Task.sleep(nanoseconds: 2_200_000_000)
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 2.8)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("IronClaw ran against project context.", systemImage: "terminal")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
            Text("This is the completed hosted-agent result, not a setup screen. It updates the attached plan from the latest IronClaw GitHub PRs and returns the artifact into the conversation.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CouncilFocusedCard: View {
    let title: String
    let subtitle: String
    let symbolName: String
    let tint: Color
    let text: String
    var sources: [WebSearchSource] = []
    var searchQuery: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbolName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            MarkdownMessageText(text: text, sources: sources)
                .font(.subheadline)
                .lineSpacing(2)

            if !sources.isEmpty {
                SearchContextStrip(query: searchQuery, sources: sources)
            }
        }
        .padding(12)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        }
    }
}
#endif
