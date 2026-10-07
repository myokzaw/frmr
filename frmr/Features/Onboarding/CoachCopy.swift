import Foundation

// Static copy for the walkthrough — zero logic, same discipline as PromptBank.
// One line of body text per step: if a step needs a paragraph, the underlying
// UI is the thing to fix.
nonisolated enum CoachCopy {
    static let entries: [CoachStep: (title: String, body: String)] = [
        .library: (
            title: "Library",
            body: "Your saved entries and film strips live here."
        ),
        .camera: (
            title: "Camera",
            body: "Take a photo, get a prompt, write a line."
        ),
        .settings: (
            title: "Settings",
            body: "Appearance, camera defaults, and strip styles."
        ),
    ]
}
