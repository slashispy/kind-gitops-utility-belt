#!/usr/bin/env bash
# =============================================================================
# 02-build-and-load-image.sh — construye la imagen de quicktask y la carga en
# el cluster KIND (sin registry remoto).
# -----------------------------------------------------------------------------
# El chart usa pullPolicy: IfNotPresent y el tag fijo `dev`, de modo que KIND
# usa esta imagen local cargada en los nodos.
# =============================================================================
source "$(dirname "$0")/lib.sh"

require_all docker kind

[ -f "${QUICKTASK_DIR}/Dockerfile" ] || die "No encuentro el Dockerfile en '${QUICKTASK_DIR}'. Ajusta QUICKTASK_DIR."

log "Construyendo imagen '${IMAGE_REF}' desde '${QUICKTASK_DIR}'…"
docker build -t "${IMAGE_REF}" "${QUICKTASK_DIR}"

log "Cargando '${IMAGE_REF}' en el cluster KIND '${CLUSTER_NAME}'…"
kind load docker-image "${IMAGE_REF}" --name "${CLUSTER_NAME}"

ok "Imagen '${IMAGE_REF}' disponible en el cluster."
echo "    Siguiente paso: scripts/03-bootstrap-apps.sh"
