import SwiftData
import SwiftUI

// Full-screen view of a single diary entry (v5.1 F10): the photo full-bleed
// in its look, a glass top bar with a close icon, and the prompt, response
// and date in a quiet glass footer. Presented from the diary list.
struct EntryDetailView: View {
    @Environment(\.dismiss) private var dismiss

    // v4 F11: the photo is shown through the entry's own stock
    let entry: DiaryEntry
    let prompt: String
    let response: String
    let dateText: String

    var body: some View {
        ZStack {
            Color.appBlack
                .ignoresSafeArea()

            DetailPhoto(entry: entry)
                .padding(.horizontal, Constants.DetailUI.photoInset)
                .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 0) {
                DetailTopBar(title: dateText, onClose: { dismiss() }) { EmptyView() }
                Spacer(minLength: 0)
                DetailFooter(prompt: prompt, response: response)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// The shared glass top bar of the full-screen viewers: close on the leading
// side, the title in the middle, optional trailing actions
struct DetailTopBar<Trailing: View>: View {
    let title: String
    let onClose: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack {
            GlassIconButton(systemImage: "xmark", label: "Close", identifier: "detail.close", action: onClose)
            Spacer()
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(Constants.DetailUI.promptOpacity))
                .accessibilityIdentifier("detail.title")
            Spacer()
            trailing()
                .frame(minWidth: Constants.DetailUI.topBarButtonSize, alignment: .trailing)
        }
        .padding(.horizontal, Constants.DetailUI.topBarPadding)
        .padding(.top, Constants.DetailUI.topBarPadding / 2)
    }
}

private struct DetailFooter: View {
    let prompt: String
    let response: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Constants.DetailUI.footerSpacing) {
                Text(prompt)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(Constants.DetailUI.promptOpacity))
                if !response.isEmpty {
                    Text(response)
                        .font(.body)
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Constants.DetailUI.footerPadding)
        }
        .frame(maxHeight: Constants.DetailUI.textPanelMaxHeight)
        .fixedSize(horizontal: false, vertical: true)
        .frmrAdaptiveGlass(in: RoundedRectangle(cornerRadius: Constants.DetailUI.footerCornerRadius))
        .padding(Constants.DetailUI.footerOuterPadding)
        .accessibilityIdentifier("detail.footer")
    }
}

private struct DetailPhoto: View {
    let entry: DiaryEntry

    var body: some View {
        EntryLookImage(entry: entry, contentMode: .fit) {
            Text("This photo file is missing.")
                .font(.callout)
                .foregroundStyle(.white.opacity(Constants.DetailUI.promptOpacity))
        }
        .clipShape(RoundedRectangle(cornerRadius: Constants.DetailUI.photoCornerRadius))
        .accessibilityLabel("Photo")
    }
}

#Preview {
    // A missing photo path shows the "file is missing" state
    EntryDetailView(
        entry: DiaryEntry(photoPath: "Photos/preview-missing.jpg", prompt: "", response: ""),
        prompt: "What made you take this picture?",
        response: "The light was doing something I'd never seen before.",
        dateText: "Jul 31, 2026"
    )
    .modelContainer(for: DiaryEntry.self, inMemory: true)
}
