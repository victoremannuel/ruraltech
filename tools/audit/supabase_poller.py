#!/usr/bin/env python3
"""
supabase_poller.py — Polling das tabelas Supabase para auditoria de área sync.

Uso:
  python3 supabase_poller.py \
    --area-id <areaId> \
    --property-id <propertyId> \
    [--command-id <commandId>] \
    [--output-dir tools/audit/output/<ts>]

Requer variáveis de ambiente:
  SUPABASE_URL
  SUPABASE_SERVICE_ROLE_KEY

Tabelas consultadas:
  property_commands, property_command_events, matrix_command_queues, propertyEvents
"""

import argparse
import json
import os
import sys
import time
from datetime import datetime, timezone

try:
    import httpx
except ImportError:
    print("Instale httpx: pip install httpx", file=sys.stderr)
    sys.exit(1)

SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")

TERMINAL_STATUSES = {"completed", "failed", "expired", "rejected", "nacked"}
POLL_INTERVAL_S = 3
MAX_POLLS = 200  # ~10 min


def headers():
    return {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json",
    }


def rest_get(path: str, params: dict) -> list:
    url = f"{SUPABASE_URL}/rest/v1/{path}"
    r = httpx.get(url, headers=headers(), params=params, timeout=10)
    r.raise_for_status()
    return r.json()


def fetch_property_commands(area_id: str, property_id: str) -> list:
    # Colunas reais: command_id, command, status, origin_doc_id, origin_doc_type,
    #                property_id, created_at, updated_at, reason
    params: dict = {
        "select": "command_id,command,status,origin_doc_id,origin_doc_type,property_id,created_at,updated_at,reason",
        "origin_doc_id": f"eq.{area_id}",
        "origin_doc_type": "eq.area",
        "order": "created_at.desc",
        "limit": "5",
    }
    return rest_get("property_commands", params)


def fetch_command_events(command_id: str) -> list:
    return rest_get("property_command_events", {
        "select": "*",
        "command_id": f"eq.{command_id}",
        "order": "created_at.asc",
    })


def fetch_matrix_queue(property_id: str, command_id: str) -> list:
    # Tabela não tem property_id nem status — filtra por command_id quando disponível
    params: dict = {
        "select": "command_id,runtime_id,queue_key,created_at_ms,expires_at_ms,payload,created_at",
        "order": "created_at_ms.desc",
        "limit": "5",
    }
    if command_id:
        params["command_id"] = f"eq.{command_id}"
    return rest_get("matrix_command_queues", params)


def fetch_property_events(property_id: str, command_id: str) -> list:
    # Colunas reais: event_type, device_id, event_id, payload, received_at_ms, property_id
    params: dict = {
        "select": "event_id,event_type,device_id,property_id,payload,received_at_ms",
        "property_id": f"eq.{property_id}",
        "event_type": "eq.polygon_apply_result",
        "order": "received_at_ms.desc",
        "limit": "10",
    }
    return rest_get("property_events", params)


def snapshot(area_id: str, property_id: str, command_id: str) -> dict:
    ts = datetime.now(timezone.utc).isoformat()
    cmds = fetch_property_commands(area_id, property_id)
    resolved_cmd_id = command_id or (cmds[0].get("command_id") if cmds else "")
    return {
        "ts": ts,
        "commandId": resolved_cmd_id,
        "property_commands": cmds,
        "command_events": fetch_command_events(resolved_cmd_id) if resolved_cmd_id else [],
        "matrix_queue": fetch_matrix_queue(property_id, resolved_cmd_id),
        "property_events": fetch_property_events(property_id, resolved_cmd_id),
    }


def detect_terminal(snap: dict) -> tuple[bool, str]:
    """Retorna (is_terminal, status)."""
    for cmd in snap.get("property_commands", []):
        status = cmd.get("status", "")
        if status in TERMINAL_STATUSES:
            return True, status
    for ev in snap.get("property_events", []):
        if ev.get("event_type") == "polygon_apply_result":
            try:
                import json as _json
                payload = _json.loads(ev.get("payload") or "{}")
                ev_status = payload.get("status", "unknown")
            except Exception:
                ev_status = "unknown"
            return True, ev_status
    return False, ""


def main():
    parser = argparse.ArgumentParser(description="Poller Supabase para auditoria de área sync")
    parser.add_argument("--area-id", required=True)
    parser.add_argument("--property-id", required=True)
    parser.add_argument("--command-id", default="")
    parser.add_argument("--output-dir", default=None)
    args = parser.parse_args()

    if not SUPABASE_URL or not SUPABASE_KEY:
        print("[ERRO] Defina SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY", file=sys.stderr)
        sys.exit(1)

    ts_str = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_dir = args.output_dir or os.path.join(
        os.path.dirname(__file__), "output", ts_str
    )
    os.makedirs(out_dir, exist_ok=True)
    snap_path = os.path.join(out_dir, "supabase_snapshots.jsonl")
    timeline_path = os.path.join(out_dir, "supabase_timeline.jsonl")

    print(f"[poller] areaId={args.area_id} propertyId={args.property_id}")
    print(f"[poller] Snapshots → {snap_path}")
    print(f"[poller] Timeline  → {timeline_path}")

    prev_status = None

    with open(snap_path, "w") as snap_f, open(timeline_path, "w") as tl_f:
        for i in range(MAX_POLLS):
            try:
                snap = snapshot(args.area_id, args.property_id, args.command_id)
            except Exception as e:
                print(f"[poller] Erro ao consultar: {e}")
                time.sleep(POLL_INTERVAL_S)
                continue

            snap_f.write(json.dumps(snap) + "\n")
            snap_f.flush()

            # timeline: detecta mudança de status
            for cmd in snap.get("property_commands", []):
                status = cmd.get("status", "")
                if status != prev_status:
                    entry = {
                        "ts": snap["ts"],
                        "event": "status_change",
                        "commandId": cmd.get("command_id"),
                        "from": prev_status,
                        "to": status,
                    }
                    tl_f.write(json.dumps(entry) + "\n")
                    tl_f.flush()
                    print(f"  [timeline] {entry}")
                    prev_status = status

            for ev in snap.get("property_events", []):
                try:
                    import json as _json
                    pl = _json.loads(ev.get("payload") or "{}")
                except Exception:
                    pl = {}
                entry = {
                    "ts": snap["ts"],
                    "event": "polygon_apply_result",
                    "commandId": pl.get("commandId") or pl.get("cmd_id"),
                    "status": pl.get("status"),
                    "deviceId": ev.get("device_id"),
                    "pointCount": pl.get("pointCount") or pl.get("point_count"),
                    "errorCode": pl.get("errorCode") or pl.get("error_code"),
                }
                tl_f.write(json.dumps(entry) + "\n")
                tl_f.flush()
                print(f"  [event] {entry}")

            is_terminal, terminal_status = detect_terminal(snap)
            if is_terminal:
                print(f"\n[poller] Terminal: {terminal_status}")
                break

            time.sleep(POLL_INTERVAL_S)

    print(f"[poller] Concluído. Arquivos em {out_dir}")


if __name__ == "__main__":
    main()
