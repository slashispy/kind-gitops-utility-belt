#!/usr/bin/env bash
# =============================================================================
# 02-build-and-push-image.sh — arranque en frío: construye quicktask y
# quicktask-auth y las publica en el registry local (localhost:5001).
# -----------------------------------------------------------------------------
# Solo se usa para tener imágenes `:dev` antes de que exista ningún pipeline.
# Los builds posteriores los hace Tekton (tag = SHA corto del commit).
# =============================================================================
source "$(dirname "$0")/lib.sh"

require docker
docker inspect "${REGISTRY_NAME}" >/dev/null 2>&1 || die "El registry '${REGISTRY_NAME}' no existe. Ejecuta 'make up' primero."

build_and_push() {
  local ref="$1" dir="$2" var="$3"
  [ -f "${dir}/Dockerfile" ] || die "No encuentro el Dockerfile en '${dir}'. Ajusta ${var}."
  log "Construyendo imagen '${ref}' desde '${dir}'…"
  docker build -t "${ref}" "${dir}"
  log "Publicando '${ref}' en el registry local…"
  docker push "${ref}"
  ok "Imagen '${ref}' publicada."
}

build_and_push "${IMAGE_REF}" "${QUICKTASK_DIR}" QUICKTASK_DIR
build_and_push "${AUTH_IMAGE_REF}" "${QUICKTASK_AUTH_DIR}" QUICKTASK_AUTH_DIR

echo "    Siguiente paso: scripts/04-generate-jwt-keys.sh"
