import SwiftUI

// v5.2 S6: Settings → Default look. The five effect strengths new strips
// start with, edited with the editor's own tool bar and scrubber instead of
// five inline sliders. Reads and writes UserDefaults directly, like the
// rest of Settings.
struct DefaultLookView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    // v5 F5: strengths (0…1.5), not toggles. A missing key is the effect's
    // default; a v4 Bool reads as 1 (on) or 0 (off).
    @AppStorage(Constants.DefaultsKeys.stripHalation) private var halation = FilmLook.Effect.halation.defaultStrength
    @AppStorage(Constants.DefaultsKeys.stripHaze) private var haze = FilmLook.Effect.haze.defaultStrength
    @AppStorage(Constants.DefaultsKeys.stripLightLeak) private var lightLeak = FilmLook.Effect.lightLeak.defaultStrength
    @AppStorage(Constants.DefaultsKeys.stripGrain) private var grain = FilmLook.Effect.grain.defaultStrength
    @AppStorage(Constants.DefaultsKeys.stripVignette) private var vignette = FilmLook.Effect.vignette.defaultStrength

    @State private var effect: FilmLook.Effect = .halation

    private var theme: ThemePalette { ThemePalette.resolve(for: colorScheme, surface: .paper, contrast: contrast) }

    var body: some View {
        Form {
            Section {
                EffectScrubber(
                    title: effect.label,
                    value: binding(for: effect),
                    defaultValue: effect.defaultStrength,
                    hint: effect.toolHint,
                    identifier: "settings.scrubber",
                    textColor: theme.text,
                    tint: theme.tint
                )
                ToolIconBar(
                    items: FilmLook.Effect.allCases.map(item(for:)),
                    selectedID: effect.rawValue,
                    identifierPrefix: "settings.tool",
                    selectedColor: theme.tint,
                    idleColor: theme.text,
                    onSelect: { effect = FilmLook.Effect(rawValue: $0) ?? .halation }
                )
            } footer: {
                Text("New strips start with these strengths. 100% is each film's own amount.")
            }
            .listRowBackground(theme.card)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(theme.bg)
        .navigationTitle("Default Look")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func item(for effect: FilmLook.Effect) -> ToolIconItem {
        let strength = binding(for: effect).wrappedValue
        return ToolIconItem(
            id: effect.rawValue, title: effect.label, systemImage: effect.toolSymbolName, hint: effect.toolHint,
            value: ScrubberMath.percentText(strength, scale: Constants.ScrubberUI.percentScale),
            ring: ToolRing.fraction(strength: strength)
        )
    }

    private func binding(for effect: FilmLook.Effect) -> Binding<Double> {
        switch effect {
        case .halation: return $halation
        case .haze: return $haze
        case .lightLeak: return $lightLeak
        case .grain: return $grain
        case .vignette: return $vignette
        }
    }
}

#Preview {
    NavigationStack { DefaultLookView() }
}
