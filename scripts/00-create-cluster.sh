#!/usr/bin/env bash
# =============================================================================
# 00-create-cluster.sh — crea el cluster KIND del circuito.
# -----------------------------------------------------------------------------
# Idempotente: si el cluster ya existe, no lo recrea.
# =============================================================================
source "$(dirname "$0")/lib.sh"

require_all kind kubectl docker

log "Verificando que Docker está en marcha…"
docker info >/dev/null 2>&1 || die "Docker no responde. Arranca Docker Desktop/daemon y reintenta."

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  ok "El cluster KIND '${CLUSTER_NAME}' ya existe. Nada que hacer."
else
  log "Creando cluster KIND '${CLUSTER_NAME}'…"
  kind create cluster \
    --name "${CLUSTER_NAME}" \
    --config "${REPO_ROOT}/kind/kind-config.yaml" \
    --wait 120s
  ok "Cluster '${CLUSTER_NAME}' creado."
fi

log "Contexto de kubectl:"
kubectl cluster-info --context "kind-${CLUSTER_NAME}" | sed 's/^/    /'

ok "Listo. Siguiente paso: scripts/01-install-argocd.sh"
