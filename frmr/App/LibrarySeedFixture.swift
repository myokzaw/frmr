#if DEBUG
import SwiftData
import SwiftUI

// Compiled out of release. Launched with `-UITestSeedLibrary` (alongside
// `-UITestSeedRoll`), the app adds what the Library's other tabs need so a UI
// test or a screenshot run can see them without a camera: one diary entry
// linked to the newest Roll photo (it earns the book badge), one older entry
// with its own photo file, and one saved strip. The older entry and the strip
// are added only once per simulator; the linked entry on every launch.
enum LibrarySeedFixture {
    static let launchArgument = "-UITestSeedLibrary"
    static let linkedResponse = "Morning light on the table, coffee gone cold."
    static let legacyResponse = "The walk home took longer than it should have."

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    @MainActor
    static func seed(in context: ModelContext) {
        seedLinkedEntry(in: context)
        guard (try? context.fetchCount(FetchDescriptor<DailyStrip>())) == 0 else { return }
        seedLegacyEntry(in: context)
        seedStrip(in: context)
    }

    @MainActor
    private static func seedLinkedEntry(in context: ModelContext) {
        var descriptor = FetchDescriptor<RollPhoto>(sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        guard let photo = try? context.fetch(descriptor).first else { return }
        context.insert(DiaryEntry(
            photoPath: photo.photoPath,
            prompt: "What made you take this picture?",
            response: linkedResponse,
            capturedAt: photo.capturedAt,
            look: photo.look,
            rollPhotoID: photo.id
        ))
        try? context.save()
    }

    @MainActor
    private static func seedLegacyEntry(in context: ModelContext) {
        guard let directory = try? FileManager.createPhotosDirectory() else { return }
        let filename = UUID().uuidString + ".jpg"
        let image = gradient(from: .systemTeal, to: .systemBrown, size: CGSize(width: 900, height: 1200))
        guard let data = image.jpegData(compressionQuality: 0.8),
              (try? data.write(to: directory.appending(path: filename))) != nil else { return }
        context.insert(DiaryEntry(
            createdAt: Date.now.addingTimeInterval(-86_400 * 2),
            photoPath: "Photos/" + filename,
            prompt: "Where did today take you?",
            response: legacyResponse,
            filmStock: .daylight200
        ))
        try? context.save()
    }

    @MainActor
    private static func seedStrip(in context: ModelContext) {
        let strip = DailyStrip(createdAt: Date.now.addingTimeInterval(-86_400), entryIDs: [], isPhotobooth: true)
        guard let directory = try? FileManager.createStripsDirectory() else { return }
        let image = gradient(from: .systemIndigo, to: .systemOrange, size: CGSize(width: 400, height: 1400))
        guard let data = image.pngData(),
              (try? data.write(to: directory.appending(path: strip.id.uuidString + ".png"))) != nil else { return }
        context.insert(strip)
        try? context.save()
    }

    private static func gradient(from start: UIColor, to end: UIColor, size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            let colors = [start.cgColor, end.cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil) else { return }
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
        }
    }
}
#endif
