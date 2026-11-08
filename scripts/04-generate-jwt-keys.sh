#!/usr/bin/env bash
# =============================================================================
# 04-generate-jwt-keys.sh — crea en el cluster los Secrets que necesita el
# flujo de autenticación. NADA de esto se versiona en Git.
# -----------------------------------------------------------------------------
#   quicktask-auth-keys         private.pem   clave PRIVADA RSA (solo quicktask-auth)
#   quicktask-jwt-public        public.pem    clave PÚBLICA (la valida quicktask)
#   quicktask-auth-demo-client  client-id, client-secret (en claro, para la demo),
#                               secret-hash (bcrypt; lo lee quicktask-auth)
#
# Idempotente: si los Secrets ya existen no se tocan (los tokens emitidos siguen
# siendo válidos). Para regenerar todo:  FORCE=1 scripts/04-generate-jwt-keys.sh
# Debe ejecutarse ANTES de `make apps` (o los pods quedan en ContainerCreating
# hasta que existan los Secrets).
# =============================================================================
source "$(dirname "$0")/lib.sh"

require_all kubectl openssl docker

kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null

SECRETS=(quicktask-auth-keys quicktask-jwt-public quicktask-auth-demo-client)

# El namespace lo crea también Argo CD (CreateNamespace=true); aquí se adelanta.
kubectl create namespace "${APP_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

if [ "${FORCE:-0}" = "1" ]; then
  log "FORCE=1: eliminando Secrets previos…"
  kubectl -n "${APP_NAMESPACE}" delete secret "${SECRETS[@]}" --ignore-not-found >/dev/null
fi

existing="$(kubectl -n "${APP_NAMESPACE}" get secret -o name | grep -cE "secret/(quicktask-auth-keys|quicktask-jwt-public|quicktask-auth-demo-client)$" || true)"
if [ "${existing}" = "3" ]; then
  ok "Los Secrets JWT ya existen en '${APP_NAMESPACE}'. Nada que hacer (FORCE=1 para regenerar)."
  exit 0
fi
# Estado parcial: se parte de cero para mantener las claves consistentes.
kubectl -n "${APP_NAMESPACE}" delete secret "${SECRETS[@]}" --ignore-not-found >/dev/null

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

log "Generando par de claves RSA 2048 (PKCS#8)…"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "${WORK}/private.pem" 2>/dev/null
openssl pkey -in "${WORK}/private.pem" -pubout -out "${WORK}/public.pem"

log "Generando credenciales del cliente de demo…"
CLIENT_ID="demo"
CLIENT_SECRET="$(openssl rand -hex 16)"
# bcrypt con htpasswd (imagen httpd, así no depende de herramientas locales).
# htpasswd emite $2y$; Quarkus/Elytron espera $2a$ (son equivalentes).
RAW_HASH="$(docker run --rm httpd:2.4-alpine htpasswd -nbBC 10 "" "${CLIENT_SECRET}")"
SECRET_HASH="$(printf '%s' "${RAW_HASH}" | tr -d ':\n' | sed 's/^\$2y/$2a/')"
[ -n "${SECRET_HASH}" ] || die "No se pudo generar el hash bcrypt."

log "Creando Secrets en el namespace '${APP_NAMESPACE}'…"
kubectl -n "${APP_NAMESPACE}" create secret generic quicktask-auth-keys \
  --from-file=private.pem="${WORK}/private.pem" >/dev/null
kubectl -n "${APP_NAMESPACE}" create secret generic quicktask-jwt-public \
  --from-file=public.pem="${WORK}/public.pem" >/dev/null
kubectl -n "${APP_NAMESPACE}" create secret generic quicktask-auth-demo-client \
  --from-literal=client-id="${CLIENT_ID}" \
  --from-literal=client-secret="${CLIENT_SECRET}" \
  --from-literal=secret-hash="${SECRET_HASH}" >/dev/null

ok "Secrets creados."
cat <<EOF

  Pide un token y llama a quicktask (cuando ambas apps estén Healthy):

    kubectl -n ${APP_NAMESPACE} port-forward svc/quicktask-auth 9092:8080 &
    kubectl -n ${APP_NAMESPACE} port-forward svc/quicktask 9090:8080 &
    TOKEN=\$(scripts/token.sh)
EOF
