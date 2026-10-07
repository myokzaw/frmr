# frmr agent team

Three agents, split along real interface boundaries (see the `## Agent team` section of `CLAUDE.md` for the ownership map):

- `frmr-frontend` — everything the user sees (SwiftUI views, components, chrome rotation, onboarding overlay, accessibility).
- `frmr-backend` — everything below the view (capture, image pipeline, strips, SwiftData, ViewModel logic).
- `frmr-qa` — black-box verifier. Reports bugs and writes regression tests; never fixes production code.

Agents are loaded at session start. After creating or editing `.claude/agents/`, **restart Claude Code**.

## Default: parallel, low ceremony

In a normal session, ask:

> Run frmr-backend on `<task>` and frmr-frontend on `<task>` in parallel, then run frmr-qa on the result.

- Subagents run in the background and share one folder. Parallel work is safe only because of the ownership map.
- If a task needs files from both sides, split it into a backend part and a frontend part, or run the two sequentially.
- QA runs after both have finished.
- Builds use separate folders so they don't fight over one Xcode cache: `-derivedDataPath build/frontend`, `build/backend`, `qa/DerivedData`.

## Optional: team mode (experimental)

Set `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, then ask the lead to "spawn teammates using the frmr-frontend, frmr-backend and frmr-qa agent types". Teammates share a task list and can message each other, so a contract request can go straight from frontend to backend.

Documented limits:

- Teammates aren't restored on `/resume`.
- An in-process teammate gets the definition's tools and body but **not its skills**. Tell each teammate in its spawn prompt to read `.claude/skills/ios-camera-orientation/SKILL.md`.

## Every delegation uses the handoff template

```
You are working on [FEATURE] in a minimalist iOS journaling app.

Context files (required reading, in order):
1. CLAUDE.md  — engineering rules and constraints
2. project.md — full product specification

Situation:
  DONE:    [list]
  DOING:   [current task or "nothing"]
  BLOCKED: [open decisions blocking this work, or "none"]
  NEXT:    [your specific task]

Deliverable: [exactly what to produce — file, diff, test results, etc.]

Do not add dependencies. Do not make network calls. Do not resolve OPEN: items by guessing — flag them and use the placeholder pattern.
```

## First assignment (not yet run)

Current state from `frmr-v3-spec.md`: v3 F1–F6 are implemented with a clean build. Tests are written but have never been run. The F1 root cause is still unknown. The v3-5 edge mapping, capture orientation and all v2 camera gestures are unverified on device.

1. **frmr-qa first.** Run the guard script and the full suite. Produce the pass/fail table and bug list. Write the physical-device checklist for F1, F2, v3-5 and capture orientation, including the step that sets `Constants.CameraUI.chromeDebugOverlayEnabled = true` (DEBUG builds only) so the live `chromeLayout` and rotation angle can be photographed.
2. **Then in parallel:**
   - `frmr-backend` takes the backend-owned failures.
   - `frmr-frontend` takes the frontend-owned failures. Specifically ask it to check the `UIDeviceOrientation` vs `UIInterfaceOrientation` landscape inversion against the v3-5 mapping **before any device session**.
3. **frmr-qa again** once both have finished.
