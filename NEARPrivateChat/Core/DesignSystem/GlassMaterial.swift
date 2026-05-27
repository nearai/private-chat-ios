import SwiftUI

extension View {
    @ViewBuilder
    func glassBackground<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.appBorder, lineWidth: 0.5))
        }
    }
}
