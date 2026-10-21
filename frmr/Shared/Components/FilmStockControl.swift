import SwiftUI

// v4 F9 camera Film control, built like WhiteBalanceControl: collapsed it is
// one chip with the film glyph over the active stock's short code; tapping
// it expands every stock inline. Picking one (or tapping the viewfinder)
// collapses it again. Each chip is the same fixed 44pt circle and only its
// glyph rotates (CameraChip), so nothing reflows when the phone turns.
struct FilmStockControl: View {
    let selected: StripCustomization.FilmStock
    let isExpanded: Bool
    let onToggle: () -> Void
    let onSelect: (StripCustomization.FilmStock) -> Void

    var body: some View {
        HStack(spacing: Constants.CameraUI.chipSpacing) {
            ForEach(CameraViewModel.visibleStocks(expanded: isExpanded, selected: selected)) { stock in
                CameraChip(
                    isSelected: stock == selected,
                    accessibilityLabel: "Film: \(stock.label)",
                    action: { isExpanded ? onSelect(stock) : onToggle() }
                ) {
                    FilmStockGlyph(code: stock.shortCode, showsSymbol: !isExpanded)
                }
                .accessibilityHint(isExpanded ? "Shoots on this film" : "Shows the film stocks")
                .accessibilityIdentifier("camera.film.\(stock.rawValue)")
            }
        }
        .animation(
            .easeInOut(duration: Constants.CameraUI.wbExpandAnimationDuration),
            value: isExpanded
        )
    }
}

// The collapsed chip carries the film glyph so it reads as the film control;
// in the expanded bank the codes alone tell the stocks apart.
private struct FilmStockGlyph: View {
    let code: String
    let showsSymbol: Bool

    var body: some View {
        VStack(spacing: Constants.CameraUI.filmChipLineSpacing) {
            if showsSymbol {
                Image(systemName: "film.stack")
                    .font(.system(size: Constants.CameraUI.filmChipSymbolSize, weight: .medium))
            }
            Text(code)
                .font(.system(size: Constants.CameraUI.filmChipCodeFontSize, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(Constants.CameraUI.filmChipCodeMinScale)
        }
        // Inset so the longest code (M3.2K) stays inside the circle
        .frame(width: Constants.CameraUI.filmChipContentWidth)
    }
}

#Preview {
    ZStack {
        Color.black
        VStack(spacing: 40) {
            FilmStockControl(selected: .cine500T, isExpanded: false, onToggle: {}, onSelect: { _ in })
            FilmStockControl(selected: .cine500T, isExpanded: true, onToggle: {}, onSelect: { _ in })
        }
    }
}
