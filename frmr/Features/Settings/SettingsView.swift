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
    // OPEN: WB persistence TBD — this toggle is stored but the camera always
    // resets to Auto on launch until the decision lands (build notes)
    @AppStorage(Constants.DefaultsKeys.rememberWhiteBalance) private var rememberWhiteBalance = Constants.rememberWhiteBalanceDefault
    @AppStorage(Constants.DefaultsKeys.stripBackground) private var stripBackground = StripCustomization.StripBackground.white.settingsName
    // v4 F12: stored as a String so As shot can be a sentinel; read and
    // written only through StripCustomization's stored-value helpers
    @AppStorage(Constants.DefaultsKeys.stripFilmStock) private var stripFilmStock = Constants.Strip.asShotStoredValue
    // nil (key absent) = the stock's own default print
    @AppStorage(Constants.DefaultsKeys.stripPrintStock) private var stripPrintStock: StripCustomization.PrintStock?
    // A missing effect key means the stock default, which for halation is on
    @AppStorage(Constants.DefaultsKeys.stripHalation) private var stripHalation = StripCustomization.FilmEffects.stockDefaults.halation
    @AppStorage(Constants.DefaultsKeys.stripBloom) private var stripBloom = StripCustomization.FilmEffects.stockDefaults.bloom
    @AppStorage(Constants.DefaultsKeys.stripLightLeak) private var stripLightLeak = StripCustomization.FilmEffects.stockDefaults.lightLeak
    @AppStorage(Constants.DefaultsKeys.stripBlackAndWhite) private var stripBlackAndWhite = false

    @State private var isClearDiaryConfirmationPresented = false

    private var theme: ThemePalette { ThemePalette.resolve(for: colorScheme) }

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
                Section("Appearance") {
                    Picker("Appearance", selection: $appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(theme.card)

                Section("Camera defaults") {
                    Toggle("Remember white balance", isOn: $rememberWhiteBalance)
                }
                .listRowBackground(theme.card)

                Section("Strip defaults") {
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
                        // OPEN: v4-2 — on/off toggles, not strength sliders
                        // (Constants.ImageProcessing.Film.effectsAreToggles)
                        Toggle("Halation", isOn: $stripHalation)
                            .accessibilityHint("New strips start with a warm glow around bright highlights")
                            .accessibilityIdentifier("settings.halation")
                        Toggle("Bloom", isOn: $stripBloom)
                            .accessibilityHint("New strips start with bright areas softened and spread")
                        Toggle("Light leak", isOn: $stripLightLeak)
                            .accessibilityHint("New strips start with a streak of light at the frame edge")
                    }
                    Toggle("Black & white", isOn: blackAndWhiteDefault)
                        .disabled(isBlackAndWhiteLocked)
                        .accessibilityHint("New strips start in black and white. Mono stocks are always black and white.")
                        .accessibilityIdentifier("settings.blackAndWhite")
                }
                .listRowBackground(theme.card)
                .animation(.easeInOut(duration: Constants.StripUI.controlRowAnimationDuration), value: stripFilmStock)

                Section("Help") {
                    // OPEN: v3-3 — replay in landscape appears to do nothing
                    // until the phone is upright; no extra copy for now
                    Button("Show intro again", action: onboarding.replayWalkthrough)
                }
                .listRowBackground(theme.card)

                Section("Data") {
                    Button("Clear diary", role: .destructive) {
                        isClearDiaryConfirmationPresented = true
                    }
                    .foregroundStyle(Color.appRust)
                }
                .listRowBackground(theme.card)
            }
            .tint(theme.primary)
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

#Preview {
    SettingsView()
        .environment(ErrorState())
        .environment(OnboardingViewModel())
}
