import CoreGraphics
import Testing
@testable import frmr

// BUG-122-03: a digitally zoomed shot crashed the app, because Bayer RAW
// capture raises an exception unless the zoom and crop are exactly 1.
struct ZoomedCaptureTests {

    @Test func rawAtNativeZoom() {
        #expect(CaptureSession.canCaptureBayerRaw(zoomFactor: 1, isRampingZoom: false, cropFactor: 1))
    }

    @Test(arguments: [1.01, 1.5, 2, 5] as [CGFloat])
    func processedOnlyWhenDigitallyZoomed(zoom: CGFloat) {
        #expect(!CaptureSession.canCaptureBayerRaw(zoomFactor: zoom, isRampingZoom: false, cropFactor: 1))
    }

    @Test func processedOnlyWhileZoomIsRamping() {
        #expect(!CaptureSession.canCaptureBayerRaw(zoomFactor: 1, isRampingZoom: true, cropFactor: 1))
    }

    @Test func processedOnlyWhenTheConnectionCrops() {
        #expect(!CaptureSession.canCaptureBayerRaw(zoomFactor: 1, isRampingZoom: false, cropFactor: 2))
    }
}
