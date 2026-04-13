#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Uso:
  ./scripts/provision_matrix_writer_key.sh --url <supabase_url> --service-role-key <key> [opcoes]

Opcoes:
  --url <url>              URL base do Supabase.
  --service-role-key <key> Service role key do projeto.
  --matrix-id <id>         Matrix runtime ID.
  --writer-key <key>       Writer key da matriz.
  --queue-key <key>        Queue key da fila cloud.
  --manual-settings <path> Arquivo manual_settings.h para fallback.
  --local-overrides <path> Arquivo manual_settings.local.h para segredos.
  --dry-run                Apenas imprime o comando sem executar.
  -h, --help               Mostra esta ajuda.

Comportamento padrao:
  - Le primeiro de:
      1) ../gateway-matriz/manual_settings.local.h
      2) ../gateway-matriz/manual_settings.h
    Campos: RT_CFG_RTDB_MATRIX_ID / RTDB_MATRIX_ID
            RT_CFG_RTDB_WRITER_KEY / RTDB_WRITER_KEY
            RT_CFG_RTDB_QUEUE_KEY / RTDB_QUEUE_KEY
  - Le `SUPABASE_URL` e `SUPABASE_SERVICE_ROLE_KEY` do ambiente se flags nao forem informadas.
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_DIR="$(cd "${APP_DIR}/.." && pwd)"
DEFAULT_MANUAL_SETTINGS="${REPO_DIR}/gateway-matriz/manual_settings.h"
DEFAULT_LOCAL_OVERRIDES="${REPO_DIR}/gateway-matriz/manual_settings.local.h"

supabase_url="${SUPABASE_URL:-}"
service_role_key="${SUPABASE_SERVICE_ROLE_KEY:-}"
matrix_id=""
writer_key=""
queue_key=""
manual_settings="${DEFAULT_MANUAL_SETTINGS}"
local_overrides="${DEFAULT_LOCAL_OVERRIDES}"
dry_run=0

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
    --matrix-id)
      matrix_id="${2:-}"
      shift 2
      ;;
    --writer-key)
      writer_key="${2:-}"
      shift 2
      ;;
    --queue-key)
      queue_key="${2:-}"
      shift 2
      ;;
    --manual-settings)
      manual_settings="${2:-}"
      shift 2
      ;;
    --local-overrides)
      local_overrides="${2:-}"
      shift 2
      ;;
    --dry-run)
      dry_run=1
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
  supabase_url="$(
    sed -nE "s/.*supabaseUrl = String.fromEnvironment\\([^']*defaultValue: '([^']+)'.*/\\1/p" \
      "${APP_DIR}/lib/config/manual_settings.dart" | head -n 1
  )"
fi

extract_macro() {
  local macro_name="$1"
  local file_path="$2"
  sed -nE "s/^[[:space:]]*#define[[:space:]]+${macro_name}[[:space:]]+\"([^\"]*)\"[[:space:]]*$/\\1/p" "${file_path}" | head -n 1
}

extract_const() {
  local const_name="$1"
  local file_path="$2"
  sed -nE "s/^[[:space:]]*constexpr[[:space:]]+char[[:space:]]+${const_name}\\[\\][[:space:]]*=[[:space:]]*\"([^\"]*)\"[[:space:]]*;.*/\\1/p" "${file_path}" | head -n 1
}

resolve_setting() {
  local macro_name="$1"
  local const_name="$2"
  local value=""
  local src=""

  for src in "${local_overrides}" "${manual_settings}"; do
    [[ -f "${src}" ]] || continue
    if [[ -z "${value}" ]]; then
      value="$(extract_macro "${macro_name}" "${src}")"
    fi
    if [[ -z "${value}" ]]; then
      value="$(extract_const "${const_name}" "${src}")"
    fi
    [[ -n "${value}" ]] && break
  done

  printf '%s' "${value}"
}

is_placeholder() {
  case "$1" in
    ""|SET_*|CHANGE_ME*|YOUR_*|EXAMPLE_*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

if [[ -z "${matrix_id}" ]]; then
  matrix_id="$(resolve_setting RT_CFG_RTDB_MATRIX_ID RTDB_MATRIX_ID)"
fi
if [[ -z "${writer_key}" ]]; then
  writer_key="$(resolve_setting RT_CFG_RTDB_WRITER_KEY RTDB_WRITER_KEY)"
fi
if [[ -z "${queue_key}" ]]; then
  queue_key="$(resolve_setting RT_CFG_RTDB_QUEUE_KEY RTDB_QUEUE_KEY)"
fi

if [[ -z "${supabase_url}" ]]; then
  echo "Erro: informe --url <supabase_url> ou defina SUPABASE_URL." >&2
  exit 1
fi
if [[ -z "${service_role_key}" ]]; then
  echo "Erro: informe --service-role-key <key> ou defina SUPABASE_SERVICE_ROLE_KEY." >&2
  exit 1
fi
if [[ -z "${matrix_id}" ]]; then
  echo "Erro: informe --matrix-id ou configure RT_CFG_RTDB_MATRIX_ID no local-overrides." >&2
  exit 1
fi
if [[ -z "${writer_key}" ]]; then
  echo "Erro: informe --writer-key ou configure RT_CFG_RTDB_WRITER_KEY no local-overrides." >&2
  exit 1
fi
if [[ -z "${queue_key}" ]]; then
  echo "Erro: informe --queue-key ou configure RT_CFG_RTDB_QUEUE_KEY no local-overrides." >&2
  exit 1
fi
if is_placeholder "${matrix_id}"; then
  echo "Erro: matrix_id ainda esta com placeholder (${matrix_id})." >&2
  exit 1
fi
if is_placeholder "${writer_key}"; then
  echo "Erro: writer_key ainda esta com placeholder (${writer_key})." >&2
  exit 1
fi
if is_placeholder "${queue_key}"; then
  echo "Erro: queue_key ainda esta com placeholder (${queue_key})." >&2
  exit 1
fi
if [[ ${#writer_key} -lt 8 ]]; then
  echo "Erro: writer_key invalida (minimo 8 caracteres)." >&2
  exit 1
fi
if [[ ${#queue_key} -lt 8 ]]; then
  echo "Erro: queue_key invalida (minimo 8 caracteres)." >&2
  exit 1
fi

matrix_id_sanitized="${matrix_id//./_}"
matrix_id_sanitized="${matrix_id_sanitized//\#/_}"
matrix_id_sanitized="${matrix_id_sanitized//\$/_}"
matrix_id_sanitized="${matrix_id_sanitized//[/_}"
matrix_id_sanitized="${matrix_id_sanitized//]/_}"
matrix_id_sanitized="${matrix_id_sanitized//\//_}"

if [[ -z "${matrix_id_sanitized}" ]]; then
  echo "Erro: matrix_id invalido apos sanitizacao." >&2
  exit 1
fi

writer_path="/matrixWriterKeys/${matrix_id_sanitized}"
queue_updated_at_ms="$(( $(date +%s) * 1000 ))"
rest_url="${supabase_url%/}/rest/v1/matrix_queue_keys?on_conflict=runtime_id&select=runtime_id,queue_key,writer_key,updated_at_ms"
validate_url="${supabase_url%/}/rest/v1/matrix_queue_keys?select=runtime_id,queue_key,writer_key,updated_at_ms&runtime_id=eq.${matrix_id_sanitized}"
queue_payload="$(cat <<EOF
[{
  "runtime_id": "${matrix_id_sanitized}",
  "queue_key": "${queue_key}",
  "writer_key": "${writer_key}",
  "updated_at_ms": ${queue_updated_at_ms},
  "raw": {
    "matrixRuntimeId": "${matrix_id_sanitized}",
    "queueKey": "${queue_key}",
    "writerKey": "${writer_key}",
    "updatedAtMs": ${queue_updated_at_ms},
    "writer": "gateway_matrix"
  }
}]
EOF
)"

echo "Supabase URL: ${supabase_url}"
echo "Matrix ID (orig): ${matrix_id}"
echo "Matrix ID (cloud): ${matrix_id_sanitized}"
echo "Fonte local-overrides: ${local_overrides}"
echo "Fonte fallback: ${manual_settings}"
if [[ ${dry_run} -eq 1 ]]; then
  echo "Dry-run:"
  printf '  %q' curl --silent --show-error --fail -X POST "${rest_url}" \
    -H "apikey: ${service_role_key}" \
    -H "Authorization: Bearer ${service_role_key}" \
    -H "Content-Type: application/json" \
    -H "Prefer: resolution=merge-duplicates,return=representation" \
    --data "${queue_payload}"
  echo
  exit 0
fi

curl --silent --show-error --fail \
  -X POST "${rest_url}" \
  -H "apikey: ${service_role_key}" \
  -H "Authorization: Bearer ${service_role_key}" \
  -H "Content-Type: application/json" \
  -H "Prefer: resolution=merge-duplicates,return=representation" \
  --data "${queue_payload}"
echo
echo "Queue key provisionada para ${matrix_id_sanitized}."
echo "Validando..."
curl --silent --show-error --fail \
  -H "apikey: ${service_role_key}" \
  -H "Authorization: Bearer ${service_role_key}" \
  "${validate_url}"
echo
