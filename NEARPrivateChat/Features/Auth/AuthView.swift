import SwiftUI

extension Notification.Name {
    /// Posted whenever AuthView toggles the inline terms-acceptance checkbox.
    /// RootView promotes the pending acceptance into the per-account record
    /// when this fires, so a signed-in-but-terms-pending user is moved from
    /// AuthView to AppShellView without re-signing.
    static let legalTermsAcceptanceDidChange = Notification.Name("legalTermsAcceptanceDidChange")
}

/// Auth screen — Claude Design v2 spec.
///
/// Single-column iPhone layout (390x844):
///   - Top: 48x48 NEAR mark + headline "Private AI with verifiable answers."
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

    #if DEBUG
    @State private var showingMoreSignInOptions = false
    @State private var showingTokenLogin = false
    @State private var token = ""
    #endif

    var body: some View {
        VStack(spacing: 0) {
            // Top — mark + headline, centered with 56pt top padding.
            VStack(spacing: 28) {
                Image("NearMark")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)

                Text("Private AI with verifiable answers.")
                    .font(.system(size: 26, weight: .semibold))
                    .tracking(-0.5)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(32 - 26)
                    .frame(maxWidth: 280)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 56)
            .frame(maxWidth: .infinity)

            // Spacer pushes terms + providers to the bottom of the screen
            // (spec uses `margin-top: auto` on the bottom block).
            Spacer(minLength: 24)

            // Bottom — terms row, providers, utility actions, footer.
            VStack(spacing: 14) {
                TermsRowCard(
                    isAccepted: hasAcceptedLegalTerms,
                    onToggle: {
                        let next = !hasAcceptedLegalTerms
                        updateLegalTermsAcceptance(next)
                    },
                    onReadTerms: { showingLegalTerms = true }
                )

                VStack(spacing: 10) {
                    AuthProviderButton(
                        provider: .near,
                        isLoading: sessionStore.isAuthenticating,
                        isEnabled: canStartSignIn
                    ) {
                        sessionStore.signIn(with: .near)
                    }
                    AuthProviderButton(
                        provider: .google,
                        isLoading: sessionStore.isAuthenticating,
                        isEnabled: canStartSignIn
                    ) {
                        sessionStore.signIn(with: .google)
                    }
                    AuthProviderButton(
                        provider: .github,
                        isLoading: sessionStore.isAuthenticating,
                        isEnabled: canStartSignIn
                    ) {
                        sessionStore.signIn(with: .github)
                    }
                }

                Button {
                    showingSharedLink = true
                } label: {
                    Text("Open shared link")
                        .font(.system(size: 15, weight: .regular))
                        .tracking(-0.1)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                #if DEBUG
                DebugMoreSignInOptions(
                    isOpen: $showingMoreSignInOptions,
                    isEnabled: hasAcceptedLegalTerms,
                    onSelectToken: { showingTokenLogin = true }
                )
                #endif

                Text("https://private.near.ai")
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 18)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground.ignoresSafeArea())
        .sheet(isPresented: $showingLegalTerms) {
            LegalTermsSheet()
        }
        .sheet(isPresented: $showingSharedLink) {
            SharedConversationSheet()
                .environmentObject(chatStore)
        }
        #if DEBUG
        .sheet(isPresented: $showingTokenLogin) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Session Token")
                        .font(.headline)
                    SecureField("Paste token", text: $token)
                        .tokenInputTraits()
                        .padding(12)
                        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))
                    Spacer()
                }
                .padding()
                .navigationTitle("Developer Sign In")
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
        #endif
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

/// Mark + headline block used by surfaces that historically reused the Auth
/// hero (LegalTermsRequiredView, DemoCaptureViews). AuthView itself inlines
/// the same composition per the v2 spec.
struct AuthHeroCard: View {
    var body: some View {
        VStack(spacing: 28) {
            Image("NearMark")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)

            Text("Private AI with verifiable answers.")
                .font(.system(size: 26, weight: .semibold))
                .tracking(-0.5)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineSpacing(32 - 26)
                .frame(maxWidth: 280)
                .fixedSize(horizontal: false, vertical: true)
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
            HStack(spacing: 10) {
                CheckBox(isOn: isAccepted)

                Text("I agree to the Terms and Privacy")
                    .font(.system(size: 13, weight: .regular))
                    .tracking(-0.08)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onReadTerms) {
                    Text("Read terms")
                        .font(.system(size: 13, weight: .medium))
                        .tracking(-0.08)
                        .foregroundStyle(Color.actionPrimary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Read terms")
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.appBorder, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            .frame(width: 20, height: 20)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isOn ? Color.actionPrimary : Color.textTertiary, lineWidth: 1.5)
            }
            .overlay {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
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
        Button(action: action) {
            HStack(spacing: 12) {
                ProviderGlyph(provider: provider, tint: isEnabled ? .white : Color.textTertiary)
                    .frame(width: 20, height: 20)

                Text(provider.title)
                    .font(.system(size: 16, weight: .semibold))
                    .tracking(-0.2)
                    .frame(maxWidth: .infinity)

                // Right-side spacer matches glyph width + leading gap so the
                // label sits optically centered.
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(isEnabled ? .white : Color.textTertiary)
                        .frame(width: 20, height: 20)
                } else {
                    Color.clear.frame(width: 20, height: 20)
                }
            }
            .foregroundStyle(isEnabled ? .white : Color.textTertiary)
            .padding(.horizontal, 18)
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            .background(
                (isEnabled ? Color.actionPrimary : Color.appSecondaryBackground),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .accessibilityLabel(provider.title)
    }
}

/// Monochrome white SVG-style glyphs, 20pt, drawn with SF Symbols and SwiftUI
/// `Path` so the visual stays close to the Claude Design house-rule
/// (white-on-blue across all three providers).
private struct ProviderGlyph: View {
    let provider: OAuthProvider
    let tint: Color

    var body: some View {
        switch provider {
        case .near:
            NearNGlyph()
                .stroke(tint, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
        case .google:
            // Stylized monochrome "G" — outline path mirrors Claude Design's
            // single-color treatment for visual uniformity. Apple HIG
            // recommends the multi-color G; revisit if review flags it.
            Image(systemName: "g.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(tint)
        case .github:
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(tint)
        }
    }
}

/// The "N" zig-zag from the Claude Design spec.
/// SVG path: M 6 19 V 5 L 18 19 V 5 — drawn into a 20x20 square.
private struct NearNGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        // Map original 24-unit viewBox coords (6,5,18,19) into rect.
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + (x / 24) * w, y: rect.minY + (y / 24) * h)
        }
        path.move(to: pt(6, 19))
        path.addLine(to: pt(6, 5))
        path.addLine(to: pt(18, 19))
        path.addLine(to: pt(18, 5))
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
                        .font(.system(size: 14, weight: .regular))
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
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("DEBUG · paste a session JWT")
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
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
