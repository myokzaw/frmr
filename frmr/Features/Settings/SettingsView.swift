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
    @AppStorage(Constants.DefaultsKeys.stripBackground) private var stripBackground = StripCustomization.StripBackground.cream.settingsName
    @AppStorage(Constants.DefaultsKeys.stripFilmStock) private var stripFilmStock = StripCustomization.FilmStock.none.rawValue
    @AppStorage(Constants.DefaultsKeys.stripBlackAndWhite) private var stripBlackAndWhite = false

    @State private var isClearDiaryConfirmationPresented = false

    private var theme: ThemePalette { ThemePalette.resolve(for: colorScheme) }

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
                        Text("Cream").tag(StripCustomization.StripBackground.cream.settingsName)
                        Text("White").tag(StripCustomization.StripBackground.white.settingsName)
                        Text("Black").tag(StripCustomization.StripBackground.black.settingsName)
                    }
                    Picker("Film stock", selection: $stripFilmStock) {
                        ForEach(StripCustomization.FilmStock.allCases) { stock in
                            Text(stock.label).tag(stock.rawValue)
                        }
                    }
                    Toggle("Black & white", isOn: $stripBlackAndWhite)
                }
                .listRowBackground(theme.card)

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
