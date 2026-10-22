import SwiftData
import SwiftUI

// Full-screen view of a single diary entry (v5.1 F10, v5.2 §5.7): the photo
// in its look at the top of a darkroom page, Close on glass over it, then
// the prompt as a muted serif italic line, the response in reading serif,
// and a footer with when and on what film. Presented from the Entries tab.
struct EntryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorSchemeContrast) private var contrast

    // v4 F11: the photo is shown through the entry's own stock
    let entry: DiaryEntry
    let prompt: String
    let response: String
    let metadata: String

    private var theme: ThemePalette { ThemePalette.resolve(for: .dark, surface: .darkroom, contrast: contrast) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Constants.DetailUI.textSpacing) {
                DetailPhoto(entry: entry, mutedColor: theme.textMuted)
                Text(prompt)
                    .font(.frmrPrompt)
                    .foregroundStyle(theme.textMuted)
                    .accessibilityIdentifier("detail.prompt")
                if !response.isEmpty {
                    Text(response)
                        .font(.frmrReading)
                        .foregroundStyle(theme.text)
                        .accessibilityIdentifier("detail.response")
                }
                Text(metadata)
                    .font(.frmrMeta)
                    .foregroundStyle(theme.textMuted)
                    .accessibilityIdentifier("detail.footer")
            }
            .padding(.horizontal, Constants.DesignUI.gutter)
            .padding(.bottom, Constants.DesignUI.Space.xxl)
            .textSelection(.enabled)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            DetailTopBar(onClose: { dismiss() }) { EmptyView() }
        }
        .background(theme.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

// The shared top bar of the full-screen viewers: Close on glass on the
// leading side, optional trailing actions in their own glass group
struct DetailTopBar<Trailing: View>: View {
    let onClose: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack {
            GlassIconButton(systemImage: "xmark", label: "Close", identifier: "detail.close", rotates: false, action: onClose)
            Spacer()
            FrmrGlassContainer(spacing: Constants.DesignUI.Space.s) {
                HStack(spacing: Constants.DesignUI.Space.s) { trailing() }
            }
        }
        .padding(.horizontal, Constants.DesignUI.gutter)
        .padding(.vertical, Constants.DesignUI.Space.s)
    }
}

private struct DetailPhoto: View {
    let entry: DiaryEntry
    let mutedColor: Color

    var body: some View {
        EntryLookImage(entry: entry, contentMode: .fit) {
            Text("This photo file is missing.")
                .font(.frmrMeta)
                .foregroundStyle(mutedColor)
        }
        .clipShape(RoundedRectangle(cornerRadius: Constants.DesignUI.Radius.media))
        // The look renders asynchronously: hold the photo's space meanwhile
        .containerRelativeFrame(.vertical) { height, _ in height * Constants.DetailUI.photoHeightFraction }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Photo")
    }
}

#Preview {
    // A missing photo path shows the "file is missing" state
    EntryDetailView(
        entry: DiaryEntry(photoPath: "Photos/preview-missing.jpg", prompt: "", response: ""),
        prompt: "What made you take this picture?",
        response: "The light was doing something I'd never seen before.",
        metadata: "Jul 31, 2026 at 3:41 PM · Daylight 200"
    )
    .modelContainer(for: DiaryEntry.self, inMemory: true)
}
