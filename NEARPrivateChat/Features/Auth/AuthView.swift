import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension Notification.Name {
    /// Posted whenever AuthView toggles the inline terms-acceptance checkbox.
    /// RootView promotes the pending acceptance into the per-account record
    /// when this fires, so a signed-in-but-terms-pending user is moved from
    /// AuthView to AppShellView without re-signing.
    static let legalTermsAcceptanceDidChange = Notification.Name("legalTermsAcceptanceDidChange")
}

/// Auth screen.
///
/// Single-column iPhone layout (390x844):
///   - Top: NEAR mark + wordmark + concise product promise.
///   - Spacer pushes the rest to the bottom (`margin-top: auto` in CSS).
///   - Bottom: terms row card, three provider buttons, "Open shared link"
///     quiet button, debug-only "More sign-in options" disclosure (DEBUG
///     builds only), monospaced footer URL.
///
/// Terms acceptance is integrated here. RootView routes a signed-in user
/// whose terms have not been accepted back to this screen (with a pending
/// state) instead of routing to a separate `LegalTermsRequiredView`.
struct AuthView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var chatStore: ChatStore

    @State private var showingLegalTerms = false
    @State private var showingSharedLink = false
    @State private var hasAcceptedLegalTerms = LegalTermsAcceptanceStore.hasPendingCurrentVersion()

    // Token sign-in is available in Release as a fallback: the hosted OAuth and
    // wallet flows can't complete on device until the backend allowlists the
    // app's callback, so a session token captured from a working web sign-in is
    // the dependable path. See WebSignInView for the in-app web-login harvest.
    @State private var showingTokenLogin = false
    @State private var showingWebSignIn = false
    @State private var showingNearAccountSignIn = false
    @State private var token = ""

    #if DEBUG
    @State private var showingMoreSignInOptions = false
    #endif

    var body: some View {
        VStack(spacing: 0) {
            // Top — mark + headline, centered with enough air to feel calm
            // without pushing the action stack too low on small phones.
            VStack(spacing: 20) {
                Image("NearMark")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .shadow(color: Color.brandBlue.opacity(0.16), radius: 14, y: 6)
                    .accessibilityHidden(true)

                ProductWordmark(alignment: .center, scale: 0.9)
                    .frame(maxWidth: 280)

                Text("Sign in to start private chat: write, code, research, summarize files, and turn messy context into actions.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 310)
            }
            .padding(.top, 44)
            .frame(maxWidth: .infinity)

            // Spacer pushes terms + providers to the bottom of the screen
            // (spec uses `margin-top: auto` on the bottom block).
            Spacer(minLength: 20)

            // Bottom — terms row, providers, utility actions, footer.
            VStack(spacing: 12) {
                TermsRowCard(
                    isAccepted: hasAcceptedLegalTerms,
                    onToggle: {
                        let next = !hasAcceptedLegalTerms
                        updateLegalTermsAcceptance(next)
                    },
                    onReadTerms: { showingLegalTerms = true }
                )

                VStack(spacing: 8) {
                    // All three providers open the real private.near.ai login in
                    // an in-app web view (WebSignInView), where the chosen method
                    // actually completes and the app adopts the resulting
                    // session. The native OAuth redirect can't finish on device
                    // (the backend doesn't allowlist the app's callback), so
                    // every button routes through the web harvest instead.
                    AuthProviderButton(
                        provider: .near,
                        isLoading: false,
                        isEnabled: canStartSignIn
                    ) {
                        showingWebSignIn = true
                    }
                    AuthProviderButton(
                        provider: .google,
                        isLoading: false,
                        isEnabled: canStartSignIn
                    ) {
                        showingWebSignIn = true
                    }
                    AuthProviderButton(
                        provider: .github,
                        isLoading: false,
                        isEnabled: canStartSignIn
                    ) {
                        showingWebSignIn = true
                    }
                }

                Button {
                    showingSharedLink = true
                } label: {
                    Label("Open shared link", systemImage: "link")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                        .labelStyle(.titleAndIcon)
                        .frame(height: 42)
                        .frame(maxWidth: .infinity)
                        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.appBorder, lineWidth: 1)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                if hasAcceptedLegalTerms {
                    Button {
                        showingTokenLogin = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "key.fill")
                                .font(.footnote.weight(.semibold))
                            Text("Sign in with a session token")
                                .font(.footnote.weight(.semibold))
                        }
                        .foregroundStyle(Color.actionPrimary)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.actionPrimary.opacity(0.18), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("auth.tokenSignIn")

                    Button {
                        showingNearAccountSignIn = true
                    } label: {
                        Text("Sign in with a NEAR account key")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color.textSecondary)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("auth.nearAccountSignIn")

                    #if DEBUG
                    DebugMoreSignInOptions(
                        isOpen: $showingMoreSignInOptions,
                        isEnabled: true,
                        onSelectToken: { showingTokenLogin = true }
                    )
                    #endif
                }

                Text("https://private.near.ai")
                    .font(.footnote)
                    .fontDesign(.monospaced)
                    .fontWeight(.regular)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground.ignoresSafeArea())
        .sheet(isPresented: $showingLegalTerms) {
            LegalTermsSheet()
        }
        .sheet(isPresented: $showingSharedLink) {
            SharedConversationSheet(
                onOpenForWriting: { snapshot in
                    chatStore.openSharedPreviewForWriting(snapshot)
                },
                onCopyAndContinue: { snapshot in
                    chatStore.cloneConversation(snapshot.conversation)
                }
            )
        }
        .sheet(isPresented: $showingWebSignIn) {
            WebSignInView(
                onHarvest: { token, sessionID in
                    showingWebSignIn = false
                    sessionStore.adoptSession(token: token, sessionID: sessionID, isNewUser: false)
                },
                onCancel: { showingWebSignIn = false }
            )
        }
        .sheet(isPresented: $showingNearAccountSignIn) {
            NearAccountSignInView()
        }
        .sheet(isPresented: $showingTokenLogin) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Paste a session token from a signed-in private.near.ai session. On a Mac: sign in at private.near.ai, open DevTools → Application → Local Storage / Cookies and copy the session token. The token authenticates the private route directly.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    SecureField("session token", text: $token)
                        .tokenInputTraits()
                        .padding(12)
                        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Button {
                        if let pasted = UIPasteboard.general.string {
                            token = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Label("Paste from clipboard", systemImage: "doc.on.clipboard")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.actionPrimary)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(Color.actionTint, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding()
                .navigationTitle("Sign in with token")
                .platformInlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingTokenLogin = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Sign In") {
                            sessionStore.signInWithToken(token)
                            showingTokenLogin = false
                        }
                        .disabled(!hasAcceptedLegalTerms || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .platformMediumDetent()
        }
    }

    private var canStartSignIn: Bool {
        hasAcceptedLegalTerms && !sessionStore.isAuthenticating
    }

    private func updateLegalTermsAcceptance(_ accepted: Bool) {
        hasAcceptedLegalTerms = accepted
        if accepted {
            LegalTermsAcceptanceStore.recordPendingAcceptance()
        } else {
            LegalTermsAcceptanceStore.clearPendingAcceptance()
        }
        // LegalTermsAcceptanceStore posts `.legalTermsAcceptanceDidChange`
        // on both record and clear; RootView observes it to promote a
        // pending acceptance into the per-account record.
    }
}

// MARK: - Hero card (compatibility shim for non-Auth surfaces)

/// Mark + headline block used by auth-adjacent surfaces.
struct AuthHeroCard: View {
    var body: some View {
        VStack(spacing: 20) {
            Image("NearMark")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .shadow(color: Color.brandBlue.opacity(0.16), radius: 14, y: 6)
                .accessibilityHidden(true)

            ProductWordmark(alignment: .center, scale: 0.9)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Terms row

private struct TermsRowCard: View {
    let isAccepted: Bool
    let onToggle: () -> Void
    let onReadTerms: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                CheckBox(isOn: isAccepted)

                Text("I agree to the Terms and Privacy Policy")
                    .font(.system(.footnote, design: .rounded).weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onReadTerms) {
                    Text("Read")
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .foregroundStyle(Color.actionPrimary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Read terms")
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isAccepted ? Color.actionPrimary.opacity(0.22) : Color.appBorder, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isAccepted ? "Terms accepted" : "Agree to terms and privacy")
        .accessibilityAddTraits(isAccepted ? [.isSelected, .isButton] : [.isButton])
    }
}

private struct CheckBox: View {
    let isOn: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isOn ? Color.actionPrimary : .clear)
            .frame(width: 22, height: 22)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isOn ? Color.actionPrimary : Color.textTertiary, lineWidth: 1.5)
            }
            .overlay {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .animation(.easeOut(duration: 0.16), value: isOn)
    }
}

// MARK: - Provider button

private struct AuthProviderButton: View {
    let provider: OAuthProvider
    let isLoading: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        Button(action: action) {
            HStack(spacing: 12) {
                ProviderGlyph(provider: provider, tint: isEnabled ? .white : Color.textSecondary)
                    .frame(width: 20, height: 20)

                Text(provider.title)
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .frame(maxWidth: .infinity)

                // Right-side spacer matches glyph width + leading gap so the
                // label sits optically centered.
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(isEnabled ? .white : Color.textSecondary)
                        .frame(width: 20, height: 20)
                } else {
                    Color.clear.frame(width: 20, height: 20)
                }
            }
            .foregroundStyle(isEnabled ? .white : Color.textSecondary)
            .padding(.horizontal, 18)
            .frame(height: 50)
            .frame(maxWidth: .infinity)
            .background(
                (isEnabled ? Color.actionPrimary : Color.appPanelBackground),
                in: shape
            )
            .overlay {
                shape.stroke(isEnabled ? Color.clear : Color.appBorder, lineWidth: 1)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .accessibilityLabel(provider.title)
    }
}

/// Real brand glyphs for each provider, rendered monochrome white on the
/// brand-blue button per the auth screen's house style. The shapes themselves
/// are the canonical brand marks (NEAR letterform, Google "G", GitHub
/// Octocat), not generic SF Symbol placeholders.
private struct ProviderGlyph: View {
    let provider: OAuthProvider
    let tint: Color

    var body: some View {
        switch provider {
        case .near:
            // The official NEAR mark from brand guidelines, rendered as a
            // tintable template.
            Image("NearGlyph")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(tint)
        case .google:
            GoogleGGlyph()
                .fill(tint)
        case .github:
            GitHubOctocatGlyph()
                .fill(tint)
        }
    }
}

/// Google "G" letterform — single-fill monochrome rendering of the canonical
/// Google G shape.
private struct GoogleGGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let s = min(rect.width, rect.height)
        let ox = rect.minX + (rect.width - s) / 2
        let oy = rect.minY + (rect.height - s) / 2
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + (x / 24) * s, y: oy + (y / 24) * s)
        }
        // Adapted from Material Icons "google" (24x24 viewBox).
        path.move(to: pt(21.35, 11.1))
        path.addLine(to: pt(12.18, 11.1))
        path.addLine(to: pt(12.18, 13.83))
        path.addLine(to: pt(18.69, 13.83))
        path.addCurve(to: pt(12.18, 19.5),
                      control1: pt(18.36, 17.64),
                      control2: pt(15.19, 19.5))
        path.addCurve(to: pt(5.34, 12.66),
                      control1: pt(8.4, 19.5),
                      control2: pt(5.34, 16.44))
        path.addCurve(to: pt(12.18, 5.82),
                      control1: pt(5.34, 8.88),
                      control2: pt(8.4, 5.82))
        path.addCurve(to: pt(16.62, 7.4),
                      control1: pt(13.91, 5.82),
                      control2: pt(15.4, 6.41))
        path.addLine(to: pt(18.71, 5.31))
        path.addCurve(to: pt(12.18, 2.74),
                      control1: pt(16.91, 3.71),
                      control2: pt(14.65, 2.74))
        path.addCurve(to: pt(2.27, 12.66),
                      control1: pt(6.7, 2.74),
                      control2: pt(2.27, 7.17))
        path.addCurve(to: pt(12.18, 22.58),
                      control1: pt(2.27, 18.15),
                      control2: pt(6.7, 22.58))
        path.addCurve(to: pt(21.95, 12.66),
                      control1: pt(17.81, 22.58),
                      control2: pt(21.95, 18.6))
        path.addCurve(to: pt(21.84, 11.34),
                      control1: pt(21.95, 12.21),
                      control2: pt(21.91, 11.78))
        path.closeSubpath()
        return path
    }
}

/// GitHub Octocat silhouette — single-fill canonical brand mark.
/// Path adapted from the public GitHub mark (24x24 viewBox).
private struct GitHubOctocatGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let s = min(rect.width, rect.height)
        let ox = rect.minX + (rect.width - s) / 2
        let oy = rect.minY + (rect.height - s) / 2
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + (x / 24) * s, y: oy + (y / 24) * s)
        }
        path.move(to: pt(12, 1.5))
        path.addCurve(to: pt(1.5, 12),
                      control1: pt(6.2, 1.5),
                      control2: pt(1.5, 6.2))
        path.addCurve(to: pt(8.7, 21.95),
                      control1: pt(1.5, 16.7),
                      control2: pt(4.55, 20.62))
        path.addCurve(to: pt(9.4, 21.45),
                      control1: pt(9.2, 22.05),
                      control2: pt(9.4, 21.75))
        path.addLine(to: pt(9.4, 19.65))
        path.addCurve(to: pt(5.9, 18.25),
                      control1: pt(6.5, 20.25),
                      control2: pt(5.9, 18.25))
        path.addCurve(to: pt(4.7, 16.75),
                      control1: pt(5.4, 17.05),
                      control2: pt(4.7, 16.75))
        path.addCurve(to: pt(4.8, 16.15),
                      control1: pt(3.8, 16.05),
                      control2: pt(4.8, 16.15))
        path.addCurve(to: pt(6.4, 17.25),
                      control1: pt(5.8, 16.25),
                      control2: pt(6.4, 17.25))
        path.addCurve(to: pt(9.5, 18.15),
                      control1: pt(7.3, 18.85),
                      control2: pt(8.9, 18.35))
        path.addCurve(to: pt(10.2, 16.75),
                      control1: pt(9.6, 17.45),
                      control2: pt(9.9, 16.95))
        path.addCurve(to: pt(5.4, 11.55),
                      control1: pt(7.9, 16.45),
                      control2: pt(5.4, 15.55))
        path.addCurve(to: pt(6.5, 8.75),
                      control1: pt(5.4, 10.35),
                      control2: pt(5.8, 9.45))
        path.addCurve(to: pt(6.6, 5.85),
                      control1: pt(6.4, 8.45),
                      control2: pt(6, 7.35))
        path.addCurve(to: pt(9.6, 6.85),
                      control1: pt(6.6, 5.85),
                      control2: pt(7.5, 5.55))
        path.addCurve(to: pt(15.1, 6.85),
                      control1: pt(11.7, 6.25),
                      control2: pt(13.4, 6.25))
        path.addCurve(to: pt(18.1, 5.85),
                      control1: pt(17.2, 5.45),
                      control2: pt(18.1, 5.85))
        path.addCurve(to: pt(18.2, 8.75),
                      control1: pt(18.7, 7.35),
                      control2: pt(18.3, 8.45))
        path.addCurve(to: pt(19.3, 11.55),
                      control1: pt(18.9, 9.45),
                      control2: pt(19.3, 10.35))
        path.addCurve(to: pt(14.5, 16.75),
                      control1: pt(19.3, 15.55),
                      control2: pt(16.9, 16.45))
        path.addCurve(to: pt(15.2, 18.75),
                      control1: pt(14.9, 17.05),
                      control2: pt(15.2, 17.65))
        path.addLine(to: pt(15.2, 21.75))
        path.addCurve(to: pt(15.9, 21.95),
                      control1: pt(15.2, 22.05),
                      control2: pt(15.4, 22.15))
        path.addCurve(to: pt(22.5, 12),
                      control1: pt(20.05, 20.6),
                      control2: pt(22.5, 16.7))
        path.addCurve(to: pt(12, 1.5),
                      control1: pt(22.5, 6.2),
                      control2: pt(17.8, 1.5))
        path.closeSubpath()
        return path
    }
}

// MARK: - Debug disclosure

#if DEBUG
private struct DebugMoreSignInOptions: View {
    @Binding var isOpen: Bool
    let isEnabled: Bool
    let onSelectToken: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Button {
                withAnimation(.easeOut(duration: 0.22)) { isOpen.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("More sign-in options")
                        .font(.subheadline)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .foregroundStyle(Color.textTertiary)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                Button(action: onSelectToken) {
                    HStack(spacing: 12) {
                        Image(systemName: "key")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.actionPrimary)
                            .frame(width: 28, height: 28)
                            .background(Color.actionTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Developer session token")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            Text("DEBUG · paste a session JWT")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(Color.textTertiary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.textTertiary)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                            .foregroundStyle(Color.appBorder)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1 : 0.6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
#endif

// MARK: - Legal terms sheet (unchanged, integrated here as before)

struct LegalTermsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("NEAR Private Chat iOS Terms")
                            .font(.title2.weight(.bold))
                        Text("Effective \(LegalTerms.effectiveDate) - Version \(LegalTerms.version)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("Full draft: \(LegalTerms.appTermsDocumentName)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(LegalTerms.signupSummary, id: \.self) { item in
                            Label(item, systemImage: "checkmark.circle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(LegalTerms.sections) { section in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(section.title)
                                    .font(.headline)
                                Text(section.body)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Divider()
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Link("NEAR AI Services Terms", destination: LegalTerms.nearAIServicesTermsURL)
                        Link("NEAR AI Cloud Terms", destination: LegalTerms.nearAICloudTermsURL)
                        Link("NEAR AI Acceptable Use Policy", destination: LegalTerms.nearAIAcceptableUseURL)
                        Link("NEAR AI Privacy Policy", destination: LegalTerms.nearAIPrivacyPolicyURL)
                        Link("IronClaw repository and licenses", destination: LegalTerms.ironclawRepositoryURL)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.brandBlue)
                }
                .padding()
            }
            .navigationTitle("Terms")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .platformMediumDetent()
    }
}
