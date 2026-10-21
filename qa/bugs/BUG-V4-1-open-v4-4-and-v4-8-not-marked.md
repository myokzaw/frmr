# BUG-V4-1 OPEN v4-4 (strip vignette) and v4-8 (cube vs kernel) are not marked in code
- Severity: minor | Owner: backend
- Files: frmr/Features/Camera/ImageProcessor.swift:136-172 (applyStripLook effect order, where the absent strip vignette would sit) and :347-370 (applyFilmCube, the cube-vs-CIColorKernel choice); frmr/Shared/Constants.swift `ImageProcessing.Film` (no value for either).
- Steps: `grep -rn 'v4-4\|v4-8' frmr/` returns nothing.
- Expected (frmr-v4-spec.md §Definition of done, "Every // OPEN: in v4 files is marked in code, with its value in Constants.swift"; §Open decisions v4-4, v4-8): each v4 open item carries an `// OPEN: v4-N` marker and a Constants value (e.g. `stripVignetteEnabled = false`, a note on the cube choice next to `lutDimension`).
- Actual: v4-1, -2, -3, -5, -6, -7 are marked; v4-4 and v4-8 are not.
- Evidence: grep output above. Not reproducible as a unit test (a source-text check).
