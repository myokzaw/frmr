---
name: qa-state
description: Recurring QA findings and device-only items for frmr camera rotation work
metadata:
  type: project
---
- Angle (SwiftUI) stores radians: compare degrees with tolerance, never ==.
- Bug class: modifier order with .position + rotationEffect (pivot = parent centre). Check on every rotatingWithDevice use.
- UI test runner (frmrUITests) DOES launch and pass on simulator id 1B3A9DB6 (2026-10-06).
- Git baseline is the template; can't diff tests against HEAD.
- Device-only: rotation sign, capture upright, CaptureSession [weak self] capture, haptics.
