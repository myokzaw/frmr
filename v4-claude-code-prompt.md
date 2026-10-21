# Prompt: build frmr v4 with Claude Code

Open Claude Code in the `frmr/` folder (the one containing `frmr.xcodeproj`) and paste everything inside the block below.

```
You are the lead engineer on frmr, a minimalist offline iOS photo-journal app.
We are building v4: a real film pipeline for the strip look.

READ FIRST, IN THIS ORDER, before writing any code:
1. CLAUDE.md                                      — hard constraints, code rules, agent team, file ownership
2. project.md                                     — product spec (§8 pipeline, §10 strip, §13 open decisions)
3. frmr-v2-spec.md                                — background for grain and film stocks (F4–F6)
4. frmr-v4-spec.md                                — THE SPEC YOU ARE IMPLEMENTING
5. .claude/skills/ios-camera-orientation/SKILL.md — orientation rules
Then read Features/Camera/ImageProcessor.swift, Features/Strip/StripGenerator.swift,
Features/Strip/StripViewModel.swift, Features/Strip/StripView.swift,
Models/StripCustomization.swift, the ImageProcessing section of Shared/Constants.swift,
and frmrTests/frmrTests.swift.

Before coding, reply with a short plan: what you understood, the order you will
work in, and anything in the spec you think is wrong or ambiguous. Wait for my OK.

HOW TO WORK
- Follow frmr-v4-spec.md §Sequencing exactly. F0 is already done — do not redo it.
  Order: F1 → F2+F3 → F7 model/migration → F4 → F5 → F6 → F7 UI → QA pass.
- One feature at a time. After each one:
  a) build with zero warnings, and
  b) run the unit tests:
     xcodebuild -project frmr.xcodeproj -scheme frmr \
       -destination 'platform=iOS Simulator,id=1B3A9DB6-1D5A-4447-9849-CF49C94A5FC8' \
       -only-testing:frmrTests test
     (if that simulator id is missing, pick one from `xcrun simctl list devices available`
     and use the id= form)
  c) update the "Implementation status — v4 build" table in frmr-v4-spec.md, then
  d) stop and give me a 3–5 line summary: what changed, test results, anything
     unverified. Wait for my "continue" before starting the next feature.
- Use the agent team in .claude/agents/ when it helps: frmr-backend for pipeline,
  model and tests; frmr-frontend for StripView and Settings, only after the F7
  model exists; frmr-qa for verification. Respect the ownership map in CLAUDE.md.
  Hand off with the DONE / DOING / BLOCKED / NEXT template.
- For F2/F3, write FilmModel.swift and FilmModelTests FIRST, as pure Swift with no
  Core Image. Only then build the colour cube and wire it into applyStripLook.
- For F1, measure strip render time before and after (cold and warm), and record
  the numbers in the spec.

NON-NEGOTIABLE RULES (from CLAUDE.md and the v4 spec)
- No network calls, no AI, no third-party dependencies, no Combine.
- Never call CIImage(image:) on a photo. Use ImageProcessor.uprightCIImage(from:).
  Photos are unrotated pixels plus an orientation tag.
- Every number goes in Constants.swift (Constants.ImageProcessing.Film for the film model).
- Open decisions v4-1…v4-8: use the documented default, mark the code
  `// OPEN: v4-N …`, and never invent a different answer.
- Effects are deterministic: seed from strip date and slot index. Re-rendering the
  same strip must be pixel-identical.
- Build the look from public film science. Do not copy another app's stock data,
  LUTs or presets, and do not use film brand names. Stock names come from the spec table.
- No force-unwraps in production code. Cosmetic filter failures fall back to the
  unfiltered photo and are logged; real errors go through AppError.
- Remove superseded code and tests (grainLuminanceCurve, colour-matrix casts,
  sizeCompensation) only after their replacements pass.
- Do not commit, push or delete anything outside the files the spec names without asking me.

WHAT YOU CANNOT VERIFY
The simulator has no camera or orientation sensor. Test strips through the
Photobooth gallery picker. List anything that needs a real iPhone (landscape
captures, on-device render time, how the look actually reads) as UNVERIFIED in your
summaries and in the spec. Never claim it works on device.

DONE MEANS every box in frmr-v4-spec.md §Definition of done is ticked or explicitly
marked as needing a device, and CLAUDE.md, project.md §8/§14 and README.md are updated.
```

## Tips

- **First, commit the current state.** The v3 spec notes the working tree is uncommitted. This gives you a clean point to roll back to if a feature goes wrong.
- **Run it one feature per session** if the conversation gets long. Start a new session with the same prompt, and the spec's status table tells it where to pick up.
- **To resolve an open decision** (for example, sliders instead of toggles), edit the table in `frmr-v4-spec.md` §Open decisions first. Then tell Claude Code, so the spec stays the source of truth.
