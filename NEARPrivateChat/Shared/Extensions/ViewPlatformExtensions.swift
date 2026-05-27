import SwiftUI

extension View {
    @ViewBuilder
    func platformInlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func platformMediumDetent() -> some View {
        #if os(iOS)
        presentationDetents([.medium])
        #else
        self
        #endif
    }

    @ViewBuilder
    func platformLargeDetent() -> some View {
        #if os(iOS)
        presentationDetents([.large])
        #else
        self
        #endif
    }

    @ViewBuilder
    func tokenInputTraits() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
            .keyboardType(.asciiCapable)
            .autocorrectionDisabled()
        #else
        self
        #endif
    }
}
