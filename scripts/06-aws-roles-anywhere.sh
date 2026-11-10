#!/usr/bin/env bash
# =============================================================================
# 06-aws-roles-anywhere.sh — ejecuta comandos de AWS CLI desde FUERA de AWS
# usando IAM Roles Anywhere. Sin Access Keys: `aws_signing_helper` intercambia
# un certificado X.509 por credenciales temporales de STS (1 h, auto-renovables).
#
# La infraestructura (trust anchor, rol, profile) vive en el proyecto Terraform
# ~/Developer/terraform/roles-anywhere (ver su README).
#
# Uso:
#   ./scripts/06-aws-roles-anywhere.sh sts get-caller-identity
#   ./scripts/06-aws-roles-anywhere.sh s3 cp ./backup.tar.gz s3://bucket/backups/
#
# Variables (las RA_* salen de `terraform output env_for_scripts`):
#   RA_TRUST_ANCHOR_ARN, RA_PROFILE_ARN, RA_ROLE_ARN, AWS_REGION   (obligatorias)
#   RA_TF_DIR   proyecto terraform  (default ~/Developer/terraform/roles-anywhere)
#   RA_CERT     certificado cliente (default $RA_TF_DIR/pki/client.crt)
#   RA_KEY      clave privada       (default $RA_TF_DIR/pki/client.key)
#
# Si las RA_* no están definidas, se intentan leer del `terraform output` del
# proyecto (requiere que ya se haya hecho `terraform apply`).
# =============================================================================
source "$(dirname "$0")/lib.sh"

require_all aws aws_signing_helper

[[ $# -gt 0 ]] || die "Uso: $0 <comando aws...>   (ej.: sts get-caller-identity)"

RA_TF_DIR="${RA_TF_DIR:-$HOME/Developer/terraform/roles-anywhere}"
RA_CERT="${RA_CERT:-$RA_TF_DIR/pki/client.crt}"
RA_KEY="${RA_KEY:-$RA_TF_DIR/pki/client.key}"

# Fallback: cargar variables desde terraform output.
if [[ -z "${RA_TRUST_ANCHOR_ARN:-}" || -z "${RA_PROFILE_ARN:-}" || -z "${RA_ROLE_ARN:-}" ]]; then
  require terraform
  log "Cargando RA_* desde terraform output (${RA_TF_DIR})"
  # shellcheck disable=SC1090
  source <(terraform -chdir="$RA_TF_DIR" output -raw env_for_scripts) \
    || die "No pude leer el output de terraform. ¿Hiciste 'terraform apply'?"
fi

: "${RA_TRUST_ANCHOR_ARN:?Falta RA_TRUST_ANCHOR_ARN}"
: "${RA_PROFILE_ARN:?Falta RA_PROFILE_ARN}"
: "${RA_ROLE_ARN:?Falta RA_ROLE_ARN}"
: "${AWS_REGION:?Falta AWS_REGION}"

[[ -r "$RA_CERT" ]] || die "No encuentro el certificado: $RA_CERT"
[[ -r "$RA_KEY"  ]] || die "No encuentro la clave privada: $RA_KEY"

# Perfil temporal: solo existe durante la ejecución, no toca ~/.aws/credentials.
AWS_CONFIG_FILE="$(mktemp)"
export AWS_CONFIG_FILE
trap 'rm -f "$AWS_CONFIG_FILE"' EXIT

cat > "$AWS_CONFIG_FILE" <<EOF
[default]
region = ${AWS_REGION}
credential_process = aws_signing_helper credential-process --certificate ${RA_CERT} --private-key ${RA_KEY} --trust-anchor-arn ${RA_TRUST_ANCHOR_ARN} --profile-arn ${RA_PROFILE_ARN} --role-arn ${RA_ROLE_ARN} --region ${AWS_REGION}
EOF

# Evita que credenciales estáticas del entorno tengan prioridad sobre el helper.
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE

aws "$@"
