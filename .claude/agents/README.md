# frmr agent team

Two agents per round (fewer merge conflicts), both on **Sonnet**:
- `frmr-frontend`: views, components, `*UI` constants.
- `frmr-backend`: ViewModels, engine, models, other constants.
- `frmr-qa` runs after both, or on its own for the accessibility pass.

Ownership is in each role file; together they cover every file. If a task spans both sides, split it into a backend part and a frontend part.

## Keeping usage low
- The lead's prompt names the exact files and spec section. Agents read nothing else.
- Agents make the smallest change that meets the task: no drive-by refactors, and each file read once.
- Agents run tests by tier: `suite` while iterating, `fast` before handing back. The full `all` tier runs only at round end, by the lead or QA.
- Screenshots only on request.
- Reports are short (≤15–20 lines). The lead re-runs the tests rather than trusting long logs.

## Handoff template

```
Task: <one sentence>. Spec: <file §section>.
Files: <paths you expect to touch>.
Acceptance: <bullets>.
Test: <suite names>.
Don't guess OPEN items: flag them.
```

Film-look changes: read and update `docs/film-simulation.md` in the same change.
