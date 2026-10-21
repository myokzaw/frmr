# OBS-V4-4 Settings → Strip defaults doesn't mirror the strip screen's rules
- Severity: minor (observation) | Owner: frontend
- File: frmr/Features/Settings/SettingsView.swift:90-96.
- Observed: the Halation / Bloom / Light leak toggles show even when the default stock is Off (they have no effect then), and the Black & white toggle is neither shown on nor disabled for Mono 400 / Mono 3200, whereas StripView hides effects for Off (`areEffectsVisible`) and locks B&W for mono stocks (`isBlackAndWhiteLocked`).
- Spec: §F7 Settings only lists the controls, so this is not a spec violation; it is an inconsistency a user can see (toggle B&W off with Mono 400 in Settings, open a strip: B&W shows on and locked).
- Suggest: reuse the same rules (ideally via a small pure helper so they're tested once).
