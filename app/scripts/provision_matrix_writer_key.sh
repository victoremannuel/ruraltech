#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Uso:
  ./scripts/provision_matrix_writer_key.sh --project <firebase_project_id> [opcoes]

Opcoes:
  --project <id>           Projeto Firebase (obrigatorio se nao existir no firebase.json).
  --matrix-id <id>         Matrix ID para chave em /matrixWriterKeys.
  --writer-key <key>       Writer key que sera liberada nas regras RTDB.
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
  - Le projectId de firebase.json (primeiro encontrado), se --project nao for informado.
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_DIR="$(cd "${APP_DIR}/.." && pwd)"
DEFAULT_MANUAL_SETTINGS="${REPO_DIR}/gateway-matriz/manual_settings.h"
DEFAULT_LOCAL_OVERRIDES="${REPO_DIR}/gateway-matriz/manual_settings.local.h"

project_id=""
matrix_id=""
writer_key=""
manual_settings="${DEFAULT_MANUAL_SETTINGS}"
local_overrides="${DEFAULT_LOCAL_OVERRIDES}"
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      project_id="${2:-}"
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

if [[ -z "${project_id}" && -f "${APP_DIR}/firebase.json" ]]; then
  project_id="$(sed -nE 's/.*"projectId": "([^"]+)".*/\1/p' "${APP_DIR}/firebase.json" | head -n 1)"
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

if [[ -z "${project_id}" ]]; then
  echo "Erro: informe --project <firebase_project_id>." >&2
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
if is_placeholder "${matrix_id}"; then
  echo "Erro: matrix_id ainda esta com placeholder (${matrix_id})." >&2
  exit 1
fi
if is_placeholder "${writer_key}"; then
  echo "Erro: writer_key ainda esta com placeholder (${writer_key})." >&2
  exit 1
fi
if [[ ${#writer_key} -lt 8 ]]; then
  echo "Erro: writer_key invalida (minimo 8 caracteres)." >&2
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

path="/matrixWriterKeys/${matrix_id_sanitized}"
payload="\"${writer_key}\""

echo "Projeto: ${project_id}"
echo "Matrix ID (orig): ${matrix_id}"
echo "Matrix ID (rtdb): ${matrix_id_sanitized}"
echo "Path RTDB: ${path}"
echo "Fonte local-overrides: ${local_overrides}"
echo "Fonte fallback: ${manual_settings}"

if ! command -v firebase >/dev/null 2>&1; then
  echo "Erro: Firebase CLI nao encontrado no PATH." >&2
  exit 1
fi

cmd=(firebase database:set "${path}" "${payload}" --project "${project_id}" --confirm)
if [[ ${dry_run} -eq 1 ]]; then
  echo "Dry-run:"
  printf '  %q' "${cmd[@]}"
  echo
  exit 0
fi

"${cmd[@]}"
echo "Writer key provisionada em ${path}."
echo "Validando..."
firebase database:get "${path}" --project "${project_id}"
