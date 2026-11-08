#!/usr/bin/env bash
# =============================================================================
# token.sh — pide un JWT al servicio quicktask-auth con el cliente de demo y lo
# imprime por stdout. Requiere el port-forward de quicktask-auth en el puerto
# AUTH_LOCAL_PORT (por defecto 9092):
#   kubectl -n quicktask port-forward svc/quicktask-auth 9092:8080
# Uso:  TOKEN=$(scripts/token.sh)
# =============================================================================
source "$(dirname "$0")/lib.sh"

require_all kubectl curl python3

AUTH_LOCAL_PORT="${AUTH_LOCAL_PORT:-9092}"
get() { kubectl -n "${APP_NAMESPACE}" get secret quicktask-auth-demo-client -o "jsonpath={.data.$1}" | base64 --decode; }

CLIENT_ID="$(get client-id)"
CLIENT_SECRET="$(get client-secret)"

curl -fsS -X POST "http://localhost:${AUTH_LOCAL_PORT}/v1/auth/token" \
  -H 'Content-Type: application/json' \
  -d "{\"grant_type\":\"client_credentials\",\"client_id\":\"${CLIENT_ID}\",\"client_secret\":\"${CLIENT_SECRET}\"}" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])'
