#!/usr/bin/env python3
"""Build the auto-remediation PR body from the qscanner patch diff and log.

Usage: build-remediation-pr-body.py <requirements-path> <patch-log-path>

Prints Markdown to stdout: a table of package version bumps derived from
`git diff` on the patched requirements.txt, followed by a collapsed excerpt
of the qscanner patch log for detail.
"""
import re
import subprocess
import sys

SPEC_RE = re.compile(r"^([A-Za-z0-9][A-Za-z0-9._-]*)\s*==\s*([^\s;#]+)")


def version_bumps(requirements_path):
    diff = subprocess.run(
        ["git", "diff", "-U0", "--", requirements_path],
        capture_output=True, text=True, check=True,
    ).stdout

    removed, added, order = {}, {}, []
    for line in diff.splitlines():
        if line.startswith("---") or line.startswith("+++"):
            continue
        if line.startswith("-"):
            m = SPEC_RE.match(line[1:].strip())
            if m:
                removed[m.group(1).lower()] = (m.group(1), m.group(2))
        elif line.startswith("+"):
            m = SPEC_RE.match(line[1:].strip())
            if m:
                key = m.group(1).lower()
                added[key] = (m.group(1), m.group(2))
                if key not in order:
                    order.append(key)

    rows = []
    for key in order:
        name, new_v = added[key]
        old_v = removed.get(key, (name, "?"))[1]
        rows.append((name, old_v, new_v))
    return rows


def main():
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    requirements_path, patch_log_path = sys.argv[1], sys.argv[2]

    print("### QScanner patch summary")
    print()
    print(f"Dependency versions bumped in `{requirements_path}`:")
    print()
    print("| Package | Old version | New version |")
    print("| --- | --- | --- |")
    rows = version_bumps(requirements_path)
    for name, old_v, new_v in rows:
        print(f"| {name} | {old_v} | {new_v} |")
    if not rows:
        print("| _(no version changes detected in the diff)_ | | |")

    print()
    print("<details><summary>qscanner patch log</summary>")
    print()
    print("```")
    try:
        with open(patch_log_path, encoding="utf-8", errors="replace") as f:
            for line in f:
                if re.search(r"PATCHED|SKIPPED|FAILED|UNSUPPORTED|Installed Version", line):
                    print(line.rstrip("\n"))
    except OSError as e:
        print(f"(could not read patch log: {e})")
    print("```")
    print("</details>")
    return 0


if __name__ == "__main__":
    sys.exit(main())
