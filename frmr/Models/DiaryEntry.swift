import Foundation
import SwiftData

@Model
final class DiaryEntry {
    var id: UUID
    var createdAt: Date
    var photoPath: String       // relative path in Documents — not a Data blob
    var prompt: String
    var response: String

    init(id: UUID = UUID(), createdAt: Date = .now, photoPath: String, prompt: String, response: String) {
        self.id = id
        self.createdAt = createdAt
        self.photoPath = photoPath
        self.prompt = prompt
        self.response = response
    }
}
