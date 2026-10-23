import SwiftData
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    // nil lets the system decide
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// Settings reads and writes UserDefaults directly — no ViewModel by design.
// v5.2 S6: a grouped Form with title-case headers. The five effect defaults
// moved to their own "Default look" page (DefaultLookView); destructive rows
// are system destructive buttons, each confirmed from its own row.
struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.modelContext) private var modelContext
    @Environment(ErrorState.self) private var errorState

    @AppStorage(Constants.DefaultsKeys.appearanceMode) private var appearanceMode = AppearanceMode.system.rawValue
    @AppStorage(Constants.DefaultsKeys.editAfterEachShot) private var editAfterEachShot = true
    @AppStorage(Constants.DefaultsKeys.filmAdvanceHaptics) private var filmAdvanceHaptics = true
    @AppStorage(Constants.DefaultsKeys.stripBackground) private var stripBackground = StripCustomization.StripBackground.white.settingsName
    // v4 F12: stored as a String so As shot can be a sentinel; read and
    // written only through StripCustomization's stored-value helpers
    @AppStorage(Constants.DefaultsKeys.stripFilmStock) private var stripFilmStock = Constants.Strip.asShotStoredValue
    // nil (key absent) = the stock's own default print
    @AppStorage(Constants.DefaultsKeys.stripPrintStock) private var stripPrintStock: StripCustomization.PrintStock?
    @AppStorage(Constants.DefaultsKeys.stripBlackAndWhite) private var stripBlackAndWhite = false

    @State private var isClearDiaryConfirmationPresented = false
    @State private var isClearRollConfirmationPresented = false
    @State private var didRequestTips = false
    // v5.1-12: how many diary entries link to Roll photos, read when the
    // prompt opens; nil = the count couldn't be read, so ask both ways
    @State private var linkedEntryCount: Int?

    private var theme: ThemePalette { ThemePalette.resolve(for: colorScheme, contrast: contrast) }

    /// The stored default as a picker choice; nil = As shot
    private var stockChoice: StripCustomization.FilmStock? {
        StripCustomization.stockChoice(fromStoredValue: stripFilmStock)
    }

    private var stockChoiceBinding: Binding<StripCustomization.FilmStock?> {
        Binding(
            get: { stockChoice },
            set: { stripFilmStock = StripCustomization.storedValue(forStockChoice: $0) }
        )
    }

    // The rules below mirror StripViewModel: As shot has no print row and
    // keeps effects (its frames may carry stocks); only an explicit Off
    // hides effects; only a mono override locks B&W
    private var isPrintRowVisible: Bool { stockChoice?.hasPrintChoice ?? false }
    private var printChoices: [StripCustomization.PrintStock] { stockChoice?.availablePrints ?? [] }
    private var areEffectsVisible: Bool { stockChoice?.hasEffects ?? true }
    private var isBlackAndWhiteLocked: Bool { stockChoice?.isMonochrome ?? false }

    // Mirrors StripViewModel.blackAndWhiteToggle: a mono stock reads on and
    // the stored preference is left untouched while it is locked
    private var blackAndWhiteDefault: Binding<Bool> {
        Binding(
            get: { stripBlackAndWhite || isBlackAndWhiteLocked },
            set: { newValue in
                guard !isBlackAndWhiteLocked else { return }
                stripBlackAndWhite = newValue
            }
        )
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                cameraSection
                stripSection
                helpSection
                dataSection
                aboutSection
            }
            .formStyle(.grouped)
            .tint(theme.tint)
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .frmrTabBarScrollInsets()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SettingsPage.self) { _ in
                DefaultLookView()
            }
        }
    }

    // MARK: Sections

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Appearance", selection: $appearanceMode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.appearance")
        }
        .listRowBackground(theme.card)
    }

    private var cameraSection: some View {
        Section {
            Toggle("Edit after each shot", isOn: $editAfterEachShot)
                .accessibilityHint("When off, photos go straight to your roll and you edit them later")
                .accessibilityIdentifier("settings.editAfterEachShot")
            Toggle("Film-advance haptics", isOn: $filmAdvanceHaptics)
                .accessibilityHint("The shutter plays a film-winding pattern. When off, a single tap.")
                .accessibilityIdentifier("settings.filmAdvanceHaptics")
        } header: {
            Text("Camera")
        } footer: {
            Text("With Edit after each shot off, keep shooting and edit later from the last-photo thumbnail.")
        }
        .listRowBackground(theme.card)
    }

    private var stripSection: some View {
        Section {
            Picker("Paper", selection: $stripBackground) {
                // v4 F8: white and black only
                ForEach(StripCustomization.StripBackground.allCases, id: \.settingsName) { background in
                    Text(background.label).tag(background.settingsName)
                }
            }
            .accessibilityHint("The paper new strips start with")
            .accessibilityIdentifier("settings.background")
            Picker("Film stock", selection: stockChoiceBinding) {
                ForEach(StripCustomization.stockChoices, id: \.self) { choice in
                    Text(StripCustomization.label(forStockChoice: choice)).tag(choice)
                }
            }
            .accessibilityHint("The film new strips start on. As shot keeps each photo's own film.")
            .accessibilityIdentifier("settings.filmStock")
            if isPrintRowVisible {
                Picker("Print", selection: $stripPrintStock) {
                    Text("Stock default").tag(StripCustomization.PrintStock?.none)
                    ForEach(printChoices) { printStock in
                        Text(printStock.label).tag(StripCustomization.PrintStock?.some(printStock))
                    }
                }
                .accessibilityHint("The paper new strips are printed on. Stock default uses the film's own print.")
                .accessibilityIdentifier("settings.print")
            }
            Toggle("Black & white", isOn: blackAndWhiteDefault)
                .disabled(isBlackAndWhiteLocked)
                .accessibilityHint("New strips start in black and white. Mono stocks are always black and white.")
                .accessibilityIdentifier("settings.blackAndWhite")
            if areEffectsVisible {
                NavigationLink(value: SettingsPage.defaultLook) {
                    Text("Default look")
                }
                .accessibilityHint("Halation, haze, light leak, grain and vignette for new strips")
                .accessibilityIdentifier("settings.defaultLook")
            }
        } header: {
            Text("Strip Defaults")
        }
        .listRowBackground(theme.card)
        .frmrAnimation(.snap, value: stripFilmStock)
    }

    private var helpSection: some View {
        Section {
            Button("Show tips again") {
                FrmrTips.requestReset()
                didRequestTips = true
            }
            .disabled(didRequestTips)
            .accessibilityIdentifier("settings.showTips")
        } header: {
            Text("Help")
        } footer: {
            Text(didRequestTips ? "Tips show again the next time you open frmr." : "Tips point out the camera's controls the first time you use them.")
        }
        .listRowBackground(theme.card)
    }

    private var dataSection: some View {
        Section {
            Button("Clear diary", role: .destructive) {
                isClearDiaryConfirmationPresented = true
            }
            .foregroundStyle(theme.destructive)
            .accessibilityIdentifier("settings.clearDiary")
            .confirmationDialog(
                "Delete all entries and strips? This can't be undone.",
                isPresented: $isClearDiaryConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Delete everything", role: .destructive, action: clearDiary)
                    .accessibilityIdentifier("settings.clearDiary.confirm")
            }
            // v5 F6 (OPEN: v5-7): the Roll is cleared on its own
            Button("Clear roll", role: .destructive, action: askToClearRoll)
                .foregroundStyle(theme.destructive)
                .accessibilityIdentifier("settings.clearRoll")
                .confirmationDialog(
                    clearRollTitle,
                    isPresented: $isClearRollConfirmationPresented,
                    titleVisibility: .visible
                ) {
                    clearRollButtons
                }
        } header: {
            Text("Your Data")
        }
        .listRowBackground(theme.card)
        .sensoryFeedback(.warning, trigger: isClearRollConfirmationPresented) { _, shown in shown }
        .sensoryFeedback(.warning, trigger: isClearDiaryConfirmationPresented) { _, shown in shown }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: appVersion)
        } header: {
            Text("About")
        } footer: {
            Text("frmr works fully offline: no accounts, no analytics, no network.")
        }
        .listRowBackground(theme.card)
    }

    // v5.1-7/12: with linked diary entries the prompt offers both; Keep
    // entries is the default and keeps the old confirm identifier so the
    // flow reads the same to the UI tests. An unreadable count (nil) asks
    // both ways rather than risk deleting entries without saying so.
    private var clearRollTitle: String {
        RollPromptText.clearRollTitle(linkedEntries: linkedEntryCount)
    }

    @ViewBuilder
    private var clearRollButtons: some View {
        if linkedEntryCount == 0 {
            Button("Delete roll", role: .destructive) { clearRoll(entries: .keepEntry) }
                .accessibilityIdentifier("settings.clearRoll.confirm")
        } else {
            Button("Keep entries") { clearRoll(entries: .keepEntry) }
                .accessibilityIdentifier("settings.clearRoll.confirm")
            Button("Delete photos and diary entries", role: .destructive) { clearRoll(entries: .deleteBoth) }
                .accessibilityIdentifier("settings.clearRoll.deleteBoth")
        }
    }

    private func askToClearRoll() {
        linkedEntryCount = RollViewModel.linkedEntryCountIfKnown(in: modelContext)
        isClearRollConfirmationPresented = true
    }

    private func clearRoll(entries: RollViewModel.RollDeletion) {
        do {
            try RollViewModel.clearRoll(entries: entries, context: modelContext)
        } catch let error as AppError {
            errorState.raise(error)
        } catch {
            errorState.raise(.persistenceFailed(reason: error.localizedDescription))
        }
    }

    private func clearDiary() {
        do {
            try modelContext.delete(model: DiaryEntry.self)
            try modelContext.delete(model: DailyStrip.self)
            try modelContext.save()
            try removeStoredImages()
        } catch {
            errorState.raise(.persistenceFailed(reason: error.localizedDescription))
        }
    }

    // Photo and strip files live outside SwiftData, so they're removed separately
    private func removeStoredImages() throws {
        let directories = ["Photos", "Strips"].map {
            FileManager.documentsDirectory.appending(path: $0, directoryHint: .isDirectory)
        }
        for directory in directories where FileManager.default.fileExists(atPath: directory.path()) {
            try FileManager.default.removeItem(at: directory)
        }
    }
}

/// Settings' pushed pages.
enum SettingsPage: Hashable {
    case defaultLook
}

#Preview {
    SettingsView()
        .environment(ErrorState())
}
