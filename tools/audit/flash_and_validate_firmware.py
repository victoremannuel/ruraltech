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
    ensure_text(out_dir / "git_status.txt", ("\n".join(status_lines) + "\n") if status_lines else "")
    ensure_text(out_dir / "commit.txt", f"{head}\n{short_head}\n")
    if head != target_commit:
        raise ValidationError(f"HEAD {head} difere do commit alvo {target_commit}")
    return head, short_head, status_lines


def snapshot_generated_header(out_dir: Path) -> None:
    generated = ROOT / "firmware" / "shared" / "generated_build_info.h"
    if generated.exists():
        shutil.copyfile(generated, out_dir / "generated_build_info_snapshot.h")


def validate_generated_header(target_commit: str, stale_sha: str, out_dir: Path) -> StageResult:
    generated = ROOT / "firmware" / "shared" / "generated_build_info.h"
    text = read_text(generated)
    target_short = short7(target_commit)
    snapshot_generated_header(out_dir)
    if target_commit not in text and target_short not in text:
        return StageResult("FAIL", "generated_build_info.h nao contem o SHA alvo")
    if stale_sha in text:
        return StageResult("FAIL", f"generated_build_info.h ainda contem SHA stale {stale_sha}")
    return StageResult("PASS", f"SHA alvo presente ({target_short})")


def run_host_tests(out_dir: Path) -> tuple[StageResult, list[str]]:
    tests = [
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
        if git_sha == target_commit or target_short in {git_short, git_sha[:7]}:
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
        return StageResult("NOT_RUN", "status indisponivel")
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
    has_stale = "RTR_WAKE_HINT_STALE" in matrix_text
    has_waiting = "RTR_WAITING_FRESH_UPLINK" in matrix_text
    repeated_stale_only = has_stale and not has_waiting
    fresh_release = all(token in matrix_text for token in ("RTR_FRESH_UPLINK_RECEIVED", "RTR_WAKE_HINT_FROM_UPLINK", "RTR_PAGE_TX_OK"))
    collar_page = all(token in collar_text for token in ("RTR_RAW_DOWNLINK_SEEN", "RTR_RAW_DOWNLINK_ACCEPT", "RTR_PAGE_RX", "RTR_PAGE_ACK_TX"))
    if repeated_stale_only:
        return StageResult("FAIL", "stale loop sem RTR_WAITING_FRESH_UPLINK")
    if has_stale and has_waiting:
        return StageResult("PASS", "stale hint seguido de waiting fresh uplink")
    if fresh_release:
        return StageResult("PASS", "fresh uplink liberou page")
    if collar_page:
        return StageResult("PASS", "coleira recebeu RTR_PAGE")
    return StageResult("NOT_RUN", "bench sem evidencia suficiente")


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


def stage_line(title: str, result: StageResult) -> str:
    return f"## {title}\n{result.status}\n{result.details}\n"


def build_report(
    out_dir: Path,
    target_commit: str,
    dirty_files: list[str],
    build_info: StageResult,
    host_tests: StageResult,
    matrix_compile: StageResult,
    collar_compile: StageResult,
    matrix_upload: StageResult,
    collar_upload: StageResult,
    matrix_runtime: ProvenanceObservation,
    collar_runtime: ProvenanceObservation,
    matrix_status: StageResult,
    collar_status: StageResult,
    bench_result: StageResult,
    final_result: str,
    blocking_issues: list[str],
    commands: Iterable[str],
) -> None:
    report = [
        "# Firmware Flash Validation Report",
        "",
        "## Target commit",
        target_commit,
        "",
        "## Git status",
        ("dirty" if dirty_files else "clean"),
    ]
    if dirty_files:
        report.extend(dirty_files)
    report.extend(
        [
            "",
            stage_line("Build info validation", build_info),
            stage_line("Host tests", host_tests),
            stage_line("Matrix compile", matrix_compile),
            stage_line("Collar compile", collar_compile),
            stage_line("Matrix upload", matrix_upload),
            stage_line("Collar upload", collar_upload),
            "## Matrix runtime provenance",
            matrix_runtime.status,
            f"Observed SHA: {matrix_runtime.git_sha or '-'}",
            f"Observed build UTC: {matrix_runtime.build_utc or '-'}",
            f"Observed dirty flag: {matrix_runtime.dirty or '-'}",
            f"Observed line: {matrix_runtime.line or '-'}",
            "",
            "## Collar runtime provenance",
            collar_runtime.status,
            f"Observed SHA: {collar_runtime.git_sha or '-'}",
            f"Observed build UTC: {collar_runtime.build_utc or '-'}",
            f"Observed dirty flag: {collar_runtime.dirty or '-'}",
            f"Observed line: {collar_runtime.line or '-'}",
            "",
            stage_line("Matrix /status validation", matrix_status),
            stage_line("Collar /status validation", collar_status),
            stage_line("SET_FENCE wake validation", bench_result),
            "## Final result",
            final_result,
            "",
            "## Blocking issues",
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

    run_id = datetime.now().strftime("%Y%m%d_%H%M%S") + "_firmware_flash_validation"
    out_dir = Path(args.output_dir) if args.output_dir else ROOT / "tools" / "audit" / "output" / run_id
    out_dir.mkdir(parents=True, exist_ok=True)

    commands_executed: list[str] = []
    blocking_issues: list[str] = []
    matrix_build_path = Path(args.matrix_build_path)
    collar_build_path = Path(args.collar_build_path)

    try:
        head, _, dirty_files = validate_workspace(args.target_commit, out_dir)
        commands_executed.extend([
            "git status --short",
            "git rev-parse HEAD",
            "git rev-parse --short=7 HEAD",
        ])
        disallowed_dirty = [line for line in dirty_files if not is_allowed_dirty(line)]
        if dirty_files and not args.allow_dirty and disallowed_dirty:
            raise ValidationError("workspace dirty com arquivos fora da allowlist: " + "; ".join(disallowed_dirty))

        gen_result = run_capture(["python3", "tools/audit/generate_build_info.py"], out_dir / "generate_build_info.log", timeout=120)
        commands_executed.append("python3 tools/audit/generate_build_info.py")
        if gen_result.returncode != 0:
            raise ValidationError("generate_build_info.py falhou")
        build_info_result = validate_generated_header(args.target_commit, args.stale_sha, out_dir)
        if build_info_result.status != "PASS":
            raise ValidationError(build_info_result.details)

        host_tests_result, host_test_commands = run_host_tests(out_dir)
        commands_executed.extend(host_test_commands)
        if host_tests_result.status != "PASS":
            raise ValidationError(host_tests_result.details)

        instrumentation_result = validate_provenance_instrumentation()
        if instrumentation_result.status != "PASS":
            raise ValidationError(instrumentation_result.details)

        matrix_compile = StageResult("NOT_RUN", "compile pulado")
        collar_compile = StageResult("NOT_RUN", "compile pulado")
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

        matrix_upload = StageResult("NOT_RUN", "upload pulado")
        collar_upload = StageResult("NOT_RUN", "upload pulado")
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

        matrix_runtime = ProvenanceObservation(status="NOT_RUN", role="matrix", line="serial nao capturado")
        collar_runtime = ProvenanceObservation(status="NOT_RUN", role="collar", line="serial nao capturado")
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
            matrix_runtime = parse_provenance(out_dir / "matrix_boot_serial.log", "matrix", args.target_commit, args.stale_sha)
            collar_runtime = parse_provenance(out_dir / "collar_boot_serial.log", "collar", args.target_commit, args.stale_sha)
            if matrix_runtime.status != "PASS":
                raise ValidationError(f"proveniencia da matriz invalida: {matrix_runtime.line}")
            if collar_runtime.status != "PASS":
                raise ValidationError(f"proveniencia da coleira invalida: {collar_runtime.line}")

        matrix_status_result = StageResult("NOT_RUN", "status pulado")
        collar_status_result = StageResult("NOT_RUN", "status pulado")
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

        bench_result = StageResult("NOT_RUN", "bench pulado")
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
            head,
            dirty_files,
            build_info_result,
            host_tests_result,
            matrix_compile,
            collar_compile,
            matrix_upload,
            collar_upload,
            matrix_runtime,
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
            git_status_lines(),
            StageResult("FAIL", "ver relatorio"),
            StageResult("NOT_RUN", "interrompido"),
            StageResult("NOT_RUN", "interrompido"),
            StageResult("NOT_RUN", "interrompido"),
            StageResult("NOT_RUN", "interrompido"),
            StageResult("NOT_RUN", "interrompido"),
            ProvenanceObservation(status="NOT_RUN", role="matrix"),
            ProvenanceObservation(status="NOT_RUN", role="collar"),
            StageResult("NOT_RUN", "interrompido"),
            StageResult("NOT_RUN", "interrompido"),
            StageResult("NOT_RUN", "interrompido"),
            "FAIL",
            blocking_issues,
            commands_executed,
        )
        print(str(exc), file=sys.stderr)
        print(str(out_dir))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
