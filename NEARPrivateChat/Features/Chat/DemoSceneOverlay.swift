import SwiftUI

#if DEBUG
struct DemoSceneOverlay: View {
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
                // Match the blue selection language used by every other focus
                // box; a lone orange ring read as a stuck/foreign highlight.
                DemoFocusBox(delay: 1.1, duration: 2.2, x: 0.08, y: 0.35, width: 0.84, height: 0.18, tint: .actionPrimary)
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
#endif
