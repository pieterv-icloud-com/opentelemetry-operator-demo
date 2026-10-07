#!/usr/bin/env python3
"""Report (and optionally apply) newer Helm chart versions for Argo CD Applications."""
import argparse
import re
import subprocess
import sys
from pathlib import Path

FIELD = re.compile(r"^(\s*-?\s*)(chart|repoURL|targetRevision):\s*(\S+)\s*$")


def parse_sources(text):
    """Yield dicts of chart/repoURL/targetRevision/line index for each Helm source."""
    lines = text.splitlines()
    block = {}

    def flush():
        if "chart" in block and "repoURL" in block and "targetRevision" in block:
            yield dict(block)

    prev_indent = None
    for i, line in enumerate(lines):
        m = FIELD.match(line)
        if not m:
            continue
        key, val = m.group(2), m.group(3).strip("'\"")
        indent = len(m.group(1).replace("-", " "))
        starts_new = m.group(1).strip() == "-" or key in block or indent != prev_indent
        if starts_new and block:
            yield from flush()
            block = {}
        prev_indent = indent
        block[key] = val
        if key == "targetRevision":
            block["line"] = i
    yield from flush()


def latest_version(repo, chart):
    out = subprocess.run(
        ["helm", "show", "chart", "--repo", repo, chart],
        capture_output=True, text=True, timeout=120,
    )
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip().splitlines()[-1] if out.stderr.strip() else "helm failed")
    m = re.search(r"^version:\s*['\"]?([^\s'\"]+)", out.stdout, re.M)
    if not m:
        raise RuntimeError("version not found in chart metadata")
    return m.group(1)


def major(v):
    m = re.match(r"v?(\d+)", v)
    return m.group(1) if m else v


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path", nargs="?", default="environments")
    ap.add_argument("--apply", action="store_true", help="rewrite targetRevision to latest")
    args = ap.parse_args()

    rows, errors = [], 0
    for f in sorted(Path(args.path).rglob("*.y*ml")):
        text = f.read_text()
        if not re.search(r"^kind:\s*Application\s*$", text, re.M):
            continue
        lines = text.splitlines(keepends=True)
        changed = False
        for s in parse_sources(text):
            try:
                latest = latest_version(s["repoURL"], s["chart"])
            except Exception as e:  # noqa: BLE001
                rows.append((s["chart"], s["targetRevision"], f"({e})", "ERROR", f))
                errors += 1
                continue
            cur = s["targetRevision"]
            if cur.lstrip("v") == latest.lstrip("v"):
                status = "OK"
            else:
                status = "UPDATE (MAJOR)" if major(cur) != major(latest) else "UPDATE"
                if args.apply:
                    prefix = "v" if cur.startswith("v") else ""
                    ln = lines[s["line"]]
                    lines[s["line"]] = ln.replace(cur, prefix + latest.lstrip("v"), 1)
                    changed = True
            rows.append((s["chart"], cur, latest, status, f))
        if changed:
            f.write_text("".join(lines))

    if not rows:
        print("No Helm-based Argo CD Applications found.")
        return 0
    hdr = ("CHART", "CURRENT", "LATEST", "STATUS", "FILE")
    widths = [max(len(str(r[i])) for r in rows + [hdr]) for i in range(5)]
    for r in [hdr] + rows:
        print("  ".join(str(c).ljust(w) for c, w in zip(r, widths)))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
