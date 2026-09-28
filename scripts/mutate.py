#!/usr/bin/env python3
"""Manual mutation testing: plant one real bug at a time, the suite must fail for each.

Fail-closed: an anchor that is missing or not unique, a mutant that leaves the file
unchanged, a dirty Sources/ tree before or after, or a surviving mutant all exit 1.
Restores every mutant with `git checkout` and proves the restore with `git diff`.
"""

import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = "Sources/HydrateCore/Hydrate.swift"

# (id, what the bug is, anchor, replacement)
MUTANTS = [
    ("M1", "every regular file counts as placeholder",
     "(attrs[.size] as? Int) == 0", "(attrs[.size] as? Int) ?? 0 >= 0"),
    ("M2", "Office lock files not skipped",
     'name.hasPrefix(".") || name.hasPrefix("~$")', 'name.hasPrefix(".")'),
    ("M3", "hidden folders walked",
     "walker?.skipDescendants()", "_ = 0"),
    ("M4", "--jobs 0 accepted",
     "guard let n = Int(v), n > 0", "guard let n = Int(v), n >= 0"),
    ("M5", "no concurrency limit",
     "queue.maxConcurrentOperationCount = jobs", "_ = jobs"),
    ("M6", "timeout ignored",
     "_ = done.wait(timeout: .now() + timeout)", "done.wait()"),
    ("M7", "dry run downloads",
     "        for file in files { out(\"  \\(file)\") }\n        return 0",
     "        for file in files { out(\"  \\(file)\") }"),
    ("M8", "files that stay empty still exit 0",
     "if result.empty.isEmpty { return 0 }", "if true { return 0 }"),
    ("M9", "coordinated read writes to the file",
     "_ = try? handle?.read(upToCount: 1)",
     'try? "x".write(to: url, atomically: false, encoding: .utf8)'),
    ("M10", "no default path",
     'if o.paths.isEmpty { o.paths = ["."] }', "_ = 0"),
]


def sh(*cmd, check=True):
    return subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, check=check)


def sources_clean():
    return sh("git", "diff", "--quiet", "--", "Sources", check=False).returncode == 0


# Negative control (--control): a harmless edit the suite cannot notice. The runner must
# report it as SURVIVED and exit 1 — proof that it can see a survivor at all.
CONTROL = [("C0", "harmless comment edit (must survive)",
            "// Own thread per file:", "// One thread per file:")]


def main():
    global MUTANTS
    if sys.argv[1:] == ["--control"]:
        MUTANTS = CONTROL
    if not sources_clean():
        sys.exit("mutate: Sources/ has uncommitted changes — commit first")
    path = ROOT / SRC
    original = path.read_text()
    survived = []
    for mid, what, anchor, replacement in MUTANTS:
        count = original.count(anchor)
        if count != 1:
            sys.exit(f"mutate: {mid} anchor found {count}x (need exactly 1): {anchor!r}")
        mutated = original.replace(anchor, replacement)
        if mutated == original:
            sys.exit(f"mutate: {mid} changed nothing")
        path.write_text(mutated)
        try:
            if sh("git", "diff", "--quiet", "--", SRC, check=False).returncode == 0:
                sys.exit(f"mutate: {mid} not visible in git diff — not applied")
            result = sh("swift", "test", check=False)
        finally:
            sh("git", "checkout", "--", SRC)
        if not sources_clean():
            sys.exit(f"mutate: restore after {mid} failed")
        compiled = "error:" not in result.stdout + result.stderr or "Executed" in result.stdout
        status = "killed" if result.returncode != 0 else "SURVIVED"
        how = "" if compiled else " (compile error — does not count as a kill)"
        if result.returncode != 0 and not compiled:
            status = "NOT-A-KILL"
        print(f"{mid:4} {status:10} {what}{how}", flush=True)
        if status != "killed":
            survived.append(mid)
    total = len(MUTANTS)
    print(f"mutation: {total - len(survived)}/{total} killed")
    sys.exit(1 if survived else 0)


if __name__ == "__main__":
    main()
