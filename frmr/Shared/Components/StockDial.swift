import SwiftUI

// v5 F2 / v5.1 F8 film-stock dial: a slim glass bar of the seven stock codes
// that snaps one detent at a time, the selected one centred. Swiping or
// tapping selects; a selection haptic ticks per detent. The selected stock's
// full name is a tiny label just above the bar (no separate caption line).
//
// Rotation (v5-3): the bar is a wide control, so it never turns; each code
// label turns about its own centre inside its fixed-width detent.
struct StockDial: View {
    let selected: StripCustomization.FilmStock
    let onSelect: (StripCustomization.FilmStock) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position: StripCustomization.FilmStock?

    var body: some View {
        VStack(spacing: Constants.CameraUI.dialNameSpacing) {
            Text(selected.label)
                .font(.system(size: Constants.CameraUI.dialNameFontSize, weight: .medium))
                .foregroundStyle(.white.opacity(Constants.CameraUI.dialNameOpacity))
                .accessibilityHidden(true)
                .accessibilityIdentifier("camera.dial.name")
            bar
        }
        .onAppear { position = selected }
        .onChange(of: position) { _, new in
            if let new, new != selected { onSelect(new) }
        }
        .onChange(of: selected) { _, new in
            if position != new {
                withAnimation(snapAnimation) { position = new }
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camera.dial")
    }

    private var bar: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(StripCustomization.FilmStock.allCases) { stock in
                        DialDetent(
                            stock: stock,
                            isSelected: stock == selected,
                            action: { choose(stock) }
                        )
                        .id(stock)
                    }
                }
                .scrollTargetLayout()
            }
            // Margins let the first and last stock reach the centre
            .contentMargins(
                .horizontal,
                max(0, (geometry.size.width - Constants.CameraUI.dialItemWidth) / 2),
                for: .scrollContent
            )
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $position, anchor: .center)
        }
        .frame(height: Constants.CameraUI.dialHeight)
        .background {
            // The window the selected stock sits in
            Capsule()
                .fill(.white.opacity(Constants.CameraUI.dialSelectedFillOpacity))
                .frame(
                    width: Constants.CameraUI.dialItemWidth,
                    height: Constants.CameraUI.dialHeight - Constants.CameraUI.dialSelectedInset * 2
                )
        }
        .frmrGlassCapsule()
        .clipShape(Capsule())
    }

    private var snapAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: Constants.CameraUI.dialSnapAnimationDuration)
    }

    private func choose(_ stock: StripCustomization.FilmStock) {
        withAnimation(snapAnimation) { position = stock }
        if stock != selected { onSelect(stock) }
    }
}

private struct DialDetent: View {
    let stock: StripCustomization.FilmStock
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(stock.shortCode)
                .font(.system(size: Constants.CameraUI.dialCodeFontSize, weight: .semibold, design: .monospaced))
                .foregroundStyle(isSelected ? Color.appAmber : .white)
                .opacity(isSelected ? 1 : Constants.CameraUI.dialUnselectedOpacity)
                .rotatingWithDevice()
                .frame(width: Constants.CameraUI.dialItemWidth, height: Constants.CameraUI.dialHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Film: \(stock.label)")
        .accessibilityHint("Shoots on this film")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("camera.dial.\(stock.rawValue)")
    }
}

#Preview {
    ZStack {
        Color.black
        StockDial(selected: .portrait400, onSelect: { _ in })
    }
}
