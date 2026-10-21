# OBS-V4-5 Grain and light-leak seeds repeat across strips rendered together
- Severity: minor (observation) | Owner: backend
- File: frmr/Features/Strip/StripGenerator.swift:141 — `seed(for: date, slot: index)`, where `index` is the slot within one chunk (0..<4); StripViewModel.renderStrips renders every chunk with the same `date`.
- Observed: with 5+ photos the second strip's frame 1 gets exactly the same grain field and light-leak placement as the first strip's frame 1.
- Spec: §Theme C "seed derived from the strip date and slot index" — literally met, so not a bug. Raising it because identical grain/leak on two prints from one session is the "digital filter" tell v2 F6 tried to avoid. Fix would be to fold the chunk index into the seed (still deterministic).
