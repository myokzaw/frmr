---
name: rotation-angle-accumulated
description: CameraViewModel.rotationAngle is accumulated/unwrapped; ChromeLayout removed; onboarding uses isPortrait
metadata:
  type: project
---

rotationAngle(for:current:) returns current + shortest delta in (-180,180]; exact 180 ties always take +180 (deterministic). ChromeLayout and v3-5 OPEN removed; OnboardingViewModel gates on `isPortrait` (static `isPortrait(for:current:)`). WBMode.symbolName lives in WhiteBalanceControl.swift (enum part only is backend's).
Build tip: use simulator `id=` destination; BSD sed fails on `-i` without suffix, so use Edit tool.
