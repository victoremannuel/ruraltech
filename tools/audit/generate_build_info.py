#!/usr/bin/env python3
"""
Gera firmware/shared/generated_build_info.h com metadata de proveniencia do build.

Uso:
  python3 tools/audit/generate_build_info.py
"""

from __future__ import annotations

import subprocess
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "firmware" / "shared" / "generated_build_info.h"


def run_git(*args: str) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def git_dirty() -> bool:
    result = subprocess.run(
        ["git", "diff", "--quiet", "HEAD", "--"],
        cwd=ROOT,
    )
    return result.returncode != 0


def main() -> int:
    git_sha = run_git("rev-parse", "HEAD")
    git_short = run_git("rev-parse", "--short=8", "HEAD")
    build_utc = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    dirty = git_dirty()

    content = f"""#pragma once
#define RT_BUILD_GIT_SHA "{git_sha}"
#define RT_BUILD_GIT_SHORT_SHA "{git_short}"
#define RT_BUILD_UTC "{build_utc}"
#define RT_BUILD_DIRTY {1 if dirty else 0}
#define RT_BUILD_SOURCE "generated"
"""
    OUT.write_text(content, encoding="utf-8")
    print(f"Wrote {OUT.relative_to(ROOT)} git={git_short} dirty={1 if dirty else 0} utc={build_utc}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
