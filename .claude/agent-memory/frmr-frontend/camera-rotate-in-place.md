---
name: camera-rotate-in-place
description: Camera chrome design rule (square chips, static backing + rotating glyph, env-based angle) and simulator verification limits
metadata:
  type: project
---

Camera chrome rotates in place (no edge strip, no stacking). Chips are fixed 44pt circles (icon or short text); wide capsules (mode toggle, flip) stay static and only the glyph rotates. Angle comes via `EnvironmentValues.deviceRotation`, applied with `.rotatingWithDevice()`.

**Why:** rotationEffect doesn't reflow; wide views overflow into neighbours when turned.
**How to apply:** never put text wider than tall in a rotating frame; use SF Symbols + accessibilityLabel.

Simulator limits: xcodebuild destination by name+OS fails (several 26.4 runtimes); use `id=1B3A9DB6-1D5A-4447-9849-CF49C94A5FC8`. Simulator.app is not running (headless), so no tapping, no rotation; camera permission alert can't be dismissed via simctl privacy grant. Landscape and expanded-WB states cannot be screenshotted here.
