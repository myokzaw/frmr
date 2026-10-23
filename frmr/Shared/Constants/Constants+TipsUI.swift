import Foundation

nonisolated extension Constants {
    // MARK: TipKit walkthrough (v5.2 C1)
    enum TipsUI {
        // The TipKit #Rule macro needs literal counts, so the thresholds
        // (shutter tip: second launch; mode tip: third saved photo) live in
        // FrmrTips.swift itself.
        /// Set by Settings → Show tips again; read and cleared at launch.
        static let resetOnLaunchKey = "tipsResetOnNextLaunch"
        /// DEBUG only: UI tests hide tips unless they pass this argument.
        static let showTipsArgument = "-UITestShowTips"
        static let uiTestArgumentPrefix = "-UITest"
    }
}
