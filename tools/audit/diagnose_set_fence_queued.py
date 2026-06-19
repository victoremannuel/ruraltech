#!/usr/bin/env python3
"""
Diagnostica runs do SET_FENCE que ficaram parados em queued.

Uso:
  tools/audit/.venv/bin/python tools/audit/diagnose_set_fence_queued.py \
    --output-dir tools/audit/output/20260419_002501
"""

import argparse
import json
import os
from datetime import datetime, timezone


def read_jsonl(path: str) -> list[dict]:
    if not os.path.exists(path):
        return []
    out = []
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                out.append(json.loads(line))
            except Exception:
                continue
    return out


def read_json(path: str) -> dict:
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8", errors="replace") as f:
        try:
            return json.load(f)
        except Exception:
            return {}


def file_size(path: str) -> int:
    return os.path.getsize(path) if os.path.exists(path) else 0


def classify(last_snap: dict, matrix_meta: dict, collar_meta: dict, matrix_raw_size: int, collar_raw_size: int) -> tuple[str, str]:
    has_property_command = bool(last_snap.get("property_commands"))
    has_queue = bool(last_snap.get("matrix_queue"))
    has_matrix_signal = matrix_meta.get("area_sync_events", 0) > 0 or matrix_raw_size > 0
    has_collar_signal = collar_meta.get("area_sync_events", 0) > 0 or collar_raw_size > 0

    if has_property_command and not has_queue:
        return (
            "fila nao criada para a matriz",
            "o comando existe no registro principal, mas nao apareceu em matrix_command_queues",
        )
    if has_queue and not has_matrix_signal:
        return (
            "fila nao consumida pela matriz ou captura serial inexistente",
            "o comando entrou em matrix_command_queues, mas nao ha qualquer evidência serial da matriz no run",
        )
    if has_matrix_signal and not has_collar_signal:
        return (
            "matriz consumiu ou emitiu sinais, mas a coleira nao mostrou recepcao",
            "ha atividade serial da matriz, mas nao ha evidência serial da coleira",
        )
    if has_matrix_signal and has_collar_signal:
        return (
            "ha sinais em ambas as pontas; revisar parser ou correlacao fina por commandId",
            "existem indícios seriais nas duas pontas, entao o problema pode estar na instrumentacao do teste ou na correlacao",
        )
    return (
        "diagnostico inconclusivo",
        "nao foi possivel classificar automaticamente com os artefatos disponiveis",
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Diagnostico de SET_FENCE parado em queued")
    parser.add_argument("--output-dir", required=True, help="Diretorio do run em tools/audit/output/<timestamp>")
    args = parser.parse_args()

    out_dir = args.output_dir
    snapshots = read_jsonl(os.path.join(out_dir, "supabase_snapshots.jsonl"))
    timeline = read_jsonl(os.path.join(out_dir, "supabase_timeline.jsonl"))
    report = read_json(os.path.join(out_dir, "area_sync_e2e_report.json"))

    last_snap = snapshots[-1] if snapshots else {}
    command_id = (report.get("commandId") or last_snap.get("commandId") or "")
    property_commands = last_snap.get("property_commands", [])
    command_events = last_snap.get("command_events", [])
    matrix_queue = last_snap.get("matrix_queue", [])
    property_events = last_snap.get("property_events", [])

    matrix_raw = os.path.join(out_dir, "serial_matrix_raw.log")
    collar_raw = os.path.join(out_dir, "serial_collar_raw.log")
    matrix_sync = os.path.join(out_dir, "serial_matrix_area_sync.jsonl")
    collar_sync = os.path.join(out_dir, "serial_collar_area_sync.jsonl")
    matrix_meta = read_json(os.path.join(out_dir, "serial_matrix_listener_meta.json"))
    collar_meta = read_json(os.path.join(out_dir, "serial_collar_listener_meta.json"))

    matrix_raw_size = file_size(matrix_raw)
    collar_raw_size = file_size(collar_raw)
    matrix_sync_events = len(read_jsonl(matrix_sync))
    collar_sync_events = len(read_jsonl(collar_sync))

    classification, rationale = classify(last_snap, matrix_meta, collar_meta, matrix_raw_size, collar_raw_size)

    result = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "output_dir": out_dir,
        "commandId": command_id,
        "summary": {
            "property_commands_count": len(property_commands),
            "command_events_count": len(command_events),
            "matrix_queue_count": len(matrix_queue),
            "property_events_count": len(property_events),
            "matrix_raw_bytes": matrix_raw_size,
            "collar_raw_bytes": collar_raw_size,
            "matrix_area_sync_events": matrix_sync_events,
            "collar_area_sync_events": collar_sync_events,
        },
        "matrix_listener": matrix_meta,
        "collar_listener": collar_meta,
        "classification": classification,
        "rationale": rationale,
        "answers": {
            "comando_criado": bool(property_commands),
            "entrou_na_fila_da_matriz": bool(matrix_queue),
            "matriz_viu_o_comando": matrix_sync_events > 0 or matrix_raw_size > 0,
            "matriz_tentou_enviar_lora": False,
            "coleira_recebeu": collar_sync_events > 0 or collar_raw_size > 0,
            "houve_ack_ou_retorno_backend": bool(property_events),
        },
        "recommended_next_steps": [
            "confirmar serial manual da matriz antes do proximo teste",
            "confirmar porta serial e firmware gravado na matriz",
            "repetir rodada com listener stdout/stderr capturados",
            "comparar se a matriz em bancada esta consumindo matrix_command_queues para o runtime_id esperado",
        ],
    }

    md_path = os.path.join(out_dir, "set_fence_queued_diagnosis.md")
    json_path = os.path.join(out_dir, "set_fence_queued_diagnosis.json")

    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)

    with open(md_path, "w", encoding="utf-8") as f:
        f.write("# Diagnóstico SET_FENCE parado em queued\n\n")
        f.write(f"**commandId:** `{command_id or 'N/A'}`\n\n")
        f.write(f"**Classificação:** `{classification}`\n\n")
        f.write(f"**Racional:** {rationale}\n\n")
        f.write("## Resumo\n\n")
        f.write(f"- property_commands: `{len(property_commands)}`\n")
        f.write(f"- command_events: `{len(command_events)}`\n")
        f.write(f"- matrix_queue: `{len(matrix_queue)}`\n")
        f.write(f"- property_events: `{len(property_events)}`\n")
        f.write(f"- matrix raw bytes: `{matrix_raw_size}`\n")
        f.write(f"- collar raw bytes: `{collar_raw_size}`\n")
        f.write(f"- matrix AREA_SYNC events: `{matrix_sync_events}`\n")
        f.write(f"- collar AREA_SYNC events: `{collar_sync_events}`\n\n")
        f.write("## Respostas\n\n")
        for key, value in result["answers"].items():
            f.write(f"- `{key}`: `{value}`\n")
        f.write("\n## Próximos passos\n\n")
        for item in result["recommended_next_steps"]:
            f.write(f"- {item}\n")

    print(json.dumps(result, indent=2, ensure_ascii=False))
    print(f"\nDiagnóstico salvo em:\n  {md_path}\n  {json_path}")


if __name__ == "__main__":
    main()
