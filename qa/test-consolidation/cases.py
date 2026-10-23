#!/usr/bin/env python3
"""Usage: cases.py <xcodebuild-test-log>  -> one line per parameterised test with its case count, and the total."""
import re, sys
rows = []
for line in open(sys.argv[1], encoding="utf-8"):
    line = line.replace("​", "").strip()
    m = re.match(r'^✔ Test "?(.*?)"? with (\d+) test cases? passed', line)
    if m:
        rows.append((m.group(1), int(m.group(2))))
for name, n in sorted(rows):
    print(f"{n:4d} cases  {name}")
print(f"-- {len(rows)} parameterised tests, {sum(n for _, n in rows)} argument cases")
