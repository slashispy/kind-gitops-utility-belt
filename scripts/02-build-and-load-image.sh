#!/usr/bin/env bash
# =============================================================================
# 02-build-and-load-image.sh — construye las imágenes de quicktask y de
# quicktask-auth y las carga en el cluster KIND (sin registry remoto).
# -----------------------------------------------------------------------------
# El chart usa pullPolicy: IfNotPresent y el tag fijo `dev`, de modo que KIND
# usa estas imágenes locales cargadas en los nodos.
# =============================================================================
source "$(dirname "$0")/lib.sh"

require_all docker kind

build_and_load() {
  local ref="$1" dir="$2" var="$3"
  [ -f "${dir}/Dockerfile" ] || die "No encuentro el Dockerfile en '${dir}'. Ajusta ${var}."
  log "Construyendo imagen '${ref}' desde '${dir}'…"
  docker build -t "${ref}" "${dir}"
  log "Cargando '${ref}' en el cluster KIND '${CLUSTER_NAME}'…"
  kind load docker-image "${ref}" --name "${CLUSTER_NAME}"
  ok "Imagen '${ref}' disponible en el cluster."
}

build_and_load "${IMAGE_REF}" "${QUICKTASK_DIR}" QUICKTASK_DIR
build_and_load "${AUTH_IMAGE_REF}" "${QUICKTASK_AUTH_DIR}" QUICKTASK_AUTH_DIR

echo "    Siguiente paso: scripts/04-generate-jwt-keys.sh"
