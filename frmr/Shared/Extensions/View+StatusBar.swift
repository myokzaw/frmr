import SwiftUI

// The status bar takes its colour from the scheme of the presentation it
// sits over. A full-screen cover owns the status bar, so darkroom covers ask
// for dark; paper content inside such a cover (the prompt, swapped into the
// editor's cover) asks for the user's own choice. The camera tab hides the
// status bar instead (ContentView).
extension View {
    /// Darkroom covers (editor, strip screen, viewers): light status text.
    func frmrDarkroomStatusBar() -> some View {
        preferredColorScheme(.dark)
    }

    /// Paper inside a darkroom cover: the user's appearance choice; nil
    /// (System) lets SwiftUI resolve the system setting.
    func frmrPaperStatusBar(appearanceMode: String) -> some View {
        preferredColorScheme(AppearanceMode(rawValue: appearanceMode)?.colorScheme)
    }
}
