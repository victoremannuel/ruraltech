#!/usr/bin/env python3
"""
area_sync_e2e.py — Orquestrador de teste E2E de atualização de área.

Fluxo:
  1. Busca área existente com linked_device_ids
  2. Salva polígono baseline
  3. Aplica mudança leve (desloca 1 vértice ~1m)
  4. Inicia subprocessos: serial_listener (matriz + coleira) + supabase_poller
  5. Atualiza a área via API Supabase
  6. Aguarda terminal (sucesso ou falha) em todos os listeners
  7. Gera relatório final Markdown + JSON
  8. (Opcional) Restaura polígono original

Variáveis de ambiente obrigatórias:
  SUPABASE_URL
  SUPABASE_SERVICE_ROLE_KEY

Variáveis opcionais:
  MATRIX_SERIAL_PORT    (ex: /dev/cu.usbserial-MATRIX)
  COLLAR_SERIAL_PORT    (ex: /dev/cu.usbserial-COLLAR)
  SERIAL_BAUD           (padrão: 115200)
  AREA_ID               (se não fornecido, busca automaticamente)
  PROPERTY_ID
  RESTORE_AFTER_TEST    (1 = restaurar polígono original ao fim)

Uso:
  SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... python3 tools/e2e/area_sync_e2e.py
"""

import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

try:
    import httpx
except ImportError:
    print("Instale httpx: pip install httpx", file=sys.stderr)
    sys.exit(1)

SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
MATRIX_PORT = os.environ.get("MATRIX_SERIAL_PORT", "")
COLLAR_PORT = os.environ.get("COLLAR_SERIAL_PORT", "")
SERIAL_BAUD = int(os.environ.get("SERIAL_BAUD", "115200"))
AREA_ID = os.environ.get("AREA_ID", "")
PROPERTY_ID = os.environ.get("PROPERTY_ID", "")
RESTORE = os.environ.get("RESTORE_AFTER_TEST", "0") == "1"

TOOLS_DIR = Path(__file__).parent.parent
AUDIT_DIR = TOOLS_DIR / "audit"
SCRIPT_LISTENER = AUDIT_DIR / "serial_listener.py"
SCRIPT_POLLER = AUDIT_DIR / "supabase_poller.py"

# ~1 metro em graus (~0.000009 graus de latitude ≈ 1m)
DELTA_LAT = 0.000010


def headers():
    return {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }


def rest_get(path: str, params: dict) -> list:
    # Filtros PostgREST (ex: "id=eq.xxx") devem ser query params individuais.
    # httpx aceita lista de tuplas para params duplicados; usamos dict normalmente.
    r = httpx.get(
        f"{SUPABASE_URL}/rest/v1/{path}",
        headers=headers(),
        params=params,
        timeout=10,
    )
    if not r.is_success:
        raise RuntimeError(f"GET {path} → {r.status_code}: {r.text}")
    return r.json()


def rest_patch(path: str, match: dict, body: dict) -> list:
    # Filtros passados como query params separados
    params = {k: f"eq.{v}" for k, v in match.items()}
    r = httpx.patch(
        f"{SUPABASE_URL}/rest/v1/{path}",
        headers=headers(),
        params=params,
        json=body,
        timeout=10,
    )
    if not r.is_success:
        raise RuntimeError(f"PATCH {path} → {r.status_code}: {r.text}")
    return r.json()


def find_area(area_id: str, property_id: str) -> dict:
    # Monta params sem conflito: filtros PostgREST usam chave=operador.valor
    params: dict = {"select": "id,property_id,perimeter,linked_device_ids", "limit": "1"}
    if area_id:
        params["id"] = f"eq.{area_id}"
    elif property_id:
        params["property_id"] = f"eq.{property_id}"
    rows = rest_get("areas", params)
    if not rows:
        raise RuntimeError("Nenhuma área encontrada. Defina AREA_ID ou PROPERTY_ID.")
    return rows[0]


def perim_to_latlon_list(perimeter: list) -> list:
    """Normaliza perimeter para lista de [lat, lon] independente do formato."""
    out = []
    for p in perimeter:
        if isinstance(p, dict):
            out.append([float(p["lat"]), float(p["lon"])])
        elif isinstance(p, (list, tuple)) and len(p) >= 2:
            out.append([float(p[0]), float(p[1])])
    return out


def latlon_list_to_supabase(points: list) -> list:
    """Converte [[lat,lon],...] de volta para [{lat,lon},...] (formato Supabase)."""
    return [{"lat": p[0], "lon": p[1]} for p in points]


def apply_light_delta(perimeter: list) -> list:
    """Desloca o primeiro vértice ~1m para norte (formato [[lat,lon]])."""
    if not perimeter:
        return perimeter
    new_perim = [list(p) for p in perimeter]
    new_perim[0] = [new_perim[0][0] + DELTA_LAT, new_perim[0][1]]
    return new_perim


def start_listener(port: str, role: str, out_dir: str, command_id: str) -> subprocess.Popen | None:
    if not port:
        print(f"[e2e] {role}_SERIAL_PORT não definido — listener {role} desabilitado.")
        return None
    cmd = [
        sys.executable, str(SCRIPT_LISTENER),
        "--port", port,
        "--role", role,
        "--baud", str(SERIAL_BAUD),
        "--output-dir", out_dir,
    ]
    if command_id:
        cmd += ["--filter-cmd", command_id]
    print(f"[e2e] Iniciando listener {role} em {port}")
    return subprocess.Popen(cmd)


def start_poller(area_id: str, property_id: str, command_id: str, out_dir: str) -> subprocess.Popen:
    cmd = [
        sys.executable, str(SCRIPT_POLLER),
        "--area-id", area_id,
        "--property-id", property_id,
        "--output-dir", out_dir,
    ]
    if command_id:
        cmd += ["--command-id", command_id]
    print(f"[e2e] Iniciando poller Supabase")
    return subprocess.Popen(cmd)


def generate_report(
    out_dir: str,
    area: dict,
    orig_perim: list,
    new_perim: list,
    command_id: str,
    timeline: list,
    conclusion: str,
    failures: list,
) -> None:
    ts = datetime.now(timezone.utc).isoformat()
    report = {
        "timestamp": ts,
        "areaId": area.get("id"),
        "propertyId": area.get("property_id"),
        "commandId": command_id,
        "linkedDeviceIds": area.get("linked_device_ids", []),
        "matrixSerialPort": MATRIX_PORT or "N/A",
        "collarSerialPort": COLLAR_PORT or "N/A",
        "originalPerimeter": orig_perim,
        "modifiedPerimeter": new_perim,
        "deltaDescription": f"Vértice 0 deslocado +{DELTA_LAT} lat (~1m norte)",
        "timeline": timeline,
        "conclusion": conclusion,
        "failures": failures,
    }
    json_path = os.path.join(out_dir, "area_sync_e2e_report.json")
    md_path = os.path.join(out_dir, "area_sync_e2e_report.md")

    with open(json_path, "w") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)

    with open(md_path, "w") as f:
        f.write(f"# Relatório E2E — Area Sync\n\n")
        f.write(f"**Data/hora:** {ts}\n\n")
        f.write(f"**Conclusão:** `{conclusion}`\n\n")
        f.write(f"## Configuração\n\n")
        f.write(f"| Campo | Valor |\n|---|---|\n")
        f.write(f"| areaId | `{area.get('id')}` |\n")
        f.write(f"| propertyId | `{area.get('property_id')}` |\n")
        f.write(f"| commandId | `{command_id or 'N/A'}` |\n")
        f.write(f"| linkedDeviceIds | `{area.get('linked_device_ids')}` |\n")
        f.write(f"| matrixSerialPort | `{MATRIX_PORT or 'N/A'}` |\n")
        f.write(f"| collarSerialPort | `{COLLAR_PORT or 'N/A'}` |\n\n")
        f.write(f"## Delta do polígono\n\n")
        f.write(f"- Vértice 0 original: `{orig_perim[0] if orig_perim else 'N/A'}`\n")
        f.write(f"- Vértice 0 alterado: `{new_perim[0] if new_perim else 'N/A'}`\n")
        f.write(f"- Delta: `+{DELTA_LAT}` lat (~1m norte)\n\n")
        if failures:
            f.write(f"## Falhas detectadas\n\n")
            for fail in failures:
                f.write(f"- {fail}\n")
            f.write("\n")
        f.write(f"## Timeline\n\n")
        for entry in timeline:
            f.write(f"- `{entry}`\n")
        f.write(f"\n## Próximos passos\n\n")
        if conclusion == "SUCCESS":
            f.write("- Fluxo ponta a ponta validado. ✓\n")
        else:
            f.write("- Investigar falhas listadas acima.\n")
            f.write("- Verificar serial monitor e tabelas Supabase.\n")
            f.write(f"- Arquivo de logs: `{out_dir}`\n")

    print(f"\n[e2e] Relatório salvo:\n  {md_path}\n  {json_path}")


def main():
    if not SUPABASE_URL or not SUPABASE_KEY:
        print("[ERRO] Defina SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY", file=sys.stderr)
        sys.exit(1)

    ts_str = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_dir = str(AUDIT_DIR / "output" / ts_str)
    os.makedirs(out_dir, exist_ok=True)

    timeline = []
    failures = []

    def log(msg: str):
        ts = datetime.now(timezone.utc).isoformat()
        entry = f"{ts}  {msg}"
        timeline.append(entry)
        print(f"[e2e] {msg}")

    # --- Fase 1: descobrir área
    log("Buscando área existente...")
    try:
        area = find_area(AREA_ID, PROPERTY_ID)
    except Exception as e:
        print(f"[ERRO] {e}", file=sys.stderr)
        sys.exit(1)

    area_id = area["id"]
    property_id = area["property_id"]
    # Normaliza para [[lat,lon]] internamente
    orig_perim = perim_to_latlon_list(area.get("perimeter") or [])
    devices = area.get("linked_device_ids") or []

    log(f"Área: id={area_id} property={property_id} devices={devices} points={len(orig_perim)}")

    if not orig_perim:
        failures.append("Área sem polígono (perimeter vazio)")
        generate_report(out_dir, area, orig_perim, [], "", timeline, "INCONCLUSIVO", failures)
        sys.exit(1)

    if not devices:
        failures.append("Área sem linked_device_ids — nenhuma coleira para testar")
        generate_report(out_dir, area, orig_perim, orig_perim, "", timeline, "INCONCLUSIVO", failures)
        sys.exit(1)

    # --- Fase 2: gerar polígono alterado
    new_perim = apply_light_delta(orig_perim)
    log(f"Polígono alterado: vértice 0 {orig_perim[0]} → {new_perim[0]}")

    # --- Fase 3: iniciar listeners e poller (commandId ainda desconhecido)
    matrix_proc = start_listener(MATRIX_PORT, "MATRIX", out_dir, "")
    collar_proc = start_listener(COLLAR_PORT, "COLLAR", out_dir, "")
    time.sleep(1)  # pequena espera para os listeners abrirem a porta

    # --- Fase 4: disparar atualização da área
    # Supabase espera [{lat, lon}], não [[lat, lon]]
    perim_for_supabase = latlon_list_to_supabase(new_perim)
    log(f"Atualizando área {area_id} no Supabase...")
    try:
        rest_patch("areas", {"id": area_id}, {"perimeter": perim_for_supabase})
        log("Área atualizada com sucesso no Supabase.")
    except Exception as e:
        failures.append(f"Falha ao atualizar área: {e}")
        generate_report(out_dir, area, orig_perim, new_perim, "", timeline, "FALHA", failures)
        for p in [matrix_proc, collar_proc]:
            if p:
                p.terminate()
        sys.exit(1)

    # --- Fase 5: iniciar poller Supabase
    time.sleep(2)
    poller_proc = start_poller(area_id, property_id, "", out_dir)

    # --- Fase 6: aguardar até terminal (max 10 min)
    log("Aguardando resultado ponta a ponta (max ~10 min)...")
    MAX_WAIT_S = 600
    poll_s = 5
    elapsed = 0
    conclusion = "INCONCLUSIVO"

    while elapsed < MAX_WAIT_S:
        time.sleep(poll_s)
        elapsed += poll_s

        # Verificar se poller terminou
        if poller_proc.poll() is not None:
            # ler último snapshot para determinar conclusão
            snap_path = os.path.join(out_dir, "supabase_snapshots.jsonl")
            tl_path = os.path.join(out_dir, "supabase_timeline.jsonl")
            if os.path.exists(tl_path):
                with open(tl_path) as f:
                    lines = [l.strip() for l in f if l.strip()]
                for line in reversed(lines):
                    try:
                        entry = json.loads(line)
                        ev = entry.get("event", "")
                        status = entry.get("to") or entry.get("status", "")
                        if ev == "polygon_apply_result" and status == "success":
                            conclusion = "SUCCESS"
                            log(f"polygon_apply_result=success — fluxo validado.")
                            break
                        elif ev == "status_change" and status == "completed":
                            conclusion = "SUCCESS"
                            log("Comando completed no Supabase.")
                            break
                        elif status in {"failed", "rejected", "nacked", "expired", "failure"}:
                            conclusion = "FALHA"
                            failures.append(f"Status terminal negativo: {status}")
                            log(f"Status terminal negativo: {status}")
                            break
                    except Exception:
                        continue
            break

    if conclusion == "INCONCLUSIVO":
        failures.append("Timeout: fluxo não alcançou estado terminal em 10 min")

    # --- Fase 7: encerrar subprocessos
    for proc in [matrix_proc, collar_proc, poller_proc]:
        if proc and proc.poll() is None:
            proc.terminate()

    # --- Fase 8 (opcional): restaurar polígono
    if RESTORE:
        log("Restaurando polígono original...")
        try:
            rest_patch("areas", {"id": area_id}, {"perimeter": latlon_list_to_supabase(orig_perim)})
            log("Polígono original restaurado.")
        except Exception as e:
            log(f"Aviso: falha ao restaurar polígono: {e}")

    # --- Fase 9: relatório final
    generate_report(out_dir, area, orig_perim, new_perim, "", timeline, conclusion, failures)

    print(f"\n[e2e] Conclusão: {conclusion}")
    if failures:
        for f in failures:
            print(f"  ! {f}")


if __name__ == "__main__":
    main()
