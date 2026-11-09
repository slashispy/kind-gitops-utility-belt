#!/usr/bin/env bash
# =============================================================================
# 99-teardown.sh — elimina el cluster KIND del circuito y su registry local.
# -----------------------------------------------------------------------------
# Destruye TODO el estado (cluster, Argo CD, apps, datos de Mongo, imágenes del
# registry). Solo toca este cluster KIND y el contenedor `kind-registry`.
# =============================================================================
source "$(dirname "$0")/lib.sh"

require_all kind docker

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  log "Eliminando cluster KIND '${CLUSTER_NAME}'…"
  kind delete cluster --name "${CLUSTER_NAME}"
  ok "Cluster '${CLUSTER_NAME}' eliminado."
else
  warn "El cluster '${CLUSTER_NAME}' no existe. Nada que eliminar."
fi

if docker inspect "${REGISTRY_NAME}" >/dev/null 2>&1; then
  log "Eliminando registry local '${REGISTRY_NAME}'…"
  docker rm -f "${REGISTRY_NAME}" >/dev/null
  ok "Registry '${REGISTRY_NAME}' eliminado."
fi
