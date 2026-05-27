import SwiftUI

struct LegalTermsRequiredView: View {
    let onAccept: () -> Void
    @State private var showingTerms = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                AuthHeroCard()

                VStack(alignment: .leading, spacing: 14) {
                    Label("Review terms to continue", systemImage: "doc.text.magnifyingglass")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)

                    Text("Accept the current Terms before using private chat, Cloud models, files, sharing, web grounding, Council, or agent tools.")
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
                        showingTerms = true
                    } label: {
                        Label("Review terms", systemImage: "doc.text.magnifyingglass")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.brandBlue)
                    .background(Color.brandBlue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Button {
                        onAccept()
                    } label: {
                        Text("Accept and continue")
                            .font(.headline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(Color.brandBlue, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        .sheet(isPresented: $showingTerms) {
            LegalTermsSheet()
        }
    }
}
