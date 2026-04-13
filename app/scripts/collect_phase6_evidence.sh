#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Uso:
  ./scripts/collect_phase6_evidence.sh --url <supabase_url> --service-role-key <key> --device-id <id> [opcoes]

Opcoes:
  --url <url>               URL base do Supabase.
  --service-role-key <key>  Service role key do projeto.
  --device-id <id>          Device ID da coleira (obrigatorio).
  --gateway-host <host>     Host do gateway para coleta HTTP (padrao: 192.168.4.1).
  --matrix-id <id>          Matrix runtime ID para validar queue key.
  --history-day-key <yyyymmdd>
                            Dia UTC do historico cloud (padrao: hoje em UTC).
  --out <dir>               Diretorio de saida (padrao: ../temp/evidence/phase6/<timestamp>_<deviceId>).
  --logs-limit <n>          Limite para /logs?limit (padrao: 200).
  --skip-gateway            Nao coleta /status, /devices e /logs no gateway.
  --skip-cloud              Nao coleta tabelas cloud.
  -h, --help                Mostra esta ajuda.

Exemplo:
  ./scripts/collect_phase6_evidence.sh \
    --url https://<project-ref>.supabase.co \
    --service-role-key <service_role_key> \
    --device-id 101 \
    --gateway-host 192.168.4.1 \
    --matrix-id matriz-01
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_DIR="$(cd "${APP_DIR}/.." && pwd)"

supabase_url="${SUPABASE_URL:-}"
service_role_key="${SUPABASE_SERVICE_ROLE_KEY:-}"
device_id=""
gateway_host="192.168.4.1"
matrix_id=""
history_day_key="$(date -u +%Y%m%d)"
out_dir=""
logs_limit="200"
skip_gateway=0
skip_cloud=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)
      supabase_url="${2:-}"
      shift 2
      ;;
    --service-role-key)
      service_role_key="${2:-}"
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
    --skip-cloud)
      skip_cloud=1
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

if [[ -z "${supabase_url}" ]]; then
  echo "Erro: informe --url <supabase_url> ou defina SUPABASE_URL." >&2
  exit 1
fi
if [[ -z "${service_role_key}" && "${skip_cloud}" -eq 0 ]]; then
  echo "Erro: informe --service-role-key <key> ou defina SUPABASE_SERVICE_ROLE_KEY." >&2
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

timestamp_utc="$(date -u +%Y%m%dT%H%M%SZ)"

if [[ -z "${out_dir}" ]]; then
  out_dir="${REPO_DIR}/temp/evidence/phase6/${timestamp_utc}_${device_id}"
fi

mkdir -p "${out_dir}"

summary_file="${out_dir}/summary.md"
metadata_file="${out_dir}/metadata.txt"

cat > "${metadata_file}" <<EOF
timestamp_utc=${timestamp_utc}
supabase_url=${supabase_url}
device_id=${device_id}
matrix_id=${matrix_id}
gateway_host=${gateway_host}
history_day_key=${history_day_key}
logs_limit=${logs_limit}
skip_gateway=${skip_gateway}
skip_cloud=${skip_cloud}
EOF

cat > "${summary_file}" <<EOF
# Coleta de evidencias - Fase 6

- Timestamp UTC: \`${timestamp_utc}\`
- Supabase URL: \`${supabase_url}\`
- Device ID: \`${device_id}\`
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

capture_cloud_required() {
  local name="$1"
  local url="$2"
  local out="${out_dir}/${name}.txt"
  if curl --silent --show-error --fail \
      -H "apikey: ${service_role_key}" \
      -H "Authorization: Bearer ${service_role_key}" \
      "${url}" >"${out}" 2>&1; then
    local compact
    compact="$(
      tr -d '[:space:]' < "${out}"
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

if [[ "${skip_cloud}" -eq 0 ]]; then
  capture_cloud_required \
    "cloud_telemetry_latest" \
    "${supabase_url%/}/rest/v1/property_telemetry_latest?select=property_id,device_id,received_at_ms,payload&device_id=eq.${device_id}&order=received_at_ms.desc&limit=1"
  capture_cloud_required \
    "cloud_telemetry_history_day" \
    "${supabase_url%/}/rest/v1/property_telemetry_history?select=property_id,device_id,history_id,received_at_ms,payload&device_id=eq.${device_id}&day_key=eq.${history_day_key}&order=received_at_ms.desc&limit=20"

  if [[ -n "${matrix_id}" ]]; then
    capture_cloud_required \
      "cloud_matrix_queue_key" \
      "${supabase_url%/}/rest/v1/matrix_queue_keys?select=runtime_id,queue_key,writer_key,updated_at_ms&runtime_id=eq.${matrix_id}"
  else
    echo "- \`cloud_matrix_queue_key\`: SKIPPED (matrix-id nao informado)" >> "${summary_file}"
  fi
else
  echo "- cloud tables: SKIPPED (--skip-cloud)" >> "${summary_file}"
fi

manual_file="${out_dir}/manual_evidence_todo.md"
cat > "${manual_file}" <<'EOF'
# Evidencias manuais pendentes (Fase 6)

1. Capturas do app:
   - publicacao do comando
   - feedback visual de sucesso/erro
2. Evidencias cloud:
   - property_commands / property_command_events
   - events / property_events
3. Resultado GO/NO-GO por cenario no PHASE6_EXECUTION_LOG.md
4. Ata final da release
EOF

echo
echo "Coleta concluida."
echo "Diretorio: ${out_dir}"
echo "Resumo: ${summary_file}"
