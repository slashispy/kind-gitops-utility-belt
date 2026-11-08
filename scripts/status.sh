#!/usr/bin/env bash
# =============================================================================
# status.sh — foto rápida del estado del circuito.
# =============================================================================
source "$(dirname "$0")/lib.sh"

require kubectl

if ! kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  warn "El cluster '${CLUSTER_NAME}' no existe. Ejecuta 'make up' primero."
  exit 0
fi

kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null

log "Argo CD Applications:"
kubectl -n "${ARGOCD_NAMESPACE}" get applications 2>/dev/null | sed 's/^/    /' || warn "Argo CD no instalado todavía."

echo
log "ApplicationSets:"
kubectl -n "${ARGOCD_NAMESPACE}" get applicationsets 2>/dev/null | sed 's/^/    /' || true

echo
log "Pods en '${APP_NAMESPACE}':"
kubectl -n "${APP_NAMESPACE}" get pods -o wide 2>/dev/null | sed 's/^/    /' || warn "Namespace '${APP_NAMESPACE}' aún no existe."

echo
log "Services en '${APP_NAMESPACE}':"
kubectl -n "${APP_NAMESPACE}" get svc 2>/dev/null | sed 's/^/    /' || true

cat <<EOF

  Port-forward quicktask-auth: kubectl -n ${APP_NAMESPACE} port-forward svc/quicktask-auth 9092:8080
  Port-forward quicktask:  kubectl -n ${APP_NAMESPACE} port-forward svc/quicktask 9090:8080
  Port-forward Argo CD UI: kubectl -n ${ARGOCD_NAMESPACE} port-forward svc/argocd-server 9091:443
EOF
