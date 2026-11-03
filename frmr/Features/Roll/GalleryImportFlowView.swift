import SwiftUI

// F-122-E: the cover over the Roll while a gallery import runs. The editor
// for the pick on screen; the diary prompt after Continue to diary; a dark
// pause while the next photo loads. All decisions live in the session.
struct GalleryImportFlowView: View {
    @Environment(ErrorState.self) private var errorState
    @Environment(\.colorSchemeContrast) private var contrast

    let session: GalleryImportSession
    let onClose: () -> Void

    var body: some View {
        ZStack {
            if let continuation = session.diaryContinuation {
                EntryEditorView(continuation: continuation, onFinish: session.diaryFinished)
                    .transition(.opacity)
            } else if let edit = session.current {
                PhotoEditView(edit: edit)
                    .id(edit.id)
                    .transition(.opacity)
            } else {
                loading
            }
        }
        .frmrAnimation(.panel, value: session.current?.id)
        .task {
            session.onClose = onClose
            await session.start()
        }
    }

    private var loading: some View {
        ZStack {
            ThemePalette.resolve(for: .dark, surface: .darkroom, contrast: contrast).bg.ignoresSafeArea()
            ProgressView()
                .tint(.white)
                .accessibilityLabel("Loading photo")
        }
        .appErrorAlert(errorState)
    }
}
