#!/usr/bin/env bash
# =============================================================================
# lib.sh — helpers compartidos por los scripts de bootstrap.
# Se importa con:  source "$(dirname "$0")/lib.sh"
# =============================================================================

# Fallar pronto y de forma ruidosa.
set -euo pipefail

# ---- Configuración (sobrescribible por variables de entorno) ----------------
export CLUSTER_NAME="${CLUSTER_NAME:-quicktask-gitops}"
export ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
export ARGOCD_VERSION="${ARGOCD_VERSION:-stable}"   # tag/branch de argo-cd/install.yaml

# Imagen de la app.
export IMAGE_NAME="${IMAGE_NAME:-quicktask}"
export IMAGE_TAG="${IMAGE_TAG:-dev}"
export IMAGE_REF="${IMAGE_NAME}:${IMAGE_TAG}"

# Ruta local del repo de la app (para `docker build`). Ajustable por entorno.
export QUICKTASK_DIR="${QUICKTASK_DIR:-$HOME/Developer/go/proyectos/quicktask}"

# Repo de manifiestos de Argo CD (App of Apps). Se aplica a mano app-of-apps.yaml.
export ARGOCD_APPS_REPO="${ARGOCD_APPS_REPO:-https://github.com/slashispy/gitops-argocd-apps}"
export ARGOCD_APPS_REF="${ARGOCD_APPS_REF:-main}"

# Namespace de la app.
export APP_NAMESPACE="${APP_NAMESPACE:-quicktask}"

# Raíz del repo utility-belt (dos niveles arriba de scripts/).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ---- Logging ----------------------------------------------------------------
log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✔\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m✘ %s\033[0m\n' "$*" >&2; exit 1; }

# ---- Verificación de prerequisitos ------------------------------------------
require() {
  command -v "$1" >/dev/null 2>&1 || die "Falta el binario requerido: '$1'. Instálalo y reintenta."
}

require_all() {
  for bin in "$@"; do require "$bin"; done
}
