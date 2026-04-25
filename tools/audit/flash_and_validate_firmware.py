#!/usr/bin/env python3
"""
Build, flash and validate RuralTech firmware provenance for matrix and collar.

Usage:
  python3 tools/audit/flash_and_validate_firmware.py
  python3 tools/audit/flash_and_validate_firmware.py --allow-dirty --skip-upload --skip-serial
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_TARGET_COMMIT = "8f12088ed3184941220170ec7732a870641327d2"
DEFAULT_STALE_SHA = "891dd586bcc53a54143968d4b182f6f91bed48d0"
DEFAULT_FQBN = "esp32:esp32:esp32:PartitionScheme=min_spiffs"
DEFAULT_MATRIX_PORT = "/dev/tty.usbserial-59470049741"
DEFAULT_COLLAR_PORT = "/dev/tty.usbserial-1420"
DEFAULT_MATRIX_BUILD = Path("/tmp/ruraltech-build-matriz")
DEFAULT_COLLAR_BUILD = Path("/tmp/ruraltech-build-coleira")
SOURCE_MARKER_PATHS = ["gateway-matriz", "firmware/shared", "firmware/tests"]
REQUIRED_SOURCE_MARKERS = [
    "RPV2_PLAN_ENTER",
    "RPV2_PLANNER_REV",
    "progressive_reduce_real_path_v1",
    "RPV2_PLAN_CANDIDATE_EVAL",
    "RPV2_PLAN_CHUNK_FIT",
    "RPV2_PLAN_FINAL",
    "RPV2_PLAN_FAILED_TERMINAL",
    "radio_proto_v2_planner_support",
    "measurementOk",
    "fitsLimit",
]
REQUIRED_MATRIX_BINARY_MARKERS = [
    "RPV2_PLAN_ENTER",
    "RPV2_PLANNER_REV",
    "progressive_reduce_real_path_v1",
    "RPV2_PLAN_CANDIDATE_EVAL",
    "RPV2_PLAN_CHUNK_FIT",
    "RPV2_PLAN_FINAL",
    "FW_PROVENANCE role=matrix",
]
ALLOWED_DIRTY_SUFFIXES = (
    "manual_settings.local.h",
    "manual_settings.local.example.h",
    "firmware/shared/generated_build_info.h",
)
PROVENANCE_RE = re.compile(
    r"FW_PROVENANCE role=(?P<role>\w+) gitSha=(?P<git_sha>\S+) gitShort=(?P<git_short>\S+) "
    r"dirty=(?P<dirty>\S+) buildUtc=(?P<build_utc>\S+) buildSource=(?P<build_source>\S+)"
)


class ValidationError(RuntimeError):
    pass


@dataclass
class CommandResult:
    command: list[str]
    returncode: int | None
    timed_out: bool
    log_path: Path


@dataclass
class StageResult:
    status: str
    details: str = ""


@dataclass
class ProvenanceObservation:
    status: str
    role: str
    git_sha: str = ""
    git_short: str = ""
    build_utc: str = ""
    dirty: str = ""
    line: str = ""


@dataclass
class RuntimeStageResult:
    status: str
    provenance_present: bool = False
    target_sha_match: bool = False
    target_short_match: bool = False
    stale_sha_absent: bool = False
    details: str = ""
    observation: ProvenanceObservation | None = None


def which_search_tool() -> list[str]:
    if shutil.which("rg"):
        return ["rg", "-n", "-F"]
    return ["grep", "-R", "-n"]


def now_utc() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def ensure_text(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")


def append_text(path: Path, content: str) -> None:
    with path.open("a", encoding="utf-8") as fh:
        fh.write(content)


def run_capture(
    command: list[str],
    log_path: Path,
    *,
    timeout: int | None = None,
    cwd: Path = ROOT,
    env: dict[str, str] | None = None,
) -> CommandResult:
    started = now_utc()
    with log_path.open("w", encoding="utf-8") as log:
        log.write(f"$ {' '.join(command)}\n")
        log.write(f"started_at={started}\n")
        log.flush()
        process = subprocess.Popen(
            command,
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            env=env,
        )
        timed_out = False
        try:
            stdout, _ = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            process.kill()
            stdout, _ = process.communicate()
        if stdout:
            log.write(stdout)
        log.write(f"\nexit_code={process.returncode}\n")
        log.write(f"timed_out={1 if timed_out else 0}\n")
        log.write(f"finished_at={now_utc()}\n")
    return CommandResult(command=command, returncode=process.returncode, timed_out=timed_out, log_path=log_path)


def run_text(command: list[str], *, cwd: Path = ROOT) -> str:
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, check=True)
    return result.stdout.strip()


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""


def short7(value: str) -> str:
    return value[:7]


def git_status_lines() -> list[str]:
    out = run_text(["git", "status", "--short"])
    return [line for line in out.splitlines() if line.strip()]


def is_allowed_dirty(line: str) -> bool:
    if len(line) < 4:
      return False
    path = line[3:].strip()
    return path.endswith(ALLOWED_DIRTY_SUFFIXES)


def validate_workspace(target_commit: str, out_dir: Path) -> tuple[str, str, list[str]]:
    status_lines = git_status_lines()
    head = run_text(["git", "rev-parse", "HEAD"])
    short_head = short7(head)
    branch = run_text(["git", "branch", "--show-current"])
    log10 = run_text(["git", "log", "--oneline", "-10"])
    ensure_text(out_dir / "branch.txt", f"{branch}\n")
    ensure_text(out_dir / "git_log_oneline_10.txt", f"{log10}\n")
    ensure_text(out_dir / "git_status.txt", ("\n".join(status_lines) + "\n") if status_lines else "")
    ensure_text(out_dir / "head.txt", f"{head}\n")
    ensure_text(out_dir / "head_short.txt", f"{short_head}\n")
    if head != target_commit:
        raise ValidationError(f"HEAD {head} difere do commit alvo {target_commit}")
    return head, short_head, status_lines


def validate_source_markers(out_dir: Path) -> StageResult:
    search_tool = which_search_tool()
    lines: list[str] = []
    missing: list[str] = []
    base_paths = SOURCE_MARKER_PATHS.copy()
    for marker in REQUIRED_SOURCE_MARKERS:
        command = search_tool + [marker] + base_paths
        result = subprocess.run(
            command,
            cwd=ROOT,
            capture_output=True,
            text=True,
            errors="replace",
            check=False,
        )
        lines.append(f"$ {' '.join(command)}")
        stdout = result.stdout.strip()
        stderr = result.stderr.strip()
        if stdout:
            lines.append(stdout)
        if stderr:
            lines.append(stderr)
        if result.returncode not in (0, 1):
            lines.append(f"exit_code={result.returncode}")
        if not stdout:
            missing.append(marker)
    ensure_text(out_dir / "source_marker_search.txt", ("\n".join(lines) + "\n") if lines else "")
    if missing:
        return StageResult("FAIL", "markers ausentes: " + ", ".join(missing))
    return StageResult("PASS", "todos os markers obrigatorios encontrados no source")


def snapshot_generated_header(out_dir: Path) -> None:
    generated = ROOT / "firmware" / "shared" / "generated_build_info.h"
    if generated.exists():
        shutil.copyfile(generated, out_dir / "generated_build_info_snapshot.h")


def validate_generated_header(target_commit: str, stale_sha: str, out_dir: Path) -> StageResult:
    generated = ROOT / "firmware" / "shared" / "generated_build_info.h"
    text = read_text(generated)
    target_short = short7(target_commit)
    snapshot_generated_header(out_dir)
    if target_commit not in text:
        return StageResult("FAIL", "generated_build_info.h nao contem o SHA alvo completo")
    if target_short not in text:
        return StageResult("FAIL", "generated_build_info.h nao contem o short SHA alvo")
    if stale_sha in text:
        return StageResult("FAIL", f"generated_build_info.h ainda contem SHA stale {stale_sha}")
    return StageResult("PASS", f"SHA alvo presente ({target_short})")


def generated_header_flags(out_dir: Path, target_commit: str, stale_sha: str) -> tuple[bool, bool, bool]:
    snapshot = out_dir / "generated_build_info_snapshot.h"
    text = read_text(snapshot if snapshot.exists() else ROOT / "firmware" / "shared" / "generated_build_info.h")
    target_short = short7(target_commit)
    return (target_commit in text, target_short in text, stale_sha in text)


def find_generated_header_locations(out_dir: Path) -> StageResult:
    ignored_parts = {"graphify-out", ".git", ".venv", "__pycache__", "tools/audit/output"}
    locations: list[Path] = []
    for path in ROOT.rglob("generated_build_info.h"):
        rel = path.relative_to(ROOT)
        rel_str = rel.as_posix()
        if any(part in ignored_parts for part in rel.parts):
            continue
        if "/build/" in rel_str:
            continue
        locations.append(path)
    locations = sorted(locations)
    ensure_text(
        out_dir / "generated_build_info_locations.txt",
        ("\n".join(path.relative_to(ROOT).as_posix() for path in locations) + "\n") if locations else "",
    )
    expected = ROOT / "firmware" / "shared" / "generated_build_info.h"
    if not locations:
        return StageResult("FAIL", "nenhum generated_build_info.h encontrado")
    if expected not in locations:
        return StageResult("FAIL", "header primario firmware/shared/generated_build_info.h nao encontrado")
    unexpected = [path.relative_to(ROOT).as_posix() for path in locations if path != expected]
    if unexpected:
        return StageResult("PASS", "copias adicionais encontradas: " + ", ".join(unexpected))
    return StageResult("PASS", "somente o header primario foi encontrado")


def validate_include_chain() -> StageResult:
    build_info = read_text(ROOT / "firmware" / "shared" / "build_info.h")
    matrix_ino = read_text(ROOT / "gateway-matriz" / "gateway-matriz.ino")
    matrix_api = read_text(ROOT / "gateway-matriz" / "ApiServer.cpp")
    collar_ino = read_text(ROOT / "coleira" / "coleira.ino")

    checks = [
        ('build_info inclui generated_build_info.h', '#include "generated_build_info.h"' in build_info),
        ('build_info usa fallback apenas com #ifndef', build_info.count("#ifndef RT_BUILD_GIT_SHA") >= 1),
        ('matriz inclui build_info.h', '../firmware/shared/build_info.h' in matrix_ino),
        ('coleira inclui build_info.h', '../firmware/shared/build_info.h' in collar_ino),
        ('matriz usa buildinfo::current()', 'buildinfo::current()' in matrix_ino and 'buildinfo::current()' in matrix_api),
        ('coleira usa buildinfo::current()', 'buildinfo::current()' in collar_ino),
    ]
    missing = [label for label, ok in checks if not ok]
    if missing:
        return StageResult("FAIL", "; ".join(missing))
    return StageResult("PASS", "include chain build_info -> generated_build_info validado em matriz e coleira")


def run_host_tests(out_dir: Path) -> tuple[StageResult, list[str]]:
    tests = [
        "firmware/tests/rpv2_fence_planner_test.cpp",
        "firmware/tests/rtrv1_stale_wake_hint_test.cpp",
        "firmware/tests/rtrv1_wake_scheduler_test.cpp",
        "firmware/tests/rtrv1_fast_path_priority_test.cpp",
        "firmware/tests/rtrv1_terminal_failure_status_test.cpp",
    ]
    log_path = out_dir / "host_tests.log"
    results: list[str] = []
    commands: list[str] = []
    with log_path.open("w", encoding="utf-8") as log:
        for test in tests:
            exe = f"/tmp/{Path(test).stem}"
            compile_cmd = ["c++", "-std=c++17", "-I.", "-Ifirmware/tests/arduino_compat", test, "-o", exe]
            run_cmd = [exe]
            commands.append(" ".join(compile_cmd))
            log.write(f"$ {' '.join(compile_cmd)}\n")
            compile_proc = subprocess.run(compile_cmd, cwd=ROOT, capture_output=True, text=True)
            log.write(compile_proc.stdout)
            log.write(compile_proc.stderr)
            if compile_proc.returncode != 0:
                return StageResult("FAIL", f"falha ao compilar {Path(test).name}"), commands
            commands.append(" ".join(run_cmd))
            log.write(f"$ {' '.join(run_cmd)}\n")
            run_proc = subprocess.run(run_cmd, cwd=ROOT, capture_output=True, text=True)
            log.write(run_proc.stdout)
            log.write(run_proc.stderr)
            if run_proc.returncode != 0:
                return StageResult("FAIL", f"falha ao executar {Path(test).name}"), commands
            results.append(Path(test).name)
    return StageResult("PASS", ", ".join(results)), commands


def validate_provenance_instrumentation() -> StageResult:
    matrix_ino = read_text(ROOT / "gateway-matriz" / "gateway-matriz.ino")
    matrix_api = read_text(ROOT / "gateway-matriz" / "ApiServer.cpp")
    collar_ino = read_text(ROOT / "coleira" / "coleira.ino")
    checks = [
        ("FW_PROVENANCE role=matrix", "gateway-matriz.ino", "FW_PROVENANCE role=matrix" in matrix_ino),
        ("FW_PROVENANCE role=collar", "coleira.ino", "FW_PROVENANCE role=collar" in collar_ino),
        ('doc["gitSha"] + doc["firmwareRole"]', "gateway-matriz/ApiServer.cpp", 'doc["gitSha"]' in matrix_api and 'doc["firmwareRole"]' in matrix_api),
        ('doc["gitSha"] + doc["firmwareRole"]', "coleira/coleira.ino", 'doc["gitSha"]' in collar_ino and 'doc["firmwareRole"]' in collar_ino),
    ]
    missing = [f"{label} em {file_name}" for label, file_name, ok in checks if not ok]
    if missing:
        return StageResult("FAIL", "; ".join(missing))
    return StageResult("PASS", "logs e /status de proveniencia presentes em matriz e coleira")


def clean_build_paths(matrix_build: Path, collar_build: Path, out_dir: Path) -> None:
    shutil.rmtree(matrix_build, ignore_errors=True)
    shutil.rmtree(collar_build, ignore_errors=True)
    run_capture(["arduino-cli", "cache", "clean"], out_dir / "arduino_cache_clean.log", timeout=120)


def build_files_listing(build_path: Path, out_path: Path) -> list[str]:
    files = sorted(str(path) for path in build_path.rglob("*") if path.is_file())
    ensure_text(out_path, ("\n".join(files) + "\n") if files else "")
    return files


def has_firmware_artifacts(build_path: Path) -> bool:
    bin_files = list(build_path.rglob("*.bin"))
    elf_files = list(build_path.rglob("*.elf"))
    return bool(bin_files and elf_files)


def validate_binary_strings(build_path: Path, target_commit: str, stale_sha: str, out_path: Path) -> StageResult:
    bin_files = sorted(build_path.rglob("*.bin"))
    if not bin_files:
        ensure_text(out_path, "")
        return StageResult("SKIPPED", f"nenhum .bin encontrado em {build_path}")
    if shutil.which("strings") is None:
        ensure_text(out_path, "")
        return StageResult("SKIPPED", "comando strings indisponivel neste host")

    target_short = short7(target_commit)
    lines: list[str] = []
    saw_target_full = False
    saw_target_short = False
    saw_stale = False
    for bin_path in bin_files:
        result = subprocess.run(
            ["strings", str(bin_path)],
            cwd=ROOT,
            capture_output=True,
            text=True,
            errors="replace",
            check=False,
        )
        lines.append(f"$ strings {bin_path}")
        for line in result.stdout.splitlines():
            if target_commit in line or target_short in line or stale_sha in line:
                lines.append(line)
            if target_commit in line:
                saw_target_full = True
            if target_short in line:
                saw_target_short = True
            if stale_sha in line:
                saw_stale = True
        lines.append(f"exit_code={result.returncode}")
    ensure_text(out_path, ("\n".join(lines) + "\n") if lines else "")

    if saw_stale:
        return StageResult("FAIL", f"binario em {build_path} contem SHA stale {stale_sha}")
    if saw_target_full and saw_target_short:
        return StageResult("PASS", f"binario em {build_path} contem SHA alvo completo e curto")
    if saw_target_full or saw_target_short:
        return StageResult("PASS", f"binario em {build_path} contem evidencia parcial do SHA alvo")
    return StageResult("SKIPPED", f"strings nao encontrou SHA alvo em {build_path}; validacao fica a cargo do serial")


def validate_matrix_binary_markers(build_path: Path, out_path: Path) -> StageResult:
    bin_files = sorted(build_path.rglob("*.bin"))
    if not bin_files:
        ensure_text(out_path, "")
        return StageResult("SKIPPED", f"nenhum .bin encontrado em {build_path}")
    if shutil.which("strings") is None:
        ensure_text(out_path, "")
        return StageResult("SKIPPED", "comando strings indisponivel neste host")

    found = {marker: False for marker in REQUIRED_MATRIX_BINARY_MARKERS}
    lines: list[str] = []
    for bin_path in bin_files:
        result = subprocess.run(
            ["strings", str(bin_path)],
            cwd=ROOT,
            capture_output=True,
            text=True,
            errors="replace",
            check=False,
        )
        payload = result.stdout.splitlines()
        lines.append(f"$ strings {bin_path}")
        for marker in REQUIRED_MATRIX_BINARY_MARKERS:
            for line in payload:
                if marker in line:
                    lines.append(line)
                    found[marker] = True
                    break
        lines.append(f"exit_code={result.returncode}")
    ensure_text(out_path, ("\n".join(lines) + "\n") if lines else "")
    missing = [marker for marker, ok in found.items() if not ok]
    if missing:
        return StageResult("FAIL", "markers ausentes no binario: " + ", ".join(missing))
    return StageResult("PASS", "todos os markers obrigatorios encontrados no binario da matriz")


def compile_target(
    sketch: str,
    fqbn: str,
    build_path: Path,
    log_path: Path,
    build_files_path: Path,
) -> StageResult:
    command = ["arduino-cli", "compile", "--fqbn", fqbn, "--build-path", str(build_path), sketch]
    result = run_capture(command, log_path, timeout=420)
    files = build_files_listing(build_path, build_files_path)
    if has_firmware_artifacts(build_path):
        if result.returncode == 0:
            return StageResult("PASS", f"artefatos em {build_path}")
        if result.timed_out:
            return StageResult("PASS", f"artefatos em {build_path} apesar de timeout do arduino-cli")
    if not files:
        return StageResult("FAIL", f"nenhum artefato em {build_path}")
    return StageResult("FAIL", f"build invalido em {build_path}")


def upload_target(
    sketch: str,
    fqbn: str,
    port: str,
    build_path: Path,
    log_path: Path,
) -> StageResult:
    if not has_firmware_artifacts(build_path):
        return StageResult("FAIL", f"sem artefatos validos em {build_path}")
    command = [
        "arduino-cli",
        "upload",
        "-p",
        port,
        "--fqbn",
        fqbn,
        "--input-dir",
        str(build_path),
        sketch,
    ]
    result = run_capture(command, log_path, timeout=240)
    if result.returncode == 0:
        return StageResult("PASS", f"upload concluido via {port}")
    return StageResult("FAIL", f"upload falhou via {port}")


def capture_serial_log(port: str, baud: int, duration: int, out_path: Path) -> None:
    try:
        import serial
    except ImportError as exc:
        raise ValidationError("pyserial nao esta instalado; instale com pip install pyserial") from exc

    started = time.monotonic()
    with serial.Serial(port, baud, timeout=1) as ser, out_path.open("w", encoding="utf-8") as out:
        out.write(f"# port={port} baud={baud} duration={duration}s started_at={now_utc()}\n")
        while time.monotonic() - started < duration:
            raw = ser.readline()
            if not raw:
                continue
            line = raw.decode("utf-8", errors="replace").rstrip()
            out.write(line + "\n")
            out.flush()
        out.write(f"# finished_at={now_utc()}\n")


def parse_provenance(log_path: Path, expected_role: str, target_commit: str, stale_sha: str) -> ProvenanceObservation:
    text = read_text(log_path)
    target_short = short7(target_commit)
    if stale_sha in text:
        return ProvenanceObservation(status="FAIL", role=expected_role, line=f"SHA stale {stale_sha} encontrado")
    for line in text.splitlines():
        match = PROVENANCE_RE.search(line)
        if not match:
            continue
        role = match.group("role")
        if role != expected_role:
            continue
        git_sha = match.group("git_sha")
        git_short = match.group("git_short")
        if git_sha == target_commit and git_short == target_short:
            return ProvenanceObservation(
                status="PASS",
                role=role,
                git_sha=git_sha,
                git_short=git_short,
                build_utc=match.group("build_utc"),
                dirty=match.group("dirty"),
                line=line,
            )
        return ProvenanceObservation(
            status="FAIL",
            role=role,
            git_sha=git_sha,
            git_short=git_short,
            build_utc=match.group("build_utc"),
            dirty=match.group("dirty"),
            line=line,
        )
    return ProvenanceObservation(status="FAIL", role=expected_role, line="FW_PROVENANCE nao encontrado")


def summarize_runtime(observation: ProvenanceObservation, target_commit: str, stale_sha: str) -> RuntimeStageResult:
    if observation.status == "SKIPPED":
        return RuntimeStageResult(status="SKIPPED", details=observation.line, observation=observation)
    if observation.status == "NOT_RUN":
        return RuntimeStageResult(status="SKIPPED", details=observation.line, observation=observation)

    target_short = short7(target_commit)
    line = observation.line or ""
    provenance_present = "FW_PROVENANCE" in line
    target_sha_match = observation.git_sha == target_commit
    target_short_match = observation.git_short == target_short
    stale_sha_absent = stale_sha not in line and stale_sha != observation.git_sha
    status = "PASS" if all((provenance_present, target_sha_match, target_short_match, stale_sha_absent)) else "FAIL"
    details = observation.line or "sem linha observada"
    return RuntimeStageResult(
        status=status,
        provenance_present=provenance_present,
        target_sha_match=target_sha_match,
        target_short_match=target_short_match,
        stale_sha_absent=stale_sha_absent,
        details=details,
        observation=observation,
    )


def validate_matrix_boot_markers(log_path: Path, out_path: Path) -> StageResult:
    text = read_text(log_path)
    markers = {
        "FW_PROVENANCE role=matrix": "FW_PROVENANCE role=matrix" in text,
        "RPV2_PLANNER_REV rev=progressive_reduce_real_path_v1":
            "RPV2_PLANNER_REV rev=progressive_reduce_real_path_v1" in text,
        "DIAG_STAGE=4":
            "Matrix diag_stage=4" in text or "diagStage=4" in text or "DIAG_STAGE=4" in text,
        "QUEUE_POLLING_CFG":
            "QUEUE_POLLING_CFG" in text,
        "CLOUD_BACKHAUL_CFG":
            "CLOUD_BACKHAUL_CFG" in text,
    }
    lines = [f"{name}: {'PASS' if ok else 'FAIL'}" for name, ok in markers.items()]
    ensure_text(out_path, "\n".join(lines) + "\n")
    missing = [name for name, ok in markers.items() if not ok]
    if missing:
        return StageResult("FAIL", "boot markers ausentes: " + ", ".join(missing))
    return StageResult("PASS", "boot serial contem proveniencia, revisao do planner e configuracao cloud")


def fetch_status_json(url: str, out_path: Path) -> dict | None:
    try:
        with urllib.request.urlopen(url, timeout=10) as response:
            payload = response.read().decode("utf-8", errors="replace")
    except (urllib.error.URLError, TimeoutError):
        return None
    out_path.write_text(payload, encoding="utf-8")
    try:
        return json.loads(payload)
    except json.JSONDecodeError:
        return None


def validate_status_payload(payload: dict | None, target_commit: str, stale_sha: str) -> StageResult:
    if payload is None:
        return StageResult("SKIPPED", "status indisponivel")
    required = ["firmwareRole", "firmwareVersion", "gitSha", "gitShortSha", "buildUtc", "buildDirty", "buildSource"]
    missing = [key for key in required if key not in payload]
    if missing:
        return StageResult("FAIL", f"faltando campos: {', '.join(missing)}")
    if payload["gitSha"] == stale_sha:
        return StageResult("FAIL", f"status ainda expoe SHA stale {stale_sha}")
    if payload["gitSha"] != target_commit and payload["gitShortSha"] != short7(target_commit):
        return StageResult("FAIL", f"status expoe SHA divergente {payload['gitSha']}")
    return StageResult("PASS", f"status com SHA {payload['gitShortSha']}")


def capture_serial_pair(
    matrix_port: str,
    collar_port: str,
    baud: int,
    duration: int,
    matrix_log: Path,
    collar_log: Path,
) -> None:
    errors: list[Exception] = []

    def worker(port: str, out_path: Path) -> None:
        try:
            capture_serial_log(port, baud, duration, out_path)
        except Exception as exc:  # noqa: BLE001
            errors.append(exc)

    threads = [
        threading.Thread(target=worker, args=(matrix_port, matrix_log), daemon=True),
        threading.Thread(target=worker, args=(collar_port, collar_log), daemon=True),
    ]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    if errors:
        raise ValidationError(str(errors[0]))


def validate_bench_logs(matrix_log: Path, collar_log: Path) -> StageResult:
    matrix_text = read_text(matrix_log)
    collar_text = read_text(collar_log)
    planner_enter = "RPV2_PLAN_ENTER" in matrix_text
    planner_eval = "RPV2_PLAN_CANDIDATE_EVAL" in matrix_text
    chunk_reject = "RPV2_PLAN_CHUNK_REJECT" in matrix_text
    chunk_fit = "RPV2_PLAN_CHUNK_FIT" in matrix_text
    plan_final_success = "RPV2_PLAN_FINAL" in matrix_text and "planReady=1" in matrix_text
    plan_final_failure = "RPV2_PLAN_FINAL" in matrix_text and "planReady=0" in matrix_text
    simple_cleared = "SIMPLE_COMMAND_CLEARED" in matrix_text
    has_stale = "RTR_WAKE_HINT_STALE" in matrix_text
    has_waiting = "RTR_WAITING_FRESH_UPLINK" in matrix_text
    repeated_stale_only = has_stale and not has_waiting
    fresh_release = all(token in matrix_text for token in ("RTR_FRESH_UPLINK_RECEIVED", "RTR_WAKE_HINT_FROM_UPLINK", "RTR_PAGE_TX_OK"))
    collar_page = all(token in collar_text for token in ("RTR_RAW_DOWNLINK_SEEN", "RTR_RAW_DOWNLINK_ACCEPT", "RTR_PAGE_RX", "RTR_PAGE_ACK_TX"))
    deadlock_after_reject = (
        chunk_reject
        and "QUEUE_POLL_SKIPPED reason=simple_command_active" in matrix_text
        and not chunk_fit
        and not plan_final_success
        and not plan_final_failure
        and not simple_cleared
    )
    if not planner_enter or not planner_eval:
        return StageResult("FAIL", "bench sem markers obrigatorios RPV2_PLAN_ENTER/RPV2_PLAN_CANDIDATE_EVAL")
    if deadlock_after_reject:
        return StageResult("FAIL", "planner rejeitou candidato e entrou em simple_command_active sem plan final")
    if chunk_reject and (chunk_fit or plan_final_failure or simple_cleared):
        if chunk_fit and plan_final_success and "RTR_WAKE_SESSION_CREATED" in matrix_text:
            return StageResult("PASS", "planner reduziu oversize, fechou planReady=1 e criou wake session")
        if plan_final_failure and simple_cleared:
            return StageResult("PASS", "planner encerrou em falha terminal e limpou simple command")
        return StageResult("PASS", "bench contem markers de progressao do planner apos reject")
    if repeated_stale_only:
        return StageResult("FAIL", "stale loop sem RTR_WAITING_FRESH_UPLINK")
    if has_stale and has_waiting:
        return StageResult("PASS", "stale hint seguido de waiting fresh uplink")
    if fresh_release:
        return StageResult("PASS", "fresh uplink liberou page")
    if collar_page:
        return StageResult("PASS", "coleira recebeu RTR_PAGE")
    return StageResult("SKIPPED", "bench sem evidencia suficiente")


def run_bench_command(
    bench_command: str,
    matrix_port: str,
    collar_port: str,
    baud: int,
    duration: int,
    out_dir: Path,
) -> StageResult:
    matrix_log = out_dir / "bench_set_fence_matrix.log"
    collar_log = out_dir / "bench_set_fence_collar.log"

    errors: list[Exception] = []

    def worker(port: str, out_path: Path) -> None:
        try:
            capture_serial_log(port, baud, duration, out_path)
        except Exception as exc:  # noqa: BLE001
            errors.append(exc)

    threads = [
        threading.Thread(target=worker, args=(matrix_port, matrix_log), daemon=True),
        threading.Thread(target=worker, args=(collar_port, collar_log), daemon=True),
    ]
    for thread in threads:
        thread.start()
    bench_log = out_dir / "bench_command.log"
    result = run_capture(["/bin/zsh", "-lc", bench_command], bench_log, timeout=duration + 30)
    for thread in threads:
        thread.join()
    if errors:
        return StageResult("FAIL", f"captura bench falhou: {errors[0]}")
    if result.returncode not in (0, None):
        return StageResult("FAIL", f"bench command falhou: {bench_command}")
    return validate_bench_logs(matrix_log, collar_log)


def build_report(
    out_dir: Path,
    target_commit: str,
    stale_sha: str,
    head: str,
    short_head: str,
    dirty_files: list[str],
    source_markers: StageResult,
    generated_headers: StageResult,
    build_info: StageResult,
    include_chain: StageResult,
    host_tests: StageResult,
    matrix_compile: StageResult,
    collar_compile: StageResult,
    matrix_binary: StageResult,
    matrix_binary_markers: StageResult,
    collar_binary: StageResult,
    matrix_upload: StageResult,
    collar_upload: StageResult,
    matrix_runtime: RuntimeStageResult,
    matrix_boot_markers: StageResult,
    collar_runtime: RuntimeStageResult,
    matrix_status: StageResult,
    collar_status: StageResult,
    bench_result: StageResult,
    final_result: str,
    blocking_issues: list[str],
    commands: Iterable[str],
) -> None:
    header_has_full_sha, header_has_short_sha, header_has_stale_sha = generated_header_flags(
        out_dir,
        target_commit,
        stale_sha,
    )
    report = [
        "# RuralTech Matrix Planner Runtime Marker Validation Report",
        "",
        "## Target Commit",
        target_commit,
        "",
        "## Repository State",
        f"- HEAD: {head or '-'}",
        f"- Short HEAD: {short_head or '-'}",
        "- Dirty files:",
    ]
    if dirty_files:
        report.extend(dirty_files)
    else:
        report.append("- none")
    report.extend(
        [
            "",
            "## Source Marker Audit",
            f"- Source markers: {source_markers.status} ({source_markers.details or '-'})",
            "",
            "## Generated Build Info",
            f"- Header locations audit: {generated_headers.status} ({generated_headers.details or '-'})",
            f"- Contains target full SHA: {'PASS' if header_has_full_sha else 'FAIL'}",
            f"- Contains target short SHA: {'PASS' if header_has_short_sha else 'FAIL'}",
            f"- Contains stale SHA: {'FAIL' if header_has_stale_sha else 'PASS'}",
            f"- Validation summary: {build_info.status} ({build_info.details or '-'})",
            "",
            "## Include Chain",
            f"- build_info.h includes generated metadata: {include_chain.status}",
            f"- collar uses build_info: {'PASS' if include_chain.status == 'PASS' else 'FAIL'}",
            f"- matrix uses build_info: {'PASS' if include_chain.status == 'PASS' else 'FAIL'}",
            "",
            "## Matrix Runtime Provenance",
            f"- FW_PROVENANCE role=matrix present: {'PASS' if matrix_runtime.provenance_present else matrix_runtime.status}",
            f"- gitSha target: {'PASS' if matrix_runtime.target_sha_match else matrix_runtime.status}",
            f"- gitShort target: {'PASS' if matrix_runtime.target_short_match else matrix_runtime.status}",
            f"- stale SHA absent: {'PASS' if matrix_runtime.stale_sha_absent else matrix_runtime.status}",
            f"- boot markers: {matrix_boot_markers.status} ({matrix_boot_markers.details or '-'})",
            f"- detail: {matrix_runtime.details or '-'}",
            "",
            "## Collar Runtime Provenance",
            f"- FW_PROVENANCE role=collar present: {'PASS' if collar_runtime.provenance_present else collar_runtime.status}",
            f"- gitSha target: {'PASS' if collar_runtime.target_sha_match else collar_runtime.status}",
            f"- gitShort target: {'PASS' if collar_runtime.target_short_match else collar_runtime.status}",
            f"- stale SHA absent: {'PASS' if collar_runtime.stale_sha_absent else collar_runtime.status}",
            f"- detail: {collar_runtime.details or '-'}",
            "",
            "## Compile and Upload",
            f"- matrix compile: {matrix_compile.status} ({matrix_compile.details or '-'})",
            f"- collar compile: {collar_compile.status} ({collar_compile.details or '-'})",
            f"- matrix binary SHA: {matrix_binary.status} ({matrix_binary.details or '-'})",
            f"- matrix binary markers: {matrix_binary_markers.status} ({matrix_binary_markers.details or '-'})",
            f"- collar binary SHA: {collar_binary.status} ({collar_binary.details or '-'})",
            f"- matrix upload: {matrix_upload.status} ({matrix_upload.details or '-'})",
            f"- collar upload: {collar_upload.status} ({collar_upload.details or '-'})",
            "",
            "## Optional /status Validation",
            f"- matrix /status: {matrix_status.status} ({matrix_status.details or '-'})",
            f"- collar /status: {collar_status.status} ({collar_status.details or '-'})",
            "",
            "## Optional SET_FENCE Smoke",
            f"- {bench_result.status.lower()}",
            f"- observed key logs: {bench_result.details or '-'}",
            "",
            "## Host Tests",
            f"- {host_tests.status} ({host_tests.details or '-'})",
            "",
            "## Final Result",
            final_result,
            "",
            "## Blocking Issues",
        ]
    )
    if blocking_issues:
        report.extend(f"- {issue}" for issue in blocking_issues)
    else:
        report.append("- none")
    report.extend(
        [
            "",
            "## Commands executed",
        ]
    )
    report.extend(f"- {command}" for command in commands)
    ensure_text(out_dir / "validation_report.md", "\n".join(report) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target-commit", default=DEFAULT_TARGET_COMMIT)
    parser.add_argument("--stale-sha", default=DEFAULT_STALE_SHA)
    parser.add_argument("--matrix-port", default=DEFAULT_MATRIX_PORT)
    parser.add_argument("--collar-port", default=DEFAULT_COLLAR_PORT)
    parser.add_argument("--fqbn", default=DEFAULT_FQBN)
    parser.add_argument("--matrix-build-path", default=str(DEFAULT_MATRIX_BUILD))
    parser.add_argument("--collar-build-path", default=str(DEFAULT_COLLAR_BUILD))
    parser.add_argument("--matrix-status-url", default="")
    parser.add_argument("--collar-status-url", default="")
    parser.add_argument("--serial-baud", type=int, default=115200)
    parser.add_argument("--serial-duration", type=int, default=90)
    parser.add_argument("--bench-duration", type=int, default=120)
    parser.add_argument("--bench-command", default="")
    parser.add_argument("--output-dir", default="")
    parser.add_argument("--allow-dirty", action="store_true")
    parser.add_argument("--skip-compile", action="store_true")
    parser.add_argument("--skip-upload", action="store_true")
    parser.add_argument("--skip-serial", action="store_true")
    parser.add_argument("--skip-status", action="store_true")
    parser.add_argument("--skip-bench", action="store_true")
    args = parser.parse_args()

    run_id = datetime.now().strftime("%Y%m%d_%H%M%S") + "_matrix_planner_runtime_marker_validation"
    out_dir = Path(args.output_dir) if args.output_dir else ROOT / "tools" / "audit" / "output" / run_id
    out_dir.mkdir(parents=True, exist_ok=True)

    commands_executed: list[str] = []
    blocking_issues: list[str] = []
    matrix_build_path = Path(args.matrix_build_path)
    collar_build_path = Path(args.collar_build_path)
    head = ""
    short_head = ""
    dirty_files: list[str] = []
    source_markers_result = StageResult("SKIPPED", "nao executado")
    generated_headers_result = StageResult("SKIPPED", "nao executado")
    build_info_result = StageResult("SKIPPED", "nao executado")
    include_chain_result = StageResult("SKIPPED", "nao executado")
    host_tests_result = StageResult("SKIPPED", "nao executado")
    matrix_compile = StageResult("SKIPPED", "compile pulado")
    collar_compile = StageResult("SKIPPED", "compile pulado")
    matrix_binary = StageResult("SKIPPED", "binario nao inspecionado")
    matrix_binary_markers = StageResult("SKIPPED", "binario nao inspecionado")
    collar_binary = StageResult("SKIPPED", "binario nao inspecionado")
    matrix_upload = StageResult("SKIPPED", "upload pulado")
    collar_upload = StageResult("SKIPPED", "upload pulado")
    matrix_runtime = RuntimeStageResult(status="SKIPPED", details="serial nao capturado")
    matrix_boot_markers = StageResult("SKIPPED", "serial nao capturado")
    collar_runtime = RuntimeStageResult(status="SKIPPED", details="serial nao capturado")
    matrix_status_result = StageResult("SKIPPED", "status pulado")
    collar_status_result = StageResult("SKIPPED", "status pulado")
    bench_result = StageResult("SKIPPED", "bench pulado")

    try:
        head, short_head, dirty_files = validate_workspace(args.target_commit, out_dir)
        commands_executed.extend([
            "git branch --show-current",
            "git status --short",
            "git log --oneline -10",
            "git rev-parse HEAD",
            "git rev-parse --short=7 HEAD",
        ])
        disallowed_dirty = [line for line in dirty_files if not is_allowed_dirty(line)]
        if dirty_files and not args.allow_dirty and disallowed_dirty:
            raise ValidationError("workspace dirty com arquivos fora da allowlist: " + "; ".join(disallowed_dirty))

        source_markers_result = validate_source_markers(out_dir)
        commands_executed.append("marker search via rg/grep")
        if source_markers_result.status != "PASS":
            raise ValidationError(source_markers_result.details)

        gen_result = run_capture(["python3", "tools/audit/generate_build_info.py"], out_dir / "generate_build_info.log", timeout=120)
        commands_executed.append("python3 tools/audit/generate_build_info.py")
        if gen_result.returncode != 0:
            raise ValidationError("generate_build_info.py falhou")
        generated_headers_result = find_generated_header_locations(out_dir)
        build_info_result = validate_generated_header(args.target_commit, args.stale_sha, out_dir)
        include_chain_result = validate_include_chain()
        if generated_headers_result.status == "FAIL":
            raise ValidationError(generated_headers_result.details)
        if build_info_result.status != "PASS":
            raise ValidationError(build_info_result.details)
        if include_chain_result.status != "PASS":
            raise ValidationError(include_chain_result.details)

        host_tests_result, host_test_commands = run_host_tests(out_dir)
        commands_executed.extend(host_test_commands)
        if host_tests_result.status != "PASS":
            raise ValidationError(host_tests_result.details)

        instrumentation_result = validate_provenance_instrumentation()
        if instrumentation_result.status != "PASS":
            raise ValidationError(instrumentation_result.details)

        if not args.skip_compile:
            clean_build_paths(matrix_build_path, collar_build_path, out_dir)
            commands_executed.append("arduino-cli cache clean")
            matrix_compile = compile_target(
                "gateway-matriz",
                args.fqbn,
                matrix_build_path,
                out_dir / "matrix_compile.log",
                out_dir / "matrix_build_files.txt",
            )
            commands_executed.append(
                f"arduino-cli compile --fqbn {args.fqbn} --build-path {matrix_build_path} gateway-matriz"
            )
            if matrix_compile.status != "PASS":
                raise ValidationError(matrix_compile.details)

            collar_compile = compile_target(
                "coleira",
                args.fqbn,
                collar_build_path,
                out_dir / "collar_compile.log",
                out_dir / "collar_build_files.txt",
            )
            commands_executed.append(
                f"arduino-cli compile --fqbn {args.fqbn} --build-path {collar_build_path} coleira"
            )
            if collar_compile.status != "PASS":
                raise ValidationError(collar_compile.details)
            matrix_binary = validate_binary_strings(
                matrix_build_path,
                args.target_commit,
                args.stale_sha,
                out_dir / "matrix_binary_sha.txt",
            )
            matrix_binary_markers = validate_matrix_binary_markers(
                matrix_build_path,
                out_dir / "matrix_binary_markers.txt",
            )
            collar_binary = validate_binary_strings(
                collar_build_path,
                args.target_commit,
                args.stale_sha,
                out_dir / "collar_binary_sha.txt",
            )
            if matrix_binary.status == "FAIL":
                raise ValidationError(matrix_binary.details)
            if matrix_binary_markers.status == "FAIL":
                raise ValidationError(matrix_binary_markers.details)
            if collar_binary.status == "FAIL":
                raise ValidationError(collar_binary.details)

        if not args.skip_upload:
            if args.skip_compile:
                raise ValidationError("nao e seguro subir firmware com --skip-compile; remova --skip-upload ou rode compile")
            matrix_upload = upload_target(
                "gateway-matriz", args.fqbn, args.matrix_port, matrix_build_path, out_dir / "matrix_upload.log"
            )
            commands_executed.append(
                f"arduino-cli upload -p {args.matrix_port} --fqbn {args.fqbn} --input-dir {matrix_build_path} gateway-matriz"
            )
            if matrix_upload.status != "PASS":
                raise ValidationError(matrix_upload.details)
            collar_upload = upload_target(
                "coleira", args.fqbn, args.collar_port, collar_build_path, out_dir / "collar_upload.log"
            )
            commands_executed.append(
                f"arduino-cli upload -p {args.collar_port} --fqbn {args.fqbn} --input-dir {collar_build_path} coleira"
            )
            if collar_upload.status != "PASS":
                raise ValidationError(collar_upload.details)

        if not args.skip_serial:
            capture_serial_pair(
                args.matrix_port,
                args.collar_port,
                args.serial_baud,
                args.serial_duration,
                out_dir / "matrix_boot_serial.log",
                out_dir / "collar_boot_serial.log",
            )
            commands_executed.append(
                f"serial capture matrix={args.matrix_port} collar={args.collar_port} duration={args.serial_duration}"
            )
            matrix_runtime = summarize_runtime(
                parse_provenance(out_dir / "matrix_boot_serial.log", "matrix", args.target_commit, args.stale_sha),
                args.target_commit,
                args.stale_sha,
            )
            matrix_boot_markers = validate_matrix_boot_markers(
                out_dir / "matrix_boot_serial.log",
                out_dir / "matrix_boot_marker_validation.txt",
            )
            collar_runtime = summarize_runtime(
                parse_provenance(out_dir / "collar_boot_serial.log", "collar", args.target_commit, args.stale_sha),
                args.target_commit,
                args.stale_sha,
            )
            if matrix_runtime.status != "PASS":
                raise ValidationError(f"proveniencia da matriz invalida: {matrix_runtime.details}")
            if matrix_boot_markers.status != "PASS":
                raise ValidationError(f"markers de boot da matriz invalidos: {matrix_boot_markers.details}")
            if collar_runtime.status != "PASS":
                raise ValidationError(f"proveniencia da coleira invalida: {collar_runtime.details}")

        if not args.skip_status and args.matrix_status_url:
            matrix_payload = fetch_status_json(args.matrix_status_url, out_dir / "matrix_status.json")
            matrix_status_result = validate_status_payload(matrix_payload, args.target_commit, args.stale_sha)
            commands_executed.append(f"GET {args.matrix_status_url}")
            if matrix_status_result.status == "FAIL":
                raise ValidationError(matrix_status_result.details)
        if not args.skip_status and args.collar_status_url:
            collar_payload = fetch_status_json(args.collar_status_url, out_dir / "collar_status.json")
            collar_status_result = validate_status_payload(collar_payload, args.target_commit, args.stale_sha)
            commands_executed.append(f"GET {args.collar_status_url}")
            if collar_status_result.status == "FAIL":
                raise ValidationError(collar_status_result.details)

        if not args.skip_bench and args.bench_command:
            bench_result = run_bench_command(
                args.bench_command,
                args.matrix_port,
                args.collar_port,
                args.serial_baud,
                args.bench_duration,
                out_dir,
            )
            commands_executed.append(args.bench_command)
            if bench_result.status == "FAIL":
                raise ValidationError(bench_result.details)

        build_report(
            out_dir,
            args.target_commit,
            args.stale_sha,
            head,
            short_head,
            dirty_files,
            source_markers_result,
            generated_headers_result,
            build_info_result,
            include_chain_result,
            host_tests_result,
            matrix_compile,
            collar_compile,
            matrix_binary,
            matrix_binary_markers,
            collar_binary,
            matrix_upload,
            collar_upload,
            matrix_runtime,
            matrix_boot_markers,
            collar_runtime,
            matrix_status_result,
            collar_status_result,
            bench_result,
            "PASS",
            blocking_issues,
            commands_executed,
        )
        print(str(out_dir))
        return 0
    except ValidationError as exc:
        blocking_issues.append(str(exc))
        build_report(
            out_dir,
            args.target_commit,
            args.stale_sha,
            head,
            short_head,
            dirty_files or git_status_lines(),
            source_markers_result,
            generated_headers_result,
            build_info_result,
            include_chain_result,
            host_tests_result,
            matrix_compile,
            collar_compile,
            matrix_binary,
            matrix_binary_markers,
            collar_binary,
            matrix_upload,
            collar_upload,
            matrix_runtime,
            matrix_boot_markers,
            collar_runtime,
            matrix_status_result,
            collar_status_result,
            bench_result,
            "FAIL",
            blocking_issues,
            commands_executed,
        )
        print(str(exc), file=sys.stderr)
        print(str(out_dir))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
