import SwiftUI

// v5 F2 film-stock dial for Photo mode: a horizontal strip of the seven
// stocks that snaps one detent at a time, the selected one centred inside a
// fixed window, its full name under it. Swiping or tapping selects; a
// selection haptic ticks per detent.
//
// Rotation (v5-3): the strip is a wide control, so it never turns; each
// code label turns about its own centre inside its fixed-width detent.
struct StockDial: View {
    let selected: StripCustomization.FilmStock
    let onSelect: (StripCustomization.FilmStock) -> Void

    @State private var position: StripCustomization.FilmStock?

    var body: some View {
        VStack(spacing: Constants.CameraUI.dialCaptionSpacing) {
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
            .overlay {
                // The window the selected stock sits in
                Capsule()
                    .strokeBorder(.white.opacity(Constants.CameraUI.lastPhotoBorderOpacity), lineWidth: Constants.CameraUI.lastPhotoBorderWidth)
                    .frame(width: Constants.CameraUI.dialItemWidth, height: Constants.CameraUI.dialHeight - Constants.CameraUI.dialCaptionSpacing * 2)
                    .allowsHitTesting(false)
            }
            Text(selected.label)
                .font(.system(size: Constants.CameraUI.captionFontSize, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(Constants.CameraUI.lastPhotoBorderOpacity))
                .accessibilityHidden(true)
        }
        .onAppear { position = selected }
        .onChange(of: position) { _, new in
            if let new, new != selected { onSelect(new) }
        }
        .onChange(of: selected) { _, new in
            if position != new {
                withAnimation(.easeOut(duration: Constants.CameraUI.dialSnapAnimationDuration)) { position = new }
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camera.dial")
    }

    private func choose(_ stock: StripCustomization.FilmStock) {
        withAnimation(.easeOut(duration: Constants.CameraUI.dialSnapAnimationDuration)) { position = stock }
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
                .foregroundStyle(.white)
                .opacity(isSelected ? 1 : Constants.CameraUI.dialUnselectedOpacity)
                .scaleEffect(isSelected ? Constants.CameraUI.dialSelectedScale : 1)
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
