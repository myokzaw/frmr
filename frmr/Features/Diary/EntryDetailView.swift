import SwiftData
import SwiftUI

// Full-screen view of a single diary entry: the photo at full size with the
// prompt and written response below. Presented from the diary list.
struct EntryDetailView: View {
    @Environment(\.dismiss) private var dismiss

    // v4 F11: the photo is shown through the entry's own stock
    let entry: DiaryEntry
    let prompt: String
    let response: String
    let dateText: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.appBlack
                .ignoresSafeArea()

            VStack(spacing: 0) {
                DetailPhoto(entry: entry)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                ScrollView {
                    VStack(alignment: .leading, spacing: Constants.EditorUI.buttonPadding / 2) {
                        Text(prompt)
                            .font(.system(size: Constants.LibraryUI.excerptFontSize, design: .serif))
                            .italic()
                            .foregroundStyle(Color.appCream.opacity(Constants.CameraUI.captionOpacity))

                        DetailResponse(response: response)

                        Text(dateText)
                            .font(.system(size: Constants.LibraryUI.sectionFontSize, design: .monospaced))
                            .foregroundStyle(Color.appTealLight)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                .frame(maxHeight: Constants.DetailUI.textPanelMaxHeight)
            }

            CloseCircleButton(action: { dismiss() })
                .padding()
        }
    }
}

private struct DetailPhoto: View {
    let entry: DiaryEntry

    var body: some View {
        EntryLookImage(entry: entry, contentMode: .fit) {
            Text("This photo file is missing.")
                .font(.system(size: Constants.LibraryUI.excerptFontSize, design: .serif))
                .italic()
                .foregroundStyle(Color.appCream.opacity(Constants.CameraUI.captionOpacity))
        }
    }
}

private struct DetailResponse: View {
    let response: String

    var body: some View {
        if !response.isEmpty {
            Text(response)
                .font(.system(size: Constants.EditorUI.entryFontSize, design: .serif))
                .foregroundStyle(Color.appCream)
        }
    }
}

// Shared close affordance for the full-screen viewers
struct CloseCircleButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: Constants.DetailUI.closeIconSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(
                    width: Constants.DetailUI.closeButtonSize,
                    height: Constants.DetailUI.closeButtonSize
                )
                .background(.white.opacity(Constants.CameraUI.chipInactiveOpacity), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    // A missing photo path shows the "file is missing" state
    EntryDetailView(
        entry: DiaryEntry(photoPath: "Photos/preview-missing.jpg", prompt: "", response: ""),
        prompt: "What made you take this picture?",
        response: "The light was doing something I'd never seen before.",
        dateText: "JUL 31, 2026"
    )
    .modelContainer(for: DiaryEntry.self, inMemory: true)
}
