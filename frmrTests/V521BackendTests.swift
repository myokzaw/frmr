import SwiftData
import Testing
import UIKit
@testable import frmr

// v5.2.1: BUG-521-01/02, F-PICK, F-GRID and the prompt's display image.

private func tone(_ white: CGFloat = 0.5, size: CGSize = CGSize(width: 96, height: 72)) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
        UIColor(white: white, alpha: 1).setFill()
        context.fill(CGRect(origin: .zero, size: size))
    }
}

@MainActor
private func memoryContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: DiaryEntry.self, DailyStrip.self, RollPhoto.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return ModelContext(container)
}

private func removeRollFiles(_ photos: [RollPhoto]) {
    for photo in photos {
        try? FileManager.default.removeItem(at: FileManager.documentsURL(forRelativePath: photo.photoPath))
    }
}

// MARK: - BUG-521-01

@MainActor
struct WhiteBalanceAutoResetTests {
    private func camera() throws -> CameraViewModel { CameraViewModel(defaults: try makeScratchDefaults()) }

    @Test(arguments: ["preset", "slider"])
    func autoReturnsToTheStartValuesAndReadsAuto(from: String) throws {
        let camera = try camera()
        if from == "preset" {
            camera.chooseWhiteBalancePreset(.tungsten)
            #expect(camera.whiteBalanceKelvinText == "3200K")
        } else {
            camera.setWhiteBalance(kelvin: 4321, tint: 12)
            #expect(camera.whiteBalanceKelvinText == "4321K" && camera.whiteBalanceTintText == "+12")
        }
        camera.chooseWhiteBalancePreset(.auto)
        #expect(camera.whiteBalanceKelvin == Constants.Camera.whiteBalanceManualStartKelvin)
        #expect(camera.whiteBalanceTint == Constants.Camera.whiteBalanceManualStartTint)
        #expect(camera.whiteBalanceKelvinText == "Auto" && camera.whiteBalanceTintText == "Auto")
        #expect(!camera.isWhiteBalanceAdjusted && camera.whiteBalanceChipText == "AUTO")
    }

    @Test(arguments: [(Float(0), "0"), (12, "+12"), (-5, "-5"), (90, "+50")])
    func tintReadout(tint: Float, expected: String) throws {
        let camera = try camera()
        camera.setWhiteBalance(kelvin: 5600, tint: tint)
        #expect(camera.whiteBalanceTintText == expected)
    }
}

// MARK: - BUG-521-02

@MainActor
struct ReEditContinueToDiaryTests {
    @Test func freshCaptureCanContinueWithoutAnyCount() {
        #expect(PhotoEditViewModel(preview: tone(), stock: .none).canContinueToDiary)
    }

    @Test func reEditWithNoEntryCanContinueAndSavesOntoTheExistingPhoto() async throws {
        let context = try memoryContext()
        let row = try RollViewModel.insert(original: tone(), look: .original, capturedAt: .now, context: context)
        defer { removeRollFiles(try! context.fetch(FetchDescriptor<RollPhoto>())) }
        let edit = try #require(PhotoEditViewModel(editing: row))
        #expect(!edit.canContinueToDiary, "unknown count hides it")
        edit.loadLinkedEntryCount(context: context)
        #expect(edit.canContinueToDiary)

        edit.selectStock(.cine500T)
        #expect(await edit.continueToDiary(context: context))
        #expect(try context.fetch(FetchDescriptor<RollPhoto>()).count == 1, "no new photo")
        #expect(row.look.stock == .cine500T)
        #expect(edit.diaryContinuation?.rollPhotoID == row.id && edit.outcome == .continuedToDiary)
    }

    @Test func reEditWithAnEntryOnlySaves() async throws {
        let context = try memoryContext()
        let row = try RollViewModel.insert(original: tone(), look: .original, capturedAt: .now, context: context)
        defer { removeRollFiles([row]) }
        let diary = DiaryViewModel()
        diary.prepareNewEntry()
        #expect(diary.saveEntry(image: nil, rollPhotoID: row.id, includeText: false, context: context))
        let edit = try #require(PhotoEditViewModel(editing: row))
        edit.loadLinkedEntryCount(context: context)
        #expect(edit.loadedLinkedEntryCount == 1 && !edit.canContinueToDiary)
        #expect(await !edit.continueToDiary(context: context))
    }
}

// MARK: - F-PICK

@MainActor
struct PhotoboothRollPickTests {
    private func rows(_ count: Int, in context: ModelContext) throws -> [RollPhoto] {
        try (0..<count).map { _ in
            try RollViewModel.insert(original: tone(), look: .original, capturedAt: .now, context: context)
        }
    }

    @Test func pickedPhotoShowsUprightWithItsSlotNumber() throws {
        let context = try memoryContext()
        let photos = try rows(2, in: context)
        defer { removeRollFiles(photos) }
        let booth = PhotoboothViewModel()
        booth.toggle(rollPhoto: photos[0])
        booth.toggle(rollPhoto: photos[1])
        let image = try #require(booth.image(at: 0))
        #expect(image.imageOrientation == .up && image.size == CGSize(width: 96, height: 72))
        #expect(booth.shot(at: 1)?.rollPhotoID == photos[1].id)
        #expect(booth.slotNumber(forRollPhoto: photos[1].id) == 2)
        #expect(booth.rollPickerTitle == "2 of 4 picked")
    }

    @Test func toggleRemovesAndRenumbers() throws {
        let context = try memoryContext()
        let photos = try rows(3, in: context)
        defer { removeRollFiles(photos) }
        let booth = PhotoboothViewModel()
        photos.forEach { booth.toggle(rollPhoto: $0) }
        booth.toggle(rollPhoto: photos[0])
        #expect(booth.slotNumber(forRollPhoto: photos[0].id) == nil)
        #expect(booth.slotNumber(forRollPhoto: photos[1].id) == 1 && booth.slotNumber(forRollPhoto: photos[2].id) == 2)
        booth.toggle(rollPhoto: photos[1])
        booth.toggle(rollPhoto: photos[1])
        #expect(booth.slotNumber(forRollPhoto: photos[1].id) == 2, "re-picked goes to the end")
    }

    @Test func fullStripStillAllowsUnpickingAndCountsOtherShots() throws {
        let context = try memoryContext()
        let photos = try rows(2, in: context)
        defer { removeRollFiles(photos) }
        let booth = PhotoboothViewModel()
        booth.add(tone())
        booth.add(tone())
        booth.toggle(rollPhoto: photos[0])
        booth.toggle(rollPhoto: photos[1])
        #expect(booth.isFull && booth.rollPickerTitle == "4 of 4 picked")
        #expect(booth.slotNumber(forRollPhoto: photos[1].id) == 4)
        booth.toggle(rollPhoto: photos[0])
        #expect(booth.shots.count == 3 && booth.slotNumber(forRollPhoto: photos[1].id) == 3)
    }

    @Test func theSamePhotoCannotBePickedTwice() throws {
        let context = try memoryContext()
        let photos = try rows(1, in: context)
        defer { removeRollFiles(photos) }
        let booth = PhotoboothViewModel()
        booth.add(rollPhoto: photos[0])
        booth.add(rollPhoto: photos[0])
        #expect(booth.shots.count == 1)
    }
}

// MARK: - F-GRID

struct CameraGridTests {
    @Test(arguments: [
        (CameraGrid.off, [CGFloat]()),
        (.thirds, [1.0 / 3.0, 2.0 / 3.0]),
        (.square, [0.25, 0.5, 0.75]),
        (.golden, [0.382, 0.618]),
    ])
    func fractions(grid: CameraGrid, expected: [CGFloat]) {
        #expect(CameraGrid.lineFractions(for: grid) == expected)
        #expect(!grid.label.isEmpty)
    }

    @Test func storedValueRoundTripsAndUnknownReadsAsOff() throws {
        let defaults = try makeScratchDefaults()
        #expect(CameraGrid.stored(in: defaults) == .off)
        for grid in CameraGrid.allCases {
            grid.store(in: defaults)
            #expect(CameraGrid.stored(in: defaults) == grid)
        }
        defaults.set("diagonal", forKey: Constants.DefaultsKeys.cameraGrid)
        #expect(CameraGrid.stored(in: defaults) == .off)
    }
}

// MARK: - Diary prompt display image

@MainActor
struct DiaryPromptDisplayImageTests {
    @Test(arguments: [CGSize(width: 4000, height: 3000), CGSize(width: 3000, height: 4000), CGSize(width: 800, height: 600)])
    func longSideIsAtMost1600AndNeverEnlarged(size: CGSize) {
        let result = CameraViewModel.promptDisplayImage(from: tone(size: size))
        let pixels = max(result.size.width * result.scale, result.size.height * result.scale)
        #expect(pixels <= CGFloat(Constants.Diary.promptDisplayMaxPixels))
        #expect(pixels == min(max(size.width, size.height), 1600))
    }

    @Test func theContinuationGetsADisplayCopyAndTheOriginalIsUntouched() async throws {
        let context = try memoryContext()
        let camera = CameraViewModel(defaults: try makeScratchDefaults())
        let edit = camera.beginPhotoEdit(preview: tone(size: CGSize(width: 3200, height: 2400)), stock: .none)
        #expect(await edit.continueToDiary(context: context))
        defer { removeRollFiles(try! context.fetch(FetchDescriptor<RollPhoto>())) }
        await camera.promptImageSettled()
        let display = try #require(camera.pendingDiaryDisplayImage)
        #expect(max(display.size.width, display.size.height) * display.scale <= 1600)
        #expect(camera.pendingDiaryImage?.size == CGSize(width: 3200, height: 2400))
    }
}
