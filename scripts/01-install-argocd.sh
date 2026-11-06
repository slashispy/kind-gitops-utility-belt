#!/usr/bin/env bash
# =============================================================================
# 01-install-argocd.sh — instala Argo CD con los manifiestos oficiales y espera
# a que los Deployments estén disponibles.
# -----------------------------------------------------------------------------
# Idempotente: `kubectl apply` se puede re-ejecutar sin efectos adversos.
# =============================================================================
source "$(dirname "$0")/lib.sh"

require_all kubectl kind

# Asegura que apuntamos al cluster correcto.
kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null

log "Creando namespace '${ARGOCD_NAMESPACE}'…"
kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

MANIFEST="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
log "Instalando Argo CD (${ARGOCD_VERSION}) desde: ${MANIFEST}"
# Server-side apply: el CRD de ApplicationSets supera los 256 KB que admite la
# anotación last-applied-configuration del apply cliente. --force-conflicts
# permite re-ejecutar el script tras un intento fallido previo.
kubectl apply --server-side --force-conflicts -n "${ARGOCD_NAMESPACE}" -f "${MANIFEST}"

log "Esperando a que los Deployments de Argo CD estén disponibles (hasta 5 min)…"
kubectl -n "${ARGOCD_NAMESPACE}" wait --for=condition=Available deployment --all --timeout=300s

ok "Argo CD instalado y listo."
cat <<EOF

  Contraseña inicial de admin:
    kubectl -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret \\
      -o jsonpath='{.data.password}' | base64 -d; echo

  Acceder a la UI (en otra terminal):
    kubectl -n ${ARGOCD_NAMESPACE} port-forward svc/argocd-server 9091:443
    # abrir https://localhost:9091  (usuario: admin)

Siguiente paso: scripts/02-build-and-load-image.sh
EOF
