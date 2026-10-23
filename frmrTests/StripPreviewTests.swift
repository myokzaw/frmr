import Testing
import UIKit
@testable import frmr

@MainActor
struct StripPreviewTests {

    private func photo(_ white: CGFloat = 0.5) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: 96, height: 72)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(white: white, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func strip(_ items: [StripItem]? = nil) -> StripViewModel {
        let model = StripViewModel(
            items: items ?? [StripItem(image: photo(), caption: "", entryID: nil, filmStock: .portrait400)],
            isPhotobooth: true
        )
        model.customization = StripCustomization()
        return model
    }

    private let size = CGSize(width: 24, height: 24)

    @Test func rendersEveryStockAndAsShot() async {
        let model = strip()
        model.requestPreviews(size: size, scale: 2)
        await model.previewsSettled()
        #expect(Set(model.stockPreviews.keys) == Set(StripCustomization.FilmStock.allCases))
        #expect(model.asShotPreview != nil)
        // As shot: no override, so no print choice
        #expect(model.printPreviews.isEmpty)
    }

    @Test func printsMatchTheCurrentStocksAvailablePrints() async {
        let model = strip()
        model.customization.filmStock = .portrait400
        model.requestPreviews(size: size, scale: 2)
        await model.previewsSettled()
        #expect(Set(model.printPreviews.keys) == Set(model.availablePrints))
        #expect(!model.printPreviews.isEmpty)
    }

    @Test func repeatCallsHitTheCacheAndChangesRenderAgain() async {
        let model = strip()
        model.requestPreviews(size: size, scale: 2)
        await model.previewsSettled()
        #expect(model.previewRenderCount == 1)
        let cached = model.stockPreviews[.daylight200]

        model.requestPreviews(size: size, scale: 2)
        await model.previewsSettled()
        #expect(model.previewRenderCount == 1 && model.stockPreviews[.daylight200] === cached)

        model.customization.blackAndWhite = true
        model.requestPreviews(size: size, scale: 2)
        await model.previewsSettled()
        #expect(model.previewRenderCount == 2)

        model.requestPreviews(size: CGSize(width: 30, height: 30), scale: 2)
        await model.previewsSettled()
        #expect(model.previewRenderCount == 3)
    }

    @Test func emptyItemsGiveEmptyPreviews() async {
        let model = strip([])
        model.requestPreviews(size: size, scale: 2)
        await model.previewsSettled()
        #expect(model.stockPreviews.isEmpty && model.asShotPreview == nil && model.printPreviews.isEmpty)

        let noImage = strip([.empty])
        noImage.requestPreviews(size: size, scale: 2)
        await noImage.previewsSettled()
        #expect(noImage.stockPreviews.isEmpty && noImage.asShotPreview == nil)
    }
}
