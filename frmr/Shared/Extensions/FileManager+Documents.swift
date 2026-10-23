import Foundation

// Photos and rendered strips are stored as files in Documents; SwiftData
// stores only relative paths because absolute container URLs change across
// iOS updates.
extension FileManager {
    static var documentsDirectory: URL {
        URL.documentsDirectory
    }

    // Resolves a stored relative path back to an absolute URL
    static func documentsURL(forRelativePath path: String) -> URL {
        documentsDirectory.appending(path: path)
    }

    static func createPhotosDirectory() throws -> URL {
        let url = documentsDirectory.appending(path: "Photos", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func createRollDirectory() throws -> URL {
        let url = documentsDirectory.appending(path: Constants.Roll.photosDirectoryName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func createStripsDirectory() throws -> URL {
        let url = documentsDirectory.appending(path: "Strips", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
