#!/usr/bin/env bash
# =============================================================================
# 99-teardown.sh — elimina el cluster KIND del circuito.
# -----------------------------------------------------------------------------
# Destruye TODO el estado (cluster, Argo CD, apps, datos de Mongo). El PVC vive
# dentro del nodo KIND, así que se pierde con el cluster. Operación segura:
# no toca nada fuera de este cluster KIND.
# =============================================================================
source "$(dirname "$0")/lib.sh"

require kind

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  log "Eliminando cluster KIND '${CLUSTER_NAME}'…"
  kind delete cluster --name "${CLUSTER_NAME}"
  ok "Cluster '${CLUSTER_NAME}' eliminado."
else
  warn "El cluster '${CLUSTER_NAME}' no existe. Nada que eliminar."
fi
