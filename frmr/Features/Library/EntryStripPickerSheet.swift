import SwiftUI

// Make today's strip: pick which of today's entries go on it. Same shape as
// the Roll picker: tap toggles, the numbered badge is the slot, the title is
// the counter. Make strip hands the picked items up and closes the sheet; the
// caller opens the strip once the sheet is gone.
struct EntryStripPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var picker: EntryStripPickerViewModel

    let onMakeStrip: ([StripItem]) -> Void

    init(entries: [DiaryEntry], onMakeStrip: @escaping ([StripItem]) -> Void) {
        _picker = State(initialValue: EntryStripPickerViewModel(entries: entries))
        self.onMakeStrip = onMakeStrip
    }

    private var theme: ThemePalette { ThemePalette.resolve(for: colorScheme, surface: .paper, contrast: contrast) }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Constants.DesignUI.Space.m, alignment: .top), count: Constants.CameraUI.rollPickerColumns)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: Constants.DesignUI.Space.m) {
                    // Newest first: the default picks (the latest four) sit at
                    // the top. Slot order stays chronological.
                    ForEach(picker.entries.reversed()) { entry in
                        cell(entry)
                    }
                }
                .padding(.horizontal, Constants.DesignUI.gutter)
            }
            .navigationTitle(picker.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("library.entryPicker.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Make strip") {
                        onMakeStrip(picker.stripItems)
                        dismiss()
                    }
                    .disabled(!picker.canMakeStrip)
                    .accessibilityIdentifier("library.entryPicker.make")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .frmrSheetBackground()
        .accessibilityIdentifier("library.entryPicker")
    }

    private func cell(_ entry: DiaryEntry) -> some View {
        let slot = picker.slotNumber(for: entry)
        return Button { picker.toggle(entry) } label: {
            VStack(spacing: Constants.DesignUI.Space.xs) {
                Color.clear
                    .aspectRatio(Constants.CameraUI.stripFrameAspect, contentMode: .fit)
                    .overlay { EntryLookImage(entry: entry, contentMode: .fill) { Color.clear } }
                    .clipShape(RoundedRectangle(cornerRadius: Constants.DesignUI.Radius.thumb))
                    .overlay(alignment: .topTrailing) {
                        SelectionBadge(isVisible: slot != nil, number: slot, tint: theme.tint)
                            .padding(Constants.DesignUI.Space.xs)
                    }
                Text(entry.response)
                    .font(.frmrMeta)
                    .foregroundStyle(theme.textMuted)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(picker.isDisabled(entry))
        .accessibilityLabel(slot.map { "Entry, picked, slot \($0)" } ?? "Entry")
        .accessibilityValue(entry.response)
        .accessibilityHint(slot == nil ? "Adds this entry to the strip" : "Removes it from the strip")
        .accessibilityIdentifier("library.entryPicker.entry")
    }
}
