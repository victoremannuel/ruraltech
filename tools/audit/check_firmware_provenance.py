#!/usr/bin/env python3
"""
Checklist local de proveniencia de firmware para bancada.

Valida:
- header gerado com SHA/build UTC
- presenca de FW_PROVENANCE no boot da matriz e da coleira
- exposicao de campos de provenance em /status

Uso:
  python3 tools/audit/check_firmware_provenance.py
  python3 tools/audit/check_firmware_provenance.py --expected-sha <sha>
  python3 tools/audit/check_firmware_provenance.py --json
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from dataclasses import asdict, dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""


def git_head() -> str:
    result = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


def find_define(text: str, name: str) -> str | None:
    pattern = re.compile(rf"^\s*#define\s+{re.escape(name)}\s+(.+?)\s*$", re.MULTILINE)
    match = pattern.search(text)
    return match.group(1).strip() if match else None


def normalize(value: str | None) -> str:
    if value is None:
        return "ausente"
    return value.strip().strip('"')


def has_token(text: str, token: str) -> bool:
    return token in text


@dataclass
class CheckRow:
    item: str
    arquivo: str
    valor_encontrado: str
    valor_esperado: str
    status: str


def okfail(ok: bool) -> str:
    return "OK" if ok else "FALHA"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--expected-sha", default=None)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    expected_sha = args.expected_sha or git_head()

    generated = ROOT / "firmware" / "shared" / "generated_build_info.h"
    matrix_ino = ROOT / "gateway-matriz" / "gateway-matriz.ino"
    matrix_api = ROOT / "gateway-matriz" / "ApiServer.cpp"
    collar_ino = ROOT / "coleira" / "coleira.ino"

    generated_text = read_text(generated)
    matrix_text = read_text(matrix_ino)
    matrix_api_text = read_text(matrix_api)
    collar_text = read_text(collar_ino)

    git_sha = normalize(find_define(generated_text, "RT_BUILD_GIT_SHA"))
    git_short = normalize(find_define(generated_text, "RT_BUILD_GIT_SHORT_SHA"))
    build_utc = normalize(find_define(generated_text, "RT_BUILD_UTC"))

    rows = [
        CheckRow(
            "generated_build_info.h",
            "firmware/shared/generated_build_info.h",
            "presente" if generated.exists() else "ausente",
            "presente",
            okfail(generated.exists()),
        ),
        CheckRow(
            "RT_BUILD_GIT_SHA",
            "firmware/shared/generated_build_info.h",
            git_sha,
            expected_sha,
            okfail(git_sha == expected_sha),
        ),
        CheckRow(
            "RT_BUILD_GIT_SHORT_SHA",
            "firmware/shared/generated_build_info.h",
            git_short,
            expected_sha[:8],
            okfail(git_short == expected_sha[:8]),
        ),
        CheckRow(
            "RT_BUILD_UTC",
            "firmware/shared/generated_build_info.h",
            build_utc,
            "timestamp UTC",
            okfail(build_utc not in {"ausente", "unknown", ""}),
        ),
        CheckRow(
            "matrix FW_PROVENANCE",
            "gateway-matriz/gateway-matriz.ino",
            "presente" if has_token(matrix_text, "FW_PROVENANCE role=matrix") else "ausente",
            "presente",
            okfail(has_token(matrix_text, "FW_PROVENANCE role=matrix")),
        ),
        CheckRow(
            "collar FW_PROVENANCE",
            "coleira/coleira.ino",
            "presente" if has_token(collar_text, "FW_PROVENANCE role=collar") else "ausente",
            "presente",
            okfail(has_token(collar_text, "FW_PROVENANCE role=collar")),
        ),
        CheckRow(
            "matrix /status provenance",
            "gateway-matriz/ApiServer.cpp",
            "presente" if has_token(matrix_api_text, 'doc["gitSha"]') and has_token(matrix_api_text, 'doc["firmwareRole"]') else "ausente",
            "presente",
            okfail(has_token(matrix_api_text, 'doc["gitSha"]') and has_token(matrix_api_text, 'doc["firmwareRole"]')),
        ),
        CheckRow(
            "collar /status provenance",
            "coleira/coleira.ino",
            "presente" if has_token(collar_text, 'doc["gitSha"]') and has_token(collar_text, 'doc["firmwareRole"]') else "ausente",
            "presente",
            okfail(has_token(collar_text, 'doc["gitSha"]') and has_token(collar_text, 'doc["firmwareRole"]')),
        ),
    ]

    summary = {
        "expected_sha": expected_sha,
        "generated_git_sha": git_sha,
        "generated_git_short_sha": git_short,
        "ready": all(row.status == "OK" for row in rows),
        "rule": "se o SHA esperado nao aparecer no boot e no /status, a bancada e invalida",
    }

    if args.json:
      print(json.dumps({"rows": [asdict(row) for row in rows], "summary": summary}, ensure_ascii=False, indent=2))
      return 0

    for row in rows:
      print(f"[{row.status}] {row.item}: encontrado={row.valor_encontrado} esperado={row.valor_esperado} arquivo={row.arquivo}")
    print()
    print(f"expected_sha={summary['expected_sha']}")
    print(f"generated_git_sha={summary['generated_git_sha']}")
    print(f"ready={1 if summary['ready'] else 0}")
    print(summary["rule"])
    return 0 if summary["ready"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
