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

// Settings reads and writes UserDefaults directly — no ViewModel by design
struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(ErrorState.self) private var errorState
    @Environment(OnboardingViewModel.self) private var onboarding

    @AppStorage(Constants.DefaultsKeys.appearanceMode) private var appearanceMode = AppearanceMode.system.rawValue
    @AppStorage(Constants.DefaultsKeys.stripBackground) private var stripBackground = StripCustomization.StripBackground.white.settingsName
    // v4 F12: stored as a String so As shot can be a sentinel; read and
    // written only through StripCustomization's stored-value helpers
    @AppStorage(Constants.DefaultsKeys.stripFilmStock) private var stripFilmStock = Constants.Strip.asShotStoredValue
    // nil (key absent) = the stock's own default print
    @AppStorage(Constants.DefaultsKeys.stripPrintStock) private var stripPrintStock: StripCustomization.PrintStock?
    // v5 F5: strengths (0…1.5), not toggles. A missing key is the effect's
    // default; a v4 Bool reads as 1 (on) or 0 (off).
    @AppStorage(Constants.DefaultsKeys.stripHalation) private var stripHalation = FilmLook.Effect.halation.defaultStrength
    @AppStorage(Constants.DefaultsKeys.stripHaze) private var stripHaze = FilmLook.Effect.haze.defaultStrength
    @AppStorage(Constants.DefaultsKeys.stripLightLeak) private var stripLightLeak = FilmLook.Effect.lightLeak.defaultStrength
    @AppStorage(Constants.DefaultsKeys.stripGrain) private var stripGrain = FilmLook.Effect.grain.defaultStrength
    @AppStorage(Constants.DefaultsKeys.stripVignette) private var stripVignette = FilmLook.Effect.vignette.defaultStrength
    @AppStorage(Constants.DefaultsKeys.stripBlackAndWhite) private var stripBlackAndWhite = false

    @State private var isClearDiaryConfirmationPresented = false
    @State private var isClearRollConfirmationPresented = false
    // v5.1-12: how many diary entries link to Roll photos, read when the prompt opens
    @State private var linkedEntryCount = 0

    private var theme: ThemePalette { ThemePalette.resolve(for: colorScheme) }
    private var accent: Color { ThemePalette.accent(for: colorScheme) }
    private var destructive: Color { ThemePalette.destructive(for: colorScheme) }

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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Appearance", selection: $appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    SettingsHeader(title: "Appearance", color: theme.muted)
                }
                .listRowBackground(theme.card)

                Section {
                    Picker("Background", selection: $stripBackground) {
                        // v4 F8: white and black only
                        ForEach(StripCustomization.StripBackground.allCases, id: \.settingsName) { background in
                            Text(background.label).tag(background.settingsName)
                        }
                    }
                    .accessibilityHint("The background new strips start with")
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
                    }
                    if areEffectsVisible {
                        EffectSliders(
                            strength: effectStrength,
                            setStrength: setEffectStrength,
                            identifierPrefix: "settings.slider",
                            textColor: theme.text,
                            tint: accent
                        )
                    }
                    Toggle("Black & white", isOn: blackAndWhiteDefault)
                        .disabled(isBlackAndWhiteLocked)
                        .accessibilityHint("New strips start in black and white. Mono stocks are always black and white.")
                        .accessibilityIdentifier("settings.blackAndWhite")
                } header: {
                    SettingsHeader(title: "Strip defaults", color: theme.muted)
                }
                .listRowBackground(theme.card)
                .animation(.easeInOut(duration: Constants.StripUI.controlRowAnimationDuration), value: stripFilmStock)

                Section {
                    // OPEN: v3-3 — replay in landscape appears to do nothing
                    // until the phone is upright; no extra copy for now
                    Button("Show intro again", action: onboarding.replayWalkthrough)
                } header: {
                    SettingsHeader(title: "Help", color: theme.muted)
                }
                .listRowBackground(theme.card)

                Section {
                    Button("Clear diary", role: .destructive) {
                        isClearDiaryConfirmationPresented = true
                    }
                    .foregroundStyle(destructive)
                    // v5 F6 (OPEN: v5-7): the Roll is cleared on its own
                    Button("Clear roll", role: .destructive) {
                        askToClearRoll()
                    }
                    .foregroundStyle(destructive)
                    .accessibilityIdentifier("settings.clearRoll")
                } header: {
                    SettingsHeader(title: "Data", color: theme.muted)
                }
                .listRowBackground(theme.card)
            }
            .tint(accent)
            .frmrTabBarScrollInsets()
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle("Settings")
            .confirmationDialog(
                "Delete all entries and strips? This can't be undone.",
                isPresented: $isClearDiaryConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Delete everything", role: .destructive, action: clearDiary)
            }
            .confirmationDialog(
                clearRollTitle,
                isPresented: $isClearRollConfirmationPresented,
                titleVisibility: .visible
            ) {
                clearRollButtons
            }
        }
    }

    private func effectStrength(_ effect: FilmLook.Effect) -> Double {
        switch effect {
        case .halation: return stripHalation
        case .haze: return stripHaze
        case .lightLeak: return stripLightLeak
        case .grain: return stripGrain
        case .vignette: return stripVignette
        }
    }

    private func setEffectStrength(_ value: Double, for effect: FilmLook.Effect) {
        switch effect {
        case .halation: stripHalation = value
        case .haze: stripHaze = value
        case .lightLeak: stripLightLeak = value
        case .grain: stripGrain = value
        case .vignette: stripVignette = value
        }
    }

    // v5.1-7/12: with linked diary entries the prompt offers both; Keep
    // entries is the default and keeps the old confirm identifier so the
    // flow reads the same to the UI tests
    private var clearRollTitle: String {
        guard linkedEntryCount > 0 else { return "Delete every photo in your roll? This can't be undone." }
        let entryText = linkedEntryCount == 1 ? "1 diary entry is" : "\(linkedEntryCount) diary entries are"
        return "\(entryText) about photos in your roll. Delete them too, or keep them with their own copy of the photo?"
    }

    @ViewBuilder
    private var clearRollButtons: some View {
        if linkedEntryCount > 0 {
            Button("Keep entries") { clearRoll(entries: .keepEntry) }
                .accessibilityIdentifier("settings.clearRoll.confirm")
            Button("Delete photos and diary entries", role: .destructive) { clearRoll(entries: .deleteBoth) }
                .accessibilityIdentifier("settings.clearRoll.deleteBoth")
        } else {
            Button("Delete roll", role: .destructive) { clearRoll(entries: .keepEntry) }
                .accessibilityIdentifier("settings.clearRoll.confirm")
        }
    }

    private func askToClearRoll() {
        linkedEntryCount = RollViewModel.linkedEntryCount(in: modelContext)
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

private struct SettingsHeader: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.footnote.weight(.medium))
            .textCase(nil)
            .foregroundStyle(color)
    }
}

#Preview {
    SettingsView()
        .environment(ErrorState())
        .environment(OnboardingViewModel())
}
