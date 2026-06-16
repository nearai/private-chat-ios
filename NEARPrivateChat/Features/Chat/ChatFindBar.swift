import SwiftUI

struct ChatFindBar: View {
    @Binding var query: String
    let matchCount: Int
    let matchIndex: Int
    let onPrev: () -> Void
    let onNext: () -> Void
    let onDismiss: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Find in conversation…", text: $query)
                    .font(.body)
                    .focused($focused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit {
                        if matchCount > 0 { onNext() }
                    }
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            if matchCount > 0 {
                Text("\(matchIndex + 1)/\(matchCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 36)

                HStack(spacing: 0) {
                    Button(action: onPrev) {
                        Image(systemName: "chevron.up")
                            .font(.caption.weight(.semibold))
                            .frame(width: 32, height: 32)
                    }
                    Button(action: onNext) {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .frame(width: 32, height: 32)
                    }
                }
                .foregroundStyle(Color.brandAccent)
                .buttonStyle(.plain)
            } else if !query.isEmpty {
                Text("No results")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Done", action: onDismiss)
                .font(.body.weight(.medium))
                .foregroundStyle(Color.brandAccent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.appBackground)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.55)
        }
        .onAppear { focused = true }
    }
}
