#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Uso:
  ./scripts/collect_phase6_evidence.sh --project <firebase_project_id> --device-id <id> [opcoes]

Opcoes:
  --project <id>            Projeto Firebase (obrigatorio).
  --device-id <id>          Device ID da coleira (obrigatorio).
  --gateway-host <host>     Host do gateway para coleta HTTP (padrao: 192.168.4.1).
  --matrix-id <id>          Matrix ID para validar chave em /matrixWriterKeys.
  --history-day-key <yyyymmdd>
                            Dia UTC do historico no RTDB (padrao: hoje em UTC).
  --out <dir>               Diretorio de saida (padrao: ../evidence/phase6/<timestamp>_<deviceId>).
  --logs-limit <n>          Limite para /logs?limit (padrao: 200).
  --skip-gateway            Nao coleta /status, /devices e /logs no gateway.
  --skip-rtdb               Nao coleta paths de RTDB.
  -h, --help                Mostra esta ajuda.

Exemplo:
  ./scripts/collect_phase6_evidence.sh \
    --project ruraltech10 \
    --device-id 101 \
    --gateway-host 192.168.4.1 \
    --matrix-id matriz-01
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_DIR="$(cd "${APP_DIR}/.." && pwd)"

project_id=""
device_id=""
gateway_host="192.168.4.1"
matrix_id=""
history_day_key="$(date -u +%Y%m%d)"
out_dir=""
logs_limit="200"
skip_gateway=0
skip_rtdb=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      project_id="${2:-}"
      shift 2
      ;;
    --device-id)
      device_id="${2:-}"
      shift 2
      ;;
    --gateway-host)
      gateway_host="${2:-}"
      shift 2
      ;;
    --matrix-id)
      matrix_id="${2:-}"
      shift 2
      ;;
    --history-day-key)
      history_day_key="${2:-}"
      shift 2
      ;;
    --out)
      out_dir="${2:-}"
      shift 2
      ;;
    --logs-limit)
      logs_limit="${2:-}"
      shift 2
      ;;
    --skip-gateway)
      skip_gateway=1
      shift
      ;;
    --skip-rtdb)
      skip_rtdb=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Argumento desconhecido: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "${project_id}" ]]; then
  echo "Erro: informe --project <firebase_project_id>." >&2
  exit 1
fi
if [[ -z "${device_id}" ]]; then
  echo "Erro: informe --device-id <id>." >&2
  exit 1
fi
if ! [[ "${history_day_key}" =~ ^[0-9]{8}$ ]]; then
  echo "Erro: --history-day-key deve estar em formato YYYYMMDD." >&2
  exit 1
fi
if ! [[ "${logs_limit}" =~ ^[0-9]+$ ]]; then
  echo "Erro: --logs-limit deve ser numerico." >&2
  exit 1
fi

sanitize_rtdb_key() {
  local key="$1"
  key="${key//./_}"
  key="${key//#/_}"
  key="${key//\$/_}"
  key="${key//[/_}"
  key="${key//]/_}"
  key="${key//\//_}"
  printf '%s' "${key}"
}

device_key="$(sanitize_rtdb_key "${device_id}")"
matrix_key="$(sanitize_rtdb_key "${matrix_id}")"
timestamp_utc="$(date -u +%Y%m%dT%H%M%SZ)"

if [[ -z "${out_dir}" ]]; then
  out_dir="${REPO_DIR}/evidence/phase6/${timestamp_utc}_${device_key}"
fi

mkdir -p "${out_dir}"

summary_file="${out_dir}/summary.md"
metadata_file="${out_dir}/metadata.txt"

cat > "${metadata_file}" <<EOF
timestamp_utc=${timestamp_utc}
project_id=${project_id}
device_id=${device_id}
device_key=${device_key}
matrix_id=${matrix_id}
matrix_key=${matrix_key}
gateway_host=${gateway_host}
history_day_key=${history_day_key}
logs_limit=${logs_limit}
skip_gateway=${skip_gateway}
skip_rtdb=${skip_rtdb}
EOF

cat > "${summary_file}" <<EOF
# Coleta de evidencias - Fase 6

- Timestamp UTC: \`${timestamp_utc}\`
- Projeto: \`${project_id}\`
- Device ID: \`${device_id}\` (RTDB key: \`${device_key}\`)
- Matrix ID: \`${matrix_id:-<nao informado>}\`
- Gateway host: \`${gateway_host}\`
- History day key: \`${history_day_key}\`

## Resultado da coleta
EOF

capture_cmd() {
  local name="$1"
  shift
  local out="${out_dir}/${name}.txt"
  if "$@" >"${out}" 2>&1; then
    echo "- \`${name}\`: PASS" >> "${summary_file}"
  else
    echo "- \`${name}\`: FAIL (ver \`${name}.txt\`)" >> "${summary_file}"
  fi
}

capture_http_json() {
  local name="$1"
  local url="$2"
  local out="${out_dir}/${name}.txt"
  if curl --silent --show-error --fail --max-time 12 "${url}" >"${out}" 2>&1; then
    local compact
    compact="$(tr -d '[:space:]' < "${out}")"
    if [[ -z "${compact}" || "${compact}" == "null" ]]; then
      {
        echo
        echo "[validation] FAIL: resposta vazia/null"
      } >> "${out}"
      echo "- \`${name}\`: FAIL (ver \`${name}.txt\`)" >> "${summary_file}"
    elif [[ "${compact:0:1}" != "{" && "${compact:0:1}" != "[" ]]; then
      {
        echo
        echo "[validation] FAIL: resposta nao-JSON"
      } >> "${out}"
      echo "- \`${name}\`: FAIL (ver \`${name}.txt\`)" >> "${summary_file}"
    else
      echo "- \`${name}\`: PASS" >> "${summary_file}"
    fi
  else
    echo "- \`${name}\`: FAIL (ver \`${name}.txt\`)" >> "${summary_file}"
  fi
}

capture_rtdb_required() {
  local name="$1"
  shift
  local out="${out_dir}/${name}.txt"
  if "$@" >"${out}" 2>&1; then
    local compact
    compact="$(
      grep -Ev '^\[|^\(node:|^\(Use ' "${out}" \
        | tr -d '[:space:]'
    )"
    if [[ -z "${compact}" || "${compact}" == "null" || "${compact}" == "{}" ]]; then
      {
        echo
        echo "[validation] FAIL: sem dado real (null/empty)"
      } >> "${out}"
      echo "- \`${name}\`: FAIL (ver \`${name}.txt\`)" >> "${summary_file}"
    else
      echo "- \`${name}\`: PASS" >> "${summary_file}"
    fi
  else
    echo "- \`${name}\`: FAIL (ver \`${name}.txt\`)" >> "${summary_file}"
  fi
}

if [[ "${skip_gateway}" -eq 0 ]]; then
  capture_http_json "gateway_status" "http://${gateway_host}/status"
  capture_http_json "gateway_devices" "http://${gateway_host}/devices"
  capture_http_json "gateway_logs" "http://${gateway_host}/logs?limit=${logs_limit}"
else
  echo "- gateway HTTP: SKIPPED (--skip-gateway)" >> "${summary_file}"
fi

if [[ "${skip_rtdb}" -eq 0 ]]; then
  if ! command -v firebase >/dev/null 2>&1; then
    echo "- firebase_cli: FAIL (comando firebase nao encontrado no PATH)" >> "${summary_file}"
  else
    capture_rtdb_required "rtdb_telemetry_latest" \
      firebase database:get "/telemetryLatest/${device_key}" --project "${project_id}"
    capture_rtdb_required "rtdb_telemetry_history_day" \
      firebase database:get "/telemetryHistory/${device_key}/${history_day_key}" --project "${project_id}"

    if [[ -n "${matrix_key}" ]]; then
      capture_rtdb_required "rtdb_matrix_writer_key" \
        firebase database:get "/matrixWriterKeys/${matrix_key}" --project "${project_id}"
    else
      echo "- \`rtdb_matrix_writer_key\`: SKIPPED (matrix-id nao informado)" >> "${summary_file}"
    fi
  fi
else
  echo "- RTDB: SKIPPED (--skip-rtdb)" >> "${summary_file}"
fi

manual_file="${out_dir}/manual_evidence_todo.md"
cat > "${manual_file}" <<'EOF'
# Evidencias manuais pendentes (Fase 6)

1. Capturas do app:
   - publicacao do comando
   - feedback visual de sucesso/erro
2. Evidencias Firestore:
   - fences/{deviceId}
   - herdingPlans/{deviceId}
   - events/*
3. Resultado GO/NO-GO por cenario no PHASE6_EXECUTION_LOG.md
4. Ata final da release
EOF

echo
echo "Coleta concluida."
echo "Diretorio: ${out_dir}"
echo "Resumo: ${summary_file}"
