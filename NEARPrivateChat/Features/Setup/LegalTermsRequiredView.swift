import SwiftUI

struct LegalTermsRequiredView: View {
    let onAccept: () -> Void
    @State private var showingTerms = false
    @State private var hasReviewedTerms = false
    @State private var hasConfirmedTerms = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                AuthHeroCard()

                VStack(alignment: .leading, spacing: 14) {
                    Label("Terms update required", systemImage: "doc.text.magnifyingglass")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)

                    Text("Review the current terms, then confirm acceptance before using private chat, Cloud models, files, sharing, web grounding, Council, or agent tools.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(LegalTerms.signupSummary, id: \.self) { item in
                            Label(item, systemImage: "checkmark.circle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        if hasReviewedTerms {
                            hasConfirmedTerms.toggle()
                        } else {
                            showingTerms = true
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: hasConfirmedTerms ? "checkmark.square.fill" : "square")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(hasConfirmedTerms ? Color.brandBlue : .secondary)
                                .frame(width: 28, height: 28)
                            Text(LegalTerms.acceptanceCheckboxText)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(hasReviewedTerms ? .primary : .secondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        showingTerms = true
                    } label: {
                        Label(hasReviewedTerms ? "Review terms again" : "Review current terms", systemImage: "doc.text.magnifyingglass")
                            .font(.footnote.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.brandBlue)
                    .background(Color.brandBlue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Text(hasReviewedTerms ? "You can continue after confirming acceptance." : "Open the current terms once before accepting.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        onAccept()
                    } label: {
                        Text("Accept terms and continue")
                            .font(.headline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(Color.brandBlue, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .opacity(hasConfirmedTerms ? 1 : 0.48)
                    .disabled(!hasConfirmedTerms)
                }
                .padding(18)
                .frame(maxWidth: 390, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.brandBlue.opacity(0.16), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.04), radius: 12, y: 5)
            }
            .frame(maxWidth: .infinity)
            .padding(28)
        }
        .background { HomeSurfaceBackground().ignoresSafeArea() }
        .sheet(isPresented: $showingTerms, onDismiss: {
            hasReviewedTerms = true
        }) {
            LegalTermsSheet()
        }
    }
}
