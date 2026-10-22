import SwiftUI

// v5 F5: one effect strength as a labelled 0–150% slider. The same row is
// used by the Photo editor, the diary review, the strip screen and
// Settings, so an effect reads the same everywhere. 100% is the v4
// strength; the Binding carries the 0…1.5 value.
struct EffectSliderRow: View {
    let title: String
    @Binding var value: Double
    let hint: String
    let identifier: String
    let textColor: Color
    let tint: Color

    /// "100%" for 1.0, "0%" for off, "150%" at the top of the range.
    nonisolated static func percentText(_ strength: Double) -> String {
        let percent = (FilmLook.clampedStrength(strength) * Constants.EffectSliderUI.percentScale).rounded()
        return "\(Int(percent))%"
    }

    // v5.1 F10: one compact line (the editor and strip screens stack five of
    // these): quiet SF title, amber slider, the value in monospaced digits
    var body: some View {
        HStack(spacing: Constants.CameraUI.chipSpacing) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(textColor)
                .lineLimit(1)
                .minimumScaleFactor(Constants.EffectSliderUI.titleMinScale)
                .frame(width: Constants.EffectSliderUI.titleWidth, alignment: .leading)
                .accessibilityHidden(true)
            Slider(value: $value, in: FilmLook.strengthRange, step: Constants.EffectSliderUI.step)
                .tint(tint)
                .accessibilityLabel(title)
                .accessibilityValue(Self.percentText(value))
                .accessibilityHint(hint)
                .accessibilityIdentifier(identifier)
            Text(Self.percentText(value))
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(textColor.opacity(Constants.SettingsUI.valueOpacity))
                .frame(minWidth: Constants.EffectSliderUI.percentWidth, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .frame(minHeight: Constants.EffectSliderUI.rowMinHeight)
    }
}

extension FilmLook.Effect {
    /// What the slider does, for VoiceOver's hint.
    var sliderHint: String {
        switch self {
        case .halation: return "Warm glow around bright highlights"
        case .haze: return "Softens and spreads bright areas"
        case .lightLeak: return "A streak of light at the frame edge"
        case .grain: return "How much film grain shows"
        case .vignette: return "Darkens the corners of the frame"
        }
    }
}

// All five sliders for a look held somewhere else (the editor, the review,
// the strip): the caller supplies how to read and write one strength.
struct EffectSliders: View {
    let strength: (FilmLook.Effect) -> Double
    let setStrength: (Double, FilmLook.Effect) -> Void
    let identifierPrefix: String
    let textColor: Color
    let tint: Color

    var body: some View {
        ForEach(FilmLook.Effect.allCases) { effect in
            EffectSliderRow(
                title: effect.label,
                value: Binding(
                    get: { strength(effect) },
                    set: { setStrength($0, effect) }
                ),
                hint: effect.sliderHint,
                identifier: "\(identifierPrefix).\(effect.rawValue)",
                textColor: textColor,
                tint: tint
            )
        }
    }
}
