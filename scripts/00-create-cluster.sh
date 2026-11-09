#!/usr/bin/env bash
# =============================================================================
# 00-create-cluster.sh — crea el cluster KIND del circuito y el registry local.
# -----------------------------------------------------------------------------
# Idempotente: si el cluster o el registry ya existen, no los recrea.
# Registry: contenedor `kind-registry` (registry:2), accesible desde el host como
# localhost:5001 y desde los nodos (containerd) vía hosts.toml -> kind-registry:5000.
# =============================================================================
source "$(dirname "$0")/lib.sh"

require_all kind kubectl docker

log "Verificando que Docker está en marcha…"
docker info >/dev/null 2>&1 || die "Docker no responde. Arranca Docker Desktop/daemon y reintenta."

# ---- Registry local (receta oficial de KIND) --------------------------------
if [ "$(docker inspect -f '{{.State.Running}}' "${REGISTRY_NAME}" 2>/dev/null || true)" != "true" ]; then
  log "Creando registry local '${REGISTRY_NAME}' (localhost:${REGISTRY_PORT})…"
  docker rm -f "${REGISTRY_NAME}" >/dev/null 2>&1 || true
  docker run -d --restart=always -p "127.0.0.1:${REGISTRY_PORT}:5000" \
    --network bridge --name "${REGISTRY_NAME}" registry:2 >/dev/null
else
  ok "El registry '${REGISTRY_NAME}' ya está en marcha."
fi

# ---- Cluster -----------------------------------------------------------------
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

# ---- Conexión registry <-> nodos ---------------------------------------------
# Mapea localhost:5001 -> kind-registry:5000 en cada nodo (containerd certs.d).
for node in $(kind get nodes --name "${CLUSTER_NAME}"); do
  docker exec "${node}" mkdir -p "/etc/containerd/certs.d/${REGISTRY_HOST}"
  printf '[host."http://%s:5000"]\n' "${REGISTRY_NAME}" \
    | docker exec -i "${node}" tee "/etc/containerd/certs.d/${REGISTRY_HOST}/hosts.toml" >/dev/null
done

# Conecta el registry a la red `kind` si aún no lo está.
if [ "$(docker inspect -f '{{json .NetworkSettings.Networks.kind}}' "${REGISTRY_NAME}")" = "null" ]; then
  docker network connect kind "${REGISTRY_NAME}"
fi
ok "Registry '${REGISTRY_NAME}' conectado a la red kind (${REGISTRY_HOST} en el host)."

log "Contexto de kubectl:"
kubectl cluster-info --context "kind-${CLUSTER_NAME}" | sed 's/^/    /'

ok "Listo. Siguiente paso: scripts/01-install-argocd.sh"
