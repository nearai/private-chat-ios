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
///   - Bottom: terms row card, hosted session-login button, "Open shared
///     link" quiet button, fallback sign-in disclosure, monospaced footer URL.
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

    // The primary path opens the hosted session-login page in-app so mobile
    // mirrors the web session flow. Provider-specific web routes, token paste,
    // and local NEAR account signing stay available as fallback routes.
    @State private var showingTokenLogin = false
    @State private var webSignInRoute: WebSignInRoute?
    @State private var showingNearAccountSignIn = false
    @State private var showingMoreSignInOptions = false
    @State private var token = ""
    @State private var tokenErrorMessage: String?

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
                    .clipShape(RoundedRectangle.app(AppRadius.control))
                    .shadow(color: Color.brandAccent.opacity(0.16), radius: 14, y: 6)
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

                HostedSessionSignInButton(
                    isLoading: sessionStore.isAuthenticating,
                    isEnabled: canStartSignIn
                ) {
                    openWebSignIn()
                }
                .accessibilityIdentifier("auth.primaryWebSession")

                if !hasAcceptedLegalTerms {
                    Text("Accept the terms above to continue.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("auth.termsRequiredHint")
                }

                Button {
                    showingSharedLink = true
                } label: {
                    Label("Open shared link", systemImage: "link")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                        .labelStyle(.titleAndIcon)
                        .frame(minHeight: 44)
                        .frame(maxWidth: .infinity)
                        .background(Color.appPanelBackground, in: RoundedRectangle.app(AppRadius.pill))
                        .overlay {
                            RoundedRectangle.app(AppRadius.pill)
                                .stroke(Color.appBorder, lineWidth: 1)
                        }
                        .contentShape(RoundedRectangle.app(AppRadius.pill))
                }
                .buttonStyle(.plain)

                MoreSignInOptions(
                    isOpen: $showingMoreSignInOptions,
                    isEnabled: hasAcceptedLegalTerms,
                    onSelectProvider: { provider in
                        openWebSignIn(WebSignInView.hostedSignInURL(for: provider))
                    },
                    onSelectToken: { showingTokenLogin = true },
                    onSelectNearAccount: { showingNearAccountSignIn = true }
                )

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
        .sheet(item: $webSignInRoute) { route in
            WebSignInView(
                url: route.url,
                onHarvest: { session in
                    webSignInRoute = nil
                    sessionStore.adoptSession(session)
                },
                onCancel: { webSignInRoute = nil }
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
                        .background(Color.appSecondaryBackground, in: RoundedRectangle.app(AppRadius.pill))
                        .overlay {
                            RoundedRectangle.app(AppRadius.pill)
                                .stroke(tokenErrorMessage == nil ? Color.clear : Color.proofMismatch, lineWidth: 1)
                        }
                        .accessibilityLabel("Session token")
                        .accessibilityHint("Paste the session token value from private.near.ai, not a URL or account name.")
                        .accessibilityIdentifier("auth.tokenField")
                        .onChange(of: token) { _, _ in
                            tokenErrorMessage = nil
                        }

                    if let tokenErrorMessage {
                        Text(tokenErrorMessage)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color.proofMismatch)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("auth.tokenFieldError")
                    }

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
                    .accessibilityHint("Copies text from the system clipboard into the session token field.")
                    .accessibilityIdentifier("auth.pasteTokenFromClipboard")

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
                            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
                            if let error = authTokenValidationMessage(trimmed) {
                                tokenErrorMessage = error
                                return
                            }
                            sessionStore.signInWithToken(trimmed)
                            showingTokenLogin = false
                        }
                        .disabled(!hasAcceptedLegalTerms || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityHint(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Paste a session token before signing in." : "Signs in with the pasted session token.")
                        .accessibilityIdentifier("auth.confirmTokenSignIn")
                    }
                }
            }
            .platformMediumDetent()
        }
    }

    private var canStartSignIn: Bool {
        hasAcceptedLegalTerms && !sessionStore.isAuthenticating
    }

    private func openWebSignIn(_ url: URL = WebSignInView.loginURL) {
        webSignInRoute = WebSignInRoute(url: url)
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

private struct WebSignInRoute: Identifiable {
    let id = UUID()
    let url: URL
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
                .clipShape(RoundedRectangle.app(AppRadius.control))
                .shadow(color: Color.brandAccent.opacity(0.16), radius: 14, y: 6)
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
                .accessibilityHint("Opens the legal terms before you accept.")
                .accessibilityIdentifier("auth.readTerms")
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(Color.appPanelBackground, in: RoundedRectangle.app(AppRadius.pill))
            .overlay {
                RoundedRectangle.app(AppRadius.pill)
                    .stroke(isAccepted ? Color.actionPrimary.opacity(0.22) : Color.appBorder, lineWidth: 1)
            }
            .contentShape(RoundedRectangle.app(AppRadius.pill))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isAccepted ? "Terms accepted" : "Agree to terms and privacy")
        .accessibilityHint(isAccepted ? "Double tap to clear terms acceptance." : "Double tap to accept before signing in.")
        .accessibilityAddTraits(isAccepted ? [.isSelected, .isButton] : [.isButton])
        .accessibilityIdentifier("auth.acceptTerms")
    }
}

private struct CheckBox: View {
    let isOn: Bool

    var body: some View {
        RoundedRectangle.app(AppRadius.pill)
            .fill(isOn ? Color.actionPrimary : .clear)
            .frame(width: 22, height: 22)
            .overlay {
                RoundedRectangle.app(AppRadius.pill)
                    .strokeBorder(isOn ? Color.actionPrimary : Color.textTertiary, lineWidth: 1.5)
            }
            .overlay {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            .animation(.easeOut(duration: 0.16), value: isOn)
    }
}

// MARK: - Primary hosted session button

private struct HostedSessionSignInButton: View {
    let isLoading: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle.app(AppRadius.pill)

        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isEnabled ? .white : Color.textSecondary)
                    .frame(width: 24, height: 24)

                VStack(spacing: 2) {
                    Text("Sign in")
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                    Text("Open private.near.ai session login")
                        .font(.system(.caption2, design: .rounded).weight(.medium))
                        .opacity(0.82)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .frame(maxWidth: .infinity)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(isEnabled ? .white : Color.textSecondary)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "arrow.up.forward")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(isEnabled ? .white.opacity(0.9) : Color.textTertiary)
                        .frame(width: 24, height: 24)
                }
            }
            .foregroundStyle(isEnabled ? .white : Color.textSecondary)
            .padding(.horizontal, 18)
            .frame(height: 54)
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
        .accessibilityLabel("Sign in")
        .accessibilityHint(isEnabled ? "Opens the private.near.ai session login page inside the app." : "Accept the terms above to continue.")
        .accessibilityIdentifier("auth.openHostedSessionSignIn")
    }
}

private func authTokenValidationMessage(_ token: String) -> String? {
    guard !token.isEmpty else {
        return "Paste the token value from private.near.ai."
    }
    if token.contains("://") || token.hasPrefix("private.near.ai") {
        return "Paste the session token value, not the private.near.ai URL."
    }
    if token.contains(where: { $0.isWhitespace }) {
        return "Paste one token value without spaces or extra copied text."
    }
    if token.hasSuffix(".near") || token.hasSuffix(".testnet") {
        return "This looks like an account ID. Use Continue with NEAR for wallet sign-in."
    }
    return nil
}

// MARK: - Fallback sign-in disclosure

private struct MoreSignInOptions: View {
    @Binding var isOpen: Bool
    let isEnabled: Bool
    let onSelectProvider: (OAuthProvider) -> Void
    let onSelectToken: () -> Void
    let onSelectNearAccount: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Button {
                withAnimation(.easeOut(duration: 0.22)) { isOpen.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("More ways to sign in")
                        .font(.subheadline)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .foregroundStyle(Color.textTertiary)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .minimumTouchTarget()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.58)
            .accessibilityLabel("More ways to sign in")
            .accessibilityHint(isEnabled ? "Shows provider, token, and local NEAR account sign-in options." : "Accept the terms above before using fallback sign-in methods.")
            .accessibilityIdentifier("auth.moreSignInOptions")

            if isOpen {
                VStack(spacing: 8) {
                    fallbackButton(
                        title: "NEAR wallet",
                        subtitle: "Open NEAR wallet sign-in",
                        symbolName: "hexagon",
                        identifier: "auth.provider.near",
                        action: { onSelectProvider(.near) }
                    )

                    fallbackButton(
                        title: "Google",
                        subtitle: "Sign in through private.near.ai",
                        symbolName: "g.circle",
                        identifier: "auth.provider.google",
                        action: { onSelectProvider(.google) }
                    )

                    fallbackButton(
                        title: "GitHub",
                        subtitle: "Sign in through private.near.ai",
                        symbolName: "chevron.left.forwardslash.chevron.right",
                        identifier: "auth.provider.github",
                        action: { onSelectProvider(.github) }
                    )

                    fallbackButton(
                        title: "Session token",
                        subtitle: "Paste a token from private.near.ai",
                        symbolName: "key",
                        identifier: "auth.tokenSignIn",
                        action: onSelectToken
                    )

                    fallbackButton(
                        title: "NEAR account key",
                        subtitle: "Sign in locally with your NEAR wallet — no web",
                        symbolName: "lock.rotation",
                        identifier: "auth.nearAccountSignIn",
                        action: onSelectNearAccount
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func fallbackButton(
        title: String,
        subtitle: String,
        symbolName: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbolName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.actionPrimary)
                    .frame(width: 28, height: 28)
                    .background(Color.actionTint, in: RoundedRectangle.app(AppRadius.pill))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .minimumTouchTarget()
            .background(Color.appSecondaryBackground, in: RoundedRectangle.app(AppRadius.pill))
            .overlay {
                RoundedRectangle.app(AppRadius.pill)
                    .stroke(Color.appBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.6)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .accessibilityIdentifier(identifier)
    }
}

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
                    .foregroundStyle(Color.brandAccent)
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
