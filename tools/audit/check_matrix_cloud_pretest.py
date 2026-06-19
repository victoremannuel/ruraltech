#!/usr/bin/env python3
"""
Checklist cirurgico de pre-teste para o fluxo app -> cloud -> matriz -> coleira.

Foco:
- verificar se a matriz esta realmente pronta para cloud/downlink
- verificar se a coleira ainda preserva os sinais esperados
- produzir uma saida objetiva com tabela e conclusao binaria

Uso:
  python3 tools/audit/check_matrix_cloud_pretest.py
  python3 tools/audit/check_matrix_cloud_pretest.py --json
"""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass, asdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""


def find_define(text: str, name: str) -> str | None:
    pattern = re.compile(rf"^\s*#define\s+{re.escape(name)}\s+(.+?)\s*$", re.MULTILINE)
    match = pattern.search(text)
    return match.group(1).strip() if match else None


def has_token(text: str, token: str) -> bool:
    return token in text


def normalize_define(value: str | None) -> str:
    if value is None:
        return "ausente"
    return value.strip()


@dataclass
class CheckRow:
    item: str
    arquivo: str
    valor_encontrado: str
    valor_esperado: str
    status: str


def okfail(ok: bool) -> str:
    return "OK" if ok else "FALHA"


def matrix_checks() -> tuple[list[CheckRow], dict]:
    config_path = ROOT / "gateway-matriz" / "config.h"
    manual_path = ROOT / "gateway-matriz" / "manual_settings.h"
    local_path = ROOT / "gateway-matriz" / "manual_settings.local.h"
    api_path = ROOT / "gateway-matriz" / "ApiServer.cpp"
    ino_path = ROOT / "gateway-matriz" / "gateway-matriz.ino"

    config_text = read_text(config_path)
    manual_text = read_text(manual_path)
    local_text = read_text(local_path)
    api_text = read_text(api_path)
    ino_text = read_text(ino_path)

    diag_default = find_define(config_text, "RT_MATRIX_DIAG_STAGE")
    diag_local = find_define(local_text, "RT_MATRIX_DIAG_STAGE")
    effective_diag = diag_local or diag_default or "ausente"
    has_local = local_path.exists()

    placeholders_present = any(
        value and "SET_" in value
        for value in [
            find_define(local_text, "RT_CFG_BACKHAUL_WIFI_SSID"),
            find_define(local_text, "RT_CFG_BACKHAUL_WIFI_PASS"),
            find_define(local_text, "RT_CFG_SUPABASE_EDGE_HOST"),
            find_define(local_text, "RT_CFG_RTDB_MATRIX_ID"),
            find_define(local_text, "RT_CFG_RTDB_WRITER_KEY"),
            find_define(local_text, "RT_CFG_RTDB_QUEUE_KEY"),
        ]
    )
    if not has_local:
      placeholders_value = "manual_settings.local.h ausente"
    else:
      placeholders_value = "presente" if placeholders_present else "ausente"

    queue_key_local = find_define(local_text, "RT_CFG_RTDB_QUEUE_KEY")
    matrix_id_local = find_define(local_text, "RT_CFG_RTDB_MATRIX_ID")
    edge_host_local = find_define(local_text, "RT_CFG_SUPABASE_EDGE_HOST")
    writer_key_local = find_define(local_text, "RT_CFG_RTDB_WRITER_KEY")
    wifi_ssid_local = find_define(local_text, "RT_CFG_BACKHAUL_WIFI_SSID")
    wifi_pass_local = find_define(local_text, "RT_CFG_BACKHAUL_WIFI_PASS")

    rows = [
        CheckRow(
            "DIAG_STAGE",
            "gateway-matriz/config.h" + (" + gateway-matriz/manual_settings.local.h" if has_local else ""),
            effective_diag,
            "4",
            okfail(effective_diag == "4"),
        ),
        CheckRow(
            "DIAG_PROFILE",
            "gateway-matriz/config.h",
            'DIAG_STAGE == 4 ? "diag-cloud-no-sd"',
            '"diag-cloud-no-sd"',
            okfail('DIAG_STAGE == 4 ? "diag-cloud-no-sd"' in config_text),
        ),
        CheckRow(
            "CLOUD_BACKHAUL_CFG",
            "gateway-matriz/config.h + gateway-matriz/manual_settings.local.h",
            "FEATURE_CLOUD depende de DIAG_STAGE>=4 + credenciais reais",
            "ON",
            okfail(effective_diag == "4" and has_local and not placeholders_present),
        ),
        CheckRow(
            "QUEUE POLLING",
            "gateway-matriz/gateway-matriz.ino",
            "queuePollingConfigured() = cloudTelemetryConfigured() && !isUnsetCloudValue(RTDB_QUEUE_KEY)",
            "habilitado",
            okfail(effective_diag == "4" and has_local and bool(queue_key_local) and "SET_" not in (queue_key_local or "")),
        ),
        CheckRow(
            "placeholders SET_*",
            "gateway-matriz/manual_settings.local.h" if has_local else "gateway-matriz/manual_settings.h",
            placeholders_value,
            "ausente",
            okfail(has_local and not placeholders_present),
        ),
        CheckRow(
            "BACKHAUL_WIFI_SSID",
            "gateway-matriz/manual_settings.local.h" if has_local else "gateway-matriz/manual_settings.h",
            normalize_define(wifi_ssid_local if has_local else find_define(manual_text, "RT_CFG_BACKHAUL_WIFI_SSID")),
            "credencial real",
            okfail(has_local and wifi_ssid_local is not None and "SET_" not in wifi_ssid_local),
        ),
        CheckRow(
            "BACKHAUL_WIFI_PASS",
            "gateway-matriz/manual_settings.local.h" if has_local else "gateway-matriz/manual_settings.h",
            "<definido>" if has_local and wifi_pass_local else "ausente",
            "credencial real ou vazio intencional",
            okfail(has_local and wifi_pass_local is not None and "SET_" not in wifi_pass_local),
        ),
        CheckRow(
            "SUPABASE_EDGE_HOST",
            "gateway-matriz/manual_settings.local.h" if has_local else "gateway-matriz/manual_settings.h",
            normalize_define(edge_host_local if has_local else find_define(manual_text, "RT_CFG_SUPABASE_EDGE_HOST")),
            "host real sem protocolo",
            okfail(has_local and edge_host_local is not None and "SET_" not in edge_host_local),
        ),
        CheckRow(
            "RTDB_MATRIX_ID",
            "gateway-matriz/manual_settings.local.h" if has_local else "gateway-matriz/manual_settings.h",
            normalize_define(matrix_id_local if has_local else find_define(manual_text, "RT_CFG_RTDB_MATRIX_ID")),
            "runtimeId real",
            okfail(has_local and matrix_id_local is not None and "SET_" not in matrix_id_local),
        ),
        CheckRow(
            "RTDB_WRITER_KEY",
            "gateway-matriz/manual_settings.local.h" if has_local else "gateway-matriz/manual_settings.h",
            "<definido>" if has_local and writer_key_local else "ausente",
            "writer key real",
            okfail(has_local and writer_key_local is not None and "SET_" not in writer_key_local),
        ),
        CheckRow(
            "RTDB_QUEUE_KEY",
            "gateway-matriz/manual_settings.local.h" if has_local else "gateway-matriz/manual_settings.h",
            normalize_define(queue_key_local if has_local else find_define(manual_text, "RT_CFG_RTDB_QUEUE_KEY")),
            "queue key real",
            okfail(has_local and queue_key_local is not None and "SET_" not in queue_key_local),
        ),
        CheckRow(
            "/status queueConfigured",
            "gateway-matriz/ApiServer.cpp",
            "presente",
            "presente",
            okfail(has_token(api_text, 'doc["queueConfigured"]')),
        ),
        CheckRow(
            "boot log queue_polling_not_configured",
            "gateway-matriz/gateway-matriz.ino",
            "presente",
            "presente",
            okfail(has_token(ino_text, "queue_polling_not_configured")),
        ),
    ]

    blockers: list[str] = []
    if effective_diag != "4":
        blockers.append("DIAG_STAGE efetivo nao esta em 4")
    if not has_local:
        blockers.append("gateway-matriz/manual_settings.local.h ausente")
    if has_local and placeholders_present:
        blockers.append("manual_settings.local.h ainda contem placeholders SET_*")
    if has_local and (not queue_key_local or "SET_" in queue_key_local):
        blockers.append("RT_CFG_RTDB_QUEUE_KEY nao esta preenchido com valor real")

    summary = {
        "has_local_settings": has_local,
        "effective_diag_stage": effective_diag,
        "placeholders_present": placeholders_present if has_local else True,
        "matrix_runtime_id": normalize_define(matrix_id_local if has_local else find_define(manual_text, "RT_CFG_RTDB_MATRIX_ID")),
        "queue_key": normalize_define(queue_key_local if has_local else find_define(manual_text, "RT_CFG_RTDB_QUEUE_KEY")),
        "blockers": blockers,
        "boot_required": [
            "DIAG_STAGE : 4",
            "CLOUD_BACKHAUL_CFG : ON",
            "QUEUE_POLLING_CFG : ON",
            "MATRIX_RUNTIME_ID : <runtime real>",
            "ausencia de QUEUE_POLL_SKIPPED reason=queue_polling_not_configured",
        ],
    }
    return rows, summary


def collar_checks() -> tuple[list[CheckRow], dict]:
    config_path = ROOT / "coleira" / "config.h"
    collar_ino = ROOT / "coleira" / "coleira.ino"
    lora_manager = ROOT / "coleira" / "LoRaManager.cpp"
    config_text = read_text(config_path)
    ino_text = read_text(collar_ino)
    lora_text = read_text(lora_manager)

    rows = [
        CheckRow(
            "RTR_DISCOVERY_WINDOW_MS_BENCH",
            "coleira/config.h",
            "5000" if "RTR_DISCOVERY_WINDOW_MS_BENCH = 5000" in config_text else "ausente",
            "5000 ou maior",
            okfail("RTR_DISCOVERY_WINDOW_MS_BENCH = 5000" in config_text),
        ),
        CheckRow(
            "RTR_SECONDARY_RX_WINDOW_MS",
            "coleira/config.h",
            "1200" if "RTR_SECONDARY_RX_WINDOW_MS = 1200" in config_text else "ausente",
            "1200 ou maior",
            okfail("RTR_SECONDARY_RX_WINDOW_MS = 1200" in config_text),
        ),
        CheckRow("RTR_DISCOVERY_WINDOW_OPEN", "coleira/coleira.ino", "presente" if "RTR_DISCOVERY_WINDOW_OPEN" in ino_text else "ausente", "presente", okfail("RTR_DISCOVERY_WINDOW_OPEN" in ino_text)),
        CheckRow("RTR_DISCOVERY_WINDOW_SECONDARY_OPEN", "coleira/coleira.ino", "presente" if "RTR_DISCOVERY_WINDOW_SECONDARY_OPEN" in ino_text else "ausente", "presente", okfail("RTR_DISCOVERY_WINDOW_SECONDARY_OPEN" in ino_text)),
        CheckRow("RTR_PAGE_RX", "coleira/coleira.ino", "presente" if "RTR_PAGE_RX" in ino_text else "ausente", "presente", okfail("RTR_PAGE_RX" in ino_text)),
        CheckRow("RTR_PAGE_ACK_TX", "coleira/coleira.ino", "presente" if "RTR_PAGE_ACK_TX" in ino_text else "ausente", "presente", okfail("RTR_PAGE_ACK_TX" in ino_text)),
        CheckRow("RTR_RAW_DOWNLINK_RX", "coleira/LoRaManager.cpp", "presente" if "RTR_RAW_DOWNLINK_RX" in lora_text else "ausente", "presente", okfail("RTR_RAW_DOWNLINK_RX" in lora_text)),
        CheckRow("RTR_RAW_DOWNLINK_DROP", "coleira/LoRaManager.cpp", "presente" if "RTR_RAW_DOWNLINK_DROP" in lora_text else "ausente", "presente", okfail("RTR_RAW_DOWNLINK_DROP" in lora_text)),
        CheckRow("RTR_RAW_DOWNLINK_ACCEPT", "coleira/LoRaManager.cpp", "presente" if "RTR_RAW_DOWNLINK_ACCEPT" in lora_text else "ausente", "presente", okfail("RTR_RAW_DOWNLINK_ACCEPT" in lora_text)),
    ]
    summary = {
        "ready": all(row.status == "OK" for row in rows),
        "expected_boot_signals": [
            "binding pronto",
            "LoRa ok",
            "RTR_DISCOVERY_WINDOW_OPEN",
            "RTR_DISCOVERY_WINDOW_SECONDARY_OPEN",
        ],
    }
    return rows, summary


def render_table(rows: list[CheckRow]) -> str:
    lines = [
        "| Item | Arquivo | Valor encontrado | Valor esperado | Status |",
        "|---|---|---|---|---|",
    ]
    for row in rows:
        lines.append(
            f"| {row.item} | `{row.arquivo}` | `{row.valor_encontrado}` | `{row.valor_esperado}` | **{row.status}** |"
        )
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description="Checklist cirurgico de pre-teste da matriz cloud/downlink")
    parser.add_argument("--json", action="store_true", help="Emitir resultado em JSON")
    args = parser.parse_args()

    matrix_rows, matrix_summary = matrix_checks()
    collar_rows, collar_summary = collar_checks()

    matrix_ready = len(matrix_summary["blockers"]) == 0
    overall_ready = matrix_ready and collar_summary["ready"]
    result = {
        "matrix_ready_for_cloud_downlink": matrix_ready,
        "collar_ready": collar_summary["ready"],
        "environment_ready_for_bench": overall_ready,
        "matrix_summary": matrix_summary,
        "collar_summary": collar_summary,
        "matrix_rows": [asdict(row) for row in matrix_rows],
        "collar_rows": [asdict(row) for row in collar_rows],
        "conclusion": (
            "Conclusao A — ambiente pronto para teste"
            if matrix_ready
            else "Conclusao B — ambiente nao pronto para teste"
        ),
        "smallest_patch_if_needed": (
            "criar/preencher gateway-matriz/manual_settings.local.h com DIAG_STAGE=4 e credenciais reais"
            if not matrix_ready
            else "nenhum patch de codigo obrigatorio"
        ),
    }

    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return

    print("# Checklist Cirurgico de Pre-Teste\n")
    print("## Matriz\n")
    print(render_table(matrix_rows))
    print("\n```text")
    print(f"MATRIZ PRONTA PARA CLOUD/DOWNLINK? {'SIM' if matrix_ready else 'NAO'}")
    print("Motivo principal:")
    if matrix_ready:
        print("configuracao local encontrada, sem placeholders, com pre-condicoes de cloud/polling atendidas")
    else:
        print(matrix_summary["blockers"][0] if matrix_summary["blockers"] else "inconclusivo")
    print("Bloqueador encontrado:")
    print("; ".join(matrix_summary["blockers"]) if matrix_summary["blockers"] else "nenhum")
    print("Linha(s) de evidencia:")
    print("- gateway-matriz/config.h: RT_MATRIX_DIAG_STAGE default = 0")
    print("- gateway-matriz/manual_settings.h: placeholders SET_* desativam cloud")
    print("- gateway-matriz/gateway-matriz.ino: queuePollingConfigured() depende de cloudTelemetryConfigured() + RTDB_QUEUE_KEY real")
    print("```\n")

    print("## Coleira\n")
    print(render_table(collar_rows))
    print("\n```text")
    print(f"COLEIRA PRONTA? {'SIM' if collar_summary['ready'] else 'NAO'}")
    print("Conclusao:")
    print("coleira pronta" if collar_summary["ready"] else "coleira com regressao estatica")
    print("```\n")

    print("## Conclusao\n")
    print(result["conclusion"])
    print(f"Ambiente pronto para bancada? {'SIM' if overall_ready else 'NAO'}")
    print(f"Menor patch necessario: {result['smallest_patch_if_needed']}")


if __name__ == "__main__":
    main()
