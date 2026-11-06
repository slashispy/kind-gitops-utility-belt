#!/usr/bin/env bash
# =============================================================================
# 03-bootstrap-apps.sh — arranca el circuito GitOps aplicando ÚNICAMENTE la
# Application raíz (App of Apps). Argo CD reconcilia el resto desde Git:
#   root -> AppProject(quicktask) + ApplicationSet -> Application(quicktask)
#        -> chart genérico + values -> Deployment/Service/CM/Secret + MongoDB
# -----------------------------------------------------------------------------
# Se aplica directamente desde GitHub (raw) para no necesitar el repo clonado.
# =============================================================================
source "$(dirname "$0")/lib.sh"

require_all kubectl

kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null

# Convierte la URL del repo (github.com/owner/repo) en la URL raw del fichero.
RAW_BASE="${ARGOCD_APPS_REPO/github.com/raw.githubusercontent.com}"
APP_OF_APPS_URL="${RAW_BASE}/${ARGOCD_APPS_REF}/app-of-apps.yaml"

log "Aplicando App of Apps (root) desde: ${APP_OF_APPS_URL}"
kubectl apply -n "${ARGOCD_NAMESPACE}" -f "${APP_OF_APPS_URL}"

ok "App of Apps aplicada. Argo CD comenzará a sincronizar el circuito."
cat <<EOF

  Observa el progreso:
    kubectl -n ${ARGOCD_NAMESPACE} get applications
    kubectl -n ${APP_NAMESPACE} get pods -w

  Cuando 'quicktask' esté Healthy/Synced:
    kubectl -n ${APP_NAMESPACE} port-forward svc/quicktask 9090:8080
    curl -fsS http://localhost:9090/health   # -> {"status":"ok"}

  Estado global: scripts cualquiera -> 'make status'
EOF
