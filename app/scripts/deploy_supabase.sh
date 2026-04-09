#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Uso:
  ./scripts/deploy_supabase.sh [opcoes]

Opcoes:
  --project-ref <id>   Project ref do Supabase. Se omitido, usa `supabase/config.toml`.
  --functions <lista>  Funcoes separadas por virgula. Padrao:
                       queue-lora-command,repair-firebase-mirrors,matrix-cloud
  --skip-db            Nao executa `supabase db push`.
  --skip-functions     Nao executa deploy das Edge Functions.
  --dry-run            Apenas imprime os comandos.
  -h, --help           Mostra esta ajuda.
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_DIR="$(cd "${APP_DIR}/.." && pwd)"
SUPABASE_DIR="${REPO_DIR}/supabase"

project_ref=""
functions_csv="queue-lora-command,repair-firebase-mirrors,matrix-cloud"
skip_db=0
skip_functions=0
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-ref)
      project_ref="${2:-}"
      shift 2
      ;;
    --functions)
      functions_csv="${2:-}"
      shift 2
      ;;
    --skip-db)
      skip_db=1
      shift
      ;;
    --skip-functions)
      skip_functions=1
      shift
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

if [[ -z "${project_ref}" && -f "${SUPABASE_DIR}/config.toml" ]]; then
  project_ref="$(sed -nE 's/^project_id = "([^"]+)"/\1/p' "${SUPABASE_DIR}/config.toml" | head -n 1)"
fi

if ! command -v supabase >/dev/null 2>&1; then
  echo "Erro: Supabase CLI nao encontrado no PATH." >&2
  exit 1
fi

if [[ -z "${project_ref}" ]]; then
  echo "Erro: informe --project-ref <id> ou configure project_id em supabase/config.toml." >&2
  exit 1
fi

IFS=',' read -r -a function_list <<< "${functions_csv}"

link_cmd=(supabase link --workdir "${REPO_DIR}" --project-ref "${project_ref}")
db_cmd=(supabase db push --workdir "${REPO_DIR}")

echo "Project ref: ${project_ref}"
echo "Supabase dir: ${SUPABASE_DIR}"
echo "Funcoes: ${functions_csv}"

if [[ "${dry_run}" -eq 1 ]]; then
  printf 'Link:'
  printf ' %q' "${link_cmd[@]}"
  echo
  if [[ "${skip_db}" -eq 0 ]]; then
    printf 'DB:'
    printf ' %q' "${db_cmd[@]}"
    echo
  fi
  if [[ "${skip_functions}" -eq 0 ]]; then
    for fn in "${function_list[@]}"; do
      fn="$(echo "${fn}" | xargs)"
      [[ -n "${fn}" ]] || continue
      printf 'Function:'
      printf ' %q' supabase functions deploy "${fn}" --workdir "${REPO_DIR}"
      echo
    done
  fi
  exit 0
fi

"${link_cmd[@]}"

if [[ "${skip_db}" -eq 0 ]]; then
  "${db_cmd[@]}"
fi

if [[ "${skip_functions}" -eq 0 ]]; then
  for fn in "${function_list[@]}"; do
    fn="$(echo "${fn}" | xargs)"
    [[ -n "${fn}" ]] || continue
    supabase functions deploy "${fn}" --workdir "${REPO_DIR}"
  done
fi
