#!/usr/bin/env python3
"""
serial_listener.py — Listener de serial monitor para auditoria de área sync.

Uso:
  python3 serial_listener.py --port /dev/cu.usbserial-XXX --role MATRIX [--baud 115200] [--filter-cmd <commandId>]
  python3 serial_listener.py --port /dev/cu.usbserial-YYY --role COLLAR  [--filter-cmd <commandId>]

Saída:
  tools/audit/output/<timestamp>/serial_<role>_raw.log
  tools/audit/output/<timestamp>/serial_<role>_area_sync.jsonl
"""

import argparse
import json
import os
import re
import sys
import time
from datetime import datetime, timezone

try:
    import serial
except ImportError:
    print("Instale pyserial: pip install pyserial", file=sys.stderr)
    sys.exit(1)

AREA_SYNC_RE = re.compile(
    r"\[AREA_SYNC\]\[(?P<role>[A-Z_]+)\]\[(?P<level>[A-Z]+)\]\[(?P<event>[A-Z_]+)\]\s*(?P<fields>.*)"
)
KV_RE = re.compile(r"(\w+)=([^\s]+)")


def parse_area_sync_line(line: str) -> dict | None:
    m = AREA_SYNC_RE.search(line)
    if not m:
        return None
    fields = dict(KV_RE.findall(m.group("fields")))
    return {
        "ts": datetime.now(timezone.utc).isoformat(),
        "role": m.group("role"),
        "level": m.group("level"),
        "event": m.group("event"),
        **fields,
    }


def write_metadata(path: str, payload: dict) -> None:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, ensure_ascii=False)


def main():
    parser = argparse.ArgumentParser(description="Listener de serial para auditoria [AREA_SYNC]")
    parser.add_argument("--port", required=True, help="Porta serial (ex: /dev/cu.usbserial-XXX)")
    parser.add_argument("--role", required=True, choices=["MATRIX", "COLLAR", "COMMON_GATEWAY"],
                        help="Role do dispositivo")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--filter-cmd", default=None, help="Filtrar por commandId específico")
    parser.add_argument("--output-dir", default=None, help="Diretório de saída (padrão: tools/audit/output/<ts>)")
    args = parser.parse_args()

    ts_str = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_dir = args.output_dir or os.path.join(
        os.path.dirname(__file__), "output", ts_str
    )
    os.makedirs(out_dir, exist_ok=True)

    role_lower = args.role.lower()
    raw_path = os.path.join(out_dir, f"serial_{role_lower}_raw.log")
    sync_path = os.path.join(out_dir, f"serial_{role_lower}_area_sync.jsonl")
    meta_path = os.path.join(out_dir, f"serial_{role_lower}_listener_meta.json")
    started_at = datetime.now(timezone.utc).isoformat()
    meta = {
        "role": args.role,
        "port": args.port,
        "baud": args.baud,
        "filter_cmd": args.filter_cmd or "",
        "started_at": started_at,
        "open_ok": False,
        "lines_read": 0,
        "area_sync_events": 0,
        "last_line_at": "",
        "stopped_at": "",
        "stop_reason": "",
    }
    write_metadata(meta_path, meta)

    print(f"[listener] Abrindo {args.port} @ {args.baud} baud")
    print(f"[listener] Raw  → {raw_path}")
    print(f"[listener] Sync → {sync_path}")
    print(f"[listener] Meta → {meta_path}")
    if args.filter_cmd:
        print(f"[listener] Filtro commandId={args.filter_cmd}")

    try:
        ser = serial.Serial(args.port, args.baud, timeout=1)
    except serial.SerialException as e:
        meta["stopped_at"] = datetime.now(timezone.utc).isoformat()
        meta["stop_reason"] = f"open_failed: {e}"
        write_metadata(meta_path, meta)
        print(f"[ERRO] Não foi possível abrir porta: {e}", file=sys.stderr)
        sys.exit(1)

    meta["open_ok"] = True
    write_metadata(meta_path, meta)

    with open(raw_path, "w", encoding="utf-8") as raw_f, \
         open(sync_path, "w", encoding="utf-8") as sync_f:
        print(f"[listener] Escutando… Ctrl+C para parar.\n")
        try:
            while True:
                try:
                    raw_line = ser.readline()
                except serial.SerialException:
                    print("[listener] Porta fechada.", file=sys.stderr)
                    break

                if not raw_line:
                    continue

                try:
                    line = raw_line.decode("utf-8", errors="replace").rstrip()
                except Exception:
                    continue

                now_str = datetime.now(timezone.utc).isoformat()
                meta["lines_read"] += 1
                meta["last_line_at"] = now_str
                raw_f.write(f"{now_str}  {line}\n")
                raw_f.flush()

                parsed = parse_area_sync_line(line)
                if parsed:
                    # filtro por commandId
                    if args.filter_cmd and parsed.get("commandId") != args.filter_cmd:
                        continue
                    meta["area_sync_events"] += 1
                    print(f"  [{parsed['level']}][{parsed['event']}] {parsed}")
                    sync_f.write(json.dumps(parsed) + "\n")
                    sync_f.flush()
                write_metadata(meta_path, meta)
        except KeyboardInterrupt:
            meta["stop_reason"] = "keyboard_interrupt"
            print("\n[listener] Encerrado pelo usuário.")
        finally:
            if not meta["stop_reason"]:
                meta["stop_reason"] = "terminated"
            meta["stopped_at"] = datetime.now(timezone.utc).isoformat()
            write_metadata(meta_path, meta)
    ser.close()
    print(f"[listener] Arquivos salvos em {out_dir}")


if __name__ == "__main__":
    main()
