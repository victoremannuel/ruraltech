#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Uso:
  ./scripts/deploy_firebase.sh [opcoes]

Opcoes:
  --project <id>      Projeto Firebase. Se omitido, le o primeiro projectId de firebase.json.
  --only <targets>    Alvos do deploy. Padrao: firestore:rules,database,functions
  --skip-install      Nao instala dependencias de app/functions antes do deploy.
  --dry-run           Apenas imprime o comando final.
  -h, --help          Mostra esta ajuda.

Exemplo:
  ./scripts/deploy_firebase.sh --project ruraltech10
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
FUNCTIONS_DIR="${APP_DIR}/functions"

project_id=""
deploy_only="firestore:rules,database,functions"
skip_install=0
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      project_id="${2:-}"
      shift 2
      ;;
    --only)
      deploy_only="${2:-}"
      shift 2
      ;;
    --skip-install)
      skip_install=1
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

if [[ -z "${project_id}" ]]; then
  project_id="$(sed -nE 's/.*"projectId": "([^"]+)".*/\1/p' "${APP_DIR}/firebase.json" | head -n 1)"
fi

if [[ -z "${project_id}" ]]; then
  echo "Erro: nao foi possivel descobrir o projectId. Informe --project <id>." >&2
  exit 1
fi

if ! command -v firebase >/dev/null 2>&1; then
  echo "Erro: Firebase CLI nao encontrado no PATH." >&2
  exit 1
fi

if [[ "${dry_run}" -eq 0 && "${skip_install}" -eq 0 &&
      "${deploy_only}" == *functions* && -f "${FUNCTIONS_DIR}/package.json" ]]; then
  if [[ -f "${FUNCTIONS_DIR}/package-lock.json" ]]; then
    (cd "${FUNCTIONS_DIR}" && npm ci)
  else
    (cd "${FUNCTIONS_DIR}" && npm install)
  fi
fi

cmd=(firebase deploy --project "${project_id}" --only "${deploy_only}")

echo "Projeto Firebase: ${project_id}"
echo "Alvos de deploy: ${deploy_only}"

if [[ "${dry_run}" -eq 1 ]]; then
  printf 'Comando:'
  printf ' %q' "${cmd[@]}"
  echo
  exit 0
fi

(cd "${APP_DIR}" && "${cmd[@]}")
