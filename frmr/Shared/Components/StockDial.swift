import SwiftUI

// v5 F2 / v5.1 F8 / v5.2 S1 film-stock dial: a slim glass bar of the seven
// stocks that snaps one detent at a time, the selected one centred. Each
// detent is a swatch of how the stock renders (FilmSwatch, v5.2-5) above its
// code; the selected one is outlined in amber. Swiping or tapping selects; a
// selection haptic ticks per detent. The selected stock's full name is a
// small label just above the bar. The edges fade instead of clipping.
//
// Rotation (v5-3): the bar is a wide control, so it never turns; each
// detent's content turns about its own centre inside its fixed-width cell.
struct StockDial: View {
    let selected: StripCustomization.FilmStock
    let onSelect: (StripCustomization.FilmStock) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position: StripCustomization.FilmStock?

    private typealias UI = Constants.CameraUI

    var body: some View {
        VStack(spacing: UI.dialNameSpacing) {
            Text(selected.label)
                .font(.frmrMeta.weight(.medium))
                .foregroundStyle(.white.opacity(UI.dialNameOpacity))
                .frmrChromeTypeSize()
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
                max(0, (geometry.size.width - UI.dialItemWidth) / 2),
                for: .scrollContent
            )
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $position, anchor: .center)
            .mask(edgeFade)
        }
        .frame(height: UI.dialHeight)
        .frmrGlassCapsule()
        .clipShape(Capsule())
    }

    // Soft edges instead of a hard clip mid-code
    private var edgeFade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: UI.dialFadeFraction),
                .init(color: .black, location: 1 - UI.dialFadeFraction),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // The FrmrMotion snap curve, or a plain ease under Reduce Motion
    private var snapAnimation: Animation? {
        FrmrMotion.snap.animation(reduceMotion: reduceMotion)
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

    private typealias UI = Constants.CameraUI

    var body: some View {
        Button(action: action) {
            VStack(spacing: UI.dialSwatchSpacing) {
                StockSwatch(stock: stock, isSelected: isSelected)
                Text(stock.shortCode)
                    .frmrCodeStyle()
                    .foregroundStyle(isSelected ? Color.appAmber : .white)
                    .opacity(isSelected ? 1 : UI.dialUnselectedOpacity)
                    .lineLimit(1)
                    .minimumScaleFactor(UI.dialCodeMinScale)
            }
            // Four mono characters in a fixed cell: capped lower than the
            // rest of the chrome; the Large Content Viewer shows the name
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            .rotatingWithDevice()
            .frame(width: UI.dialItemWidth, height: UI.dialHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Film: \(stock.label)")
        .accessibilityHint("Shoots on this film")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("camera.dial.\(stock.rawValue)")
        .frmrLargeContent(LocalizedStringKey(stock.label), systemImage: "film")
    }
}

/// Three patches (skin, sky, foliage) rendered through the stock: how it
/// behaves, at a glance. Decorative; the detent's label names the stock.
struct StockSwatch: View {
    let stock: StripCustomization.FilmStock
    var isSelected = false

    private typealias UI = Constants.CameraUI
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: UI.dialSwatchCornerRadius) }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(FilmSwatch.colors(for: stock).enumerated()), id: \.offset) { _, color in
                color
            }
        }
        .frame(width: UI.dialSwatchWidth, height: UI.dialSwatchHeight)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(isSelected ? Color.appAmber : .white.opacity(UI.dialSwatchRimOpacity), lineWidth: isSelected ? UI.dialSwatchSelectedRing : UI.dialSwatchRim)
        }
        .opacity(isSelected ? 1 : UI.dialUnselectedOpacity)
        .accessibilityHidden(true)
    }
}

#Preview {
    ZStack {
        Color.black
        StockDial(selected: .portrait400, onSelect: { _ in })
    }
}
