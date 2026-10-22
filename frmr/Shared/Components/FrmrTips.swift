import OSLog
import SwiftUI
import TipKit

// v5.2 C1: the walkthrough is TipKit tips anchored to the real controls
// (research §5.9), replacing the coach-mark overlay. On-device and offline;
// each tip shows once, in context, and adopts the system popover (Liquid
// Glass on iOS 26, Dynamic Type, VoiceOver). Copy is from v5.1-8, split per
// anchor.

/// The stock dial: shown first.
struct DialTip: Tip {
    var title: Text { Text("Choose a film") }
    var message: Text? { Text("Swipe the dial to choose a film. The viewfinder shows it live.") }
    var image: Image? { Image(systemName: "film") }
}

/// The shutter: from the second launch on.
struct ShutterTip: Tip {
    static let appOpened = Tips.Event(id: "frmr.appOpened")
    /// Set once the dial tip has been dismissed or acted on, so the two
    /// popovers never compete.
    @Parameter static var isDialTipDone: Bool = false

    var title: Text { Text("Every shot opens the editor") }
    var message: Text? { Text("To keep shooting and edit later, turn off Edit after each shot in Settings.") }
    var image: Image? { Image(systemName: "camera.aperture") }
    var rules: [Rule] {
        [
            #Rule(Self.$isDialTipDone) { $0 },
            #Rule(Self.appOpened) { $0.donations.count >= 2 },
        ]
    }
}

/// Continue to diary, in the editor after a capture.
struct DiaryTip: Tip {
    var title: Text { Text("Write about a photo") }
    var message: Text? { Text("Continue to diary saves the photo, then gives you a prompt to answer.") }
    var image: Image? { Image(systemName: "book.closed") }
}

/// The mode switch, once a few photos are in the Roll.
struct ModeTip: Tip {
    static let photoSaved = Tips.Event(id: "frmr.photoSaved")

    var title: Text { Text("Make a photobooth strip") }
    var message: Text? { Text("Film strip mode fills four frames, then prints them as a strip.") }
    var image: Image? { Image(systemName: "film.stack") }
    var rules: [Rule] {
        [#Rule(Self.photoSaved) { $0.donations.count >= 3 }]
    }
}

enum FrmrTips {
    private static let logger = Logger(subsystem: "frmr", category: "tips")

    /// Once per launch, before any tip shows. Settings' "Show tips again"
    /// leaves a flag that clears the tip history here (TipKit's datastore can
    /// only be reset before it is configured).
    static func configure(defaults: UserDefaults = .standard) {
        #if DEBUG
        // UI tests: tips never cover the controls a test drives, unless a
        // test asks for them; then they start fresh and follow their real
        // rules (showAllTipsForTesting would re-show a closed tip forever)
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains(Constants.TipsUI.showTipsArgument) {
            resetDatastore()
        } else if arguments.contains(where: { $0.hasPrefix(Constants.TipsUI.uiTestArgumentPrefix) }) {
            Tips.hideAllTipsForTesting()
        }
        #endif
        if defaults.bool(forKey: Constants.TipsUI.resetOnLaunchKey) {
            resetDatastore()
            defaults.set(false, forKey: Constants.TipsUI.resetOnLaunchKey)
        }
        do {
            try Tips.configure([.displayFrequency(.immediate)])
        } catch {
            // Tips are a nicety: the app works the same without them
            logger.error("TipKit configure failed: \(error.localizedDescription)")
        }
    }

    /// Settings → Show tips again: takes effect on the next launch.
    static func requestReset(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: Constants.TipsUI.resetOnLaunchKey)
    }

    static func noteAppOpened() {
        Task { await ShutterTip.appOpened.donate() }
    }

    static func notePhotoSaved() {
        Task { await ModeTip.photoSaved.donate() }
    }

    private static func resetDatastore() {
        do {
            try Tips.resetDatastore()
        } catch {
            logger.error("TipKit reset failed: \(error.localizedDescription)")
        }
    }
}
