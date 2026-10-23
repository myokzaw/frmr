import SwiftUI

extension View {
    /// Bottom content inset so lists end above the floating tab bar, and a
    /// soft edge under it on iOS 26.
    @ViewBuilder
    func frmrTabBarScrollInsets() -> some View {
        if #available(iOS 26, *) {
            contentMargins(.bottom, Constants.LibraryUI.bottomContentInset, for: .scrollContent)
                .scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
            contentMargins(.bottom, Constants.LibraryUI.bottomContentInset, for: .scrollContent)
        }
    }
}
