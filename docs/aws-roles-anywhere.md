---
layout: default
title: AWS sin Access Keys (IAM Roles Anywhere)
---

# AWS sin Access Keys: IAM Roles Anywhere

[← Volver al inicio](./)

Un workload **fuera de AWS** (on-prem, VM, otro cloud, CI) necesita usar S3. En vez de
crear un usuario IAM con Access Key + Secret de larga duración, el workload se autentica
con un **certificado X.509** y recibe **credenciales temporales de STS** (1 hora,
renovables). No hay secretos estáticos que rotar, filtrar ni guardar en un repo.

## Flujo de autenticación

```
  WORKLOAD EXTERNO (on-prem / VM / CI)                         AWS
 ┌──────────────────────────────────┐        ┌────────────────────────────────────────────┐
 │  client.crt  (cert X.509)        │        │                                            │
 │  client.key  (clave privada,     │        │   IAM Roles Anywhere                       │
 │               nunca sale)        │        │   ┌──────────────────────────────────┐     │
 │                                  │        │   │ Trust Anchor = tu CA / PKI       │     │
 │  aws CLI / SDK                   │        │   │ Profile      = roles permitidos  │     │
 │      │ necesita credenciales     │        │   └──────────────────────────────────┘     │
 │      ▼                           │        │                                            │
 │  aws_signing_helper              │        │                                            │
 │  (credential_process)            │        │                                            │
 └──────────────┬───────────────────┘        └────────────────────────────────────────────┘
                │
                │ 1) CreateSession firmada con client.key
                │    + cadena de certificados en la petición
                ▼
        ┌─────────────────────────┐   2) ¿El cert está firmado por el Trust Anchor?
        │   IAM Roles Anywhere    │      ¿vigente? ¿no revocado (CRL)?
        └───────────┬─────────────┘   3) ¿Trust policy del rol OK?
                    │                    · Principal = rolesanywhere.amazonaws.com
                    │                    · aws:SourceArn = este Trust Anchor
                    │                    · x509Subject/CN ∈ CNs permitidos
                    ▼
        ┌─────────────────────────┐
        │   STS  AssumeRole       │   4) Emite credenciales temporales (1 h)
        └───────────┬─────────────┘      AccessKeyId + SecretKey + SessionToken
                    │
                    │ 5) credenciales temporales de vuelta al workload
                    ▼
        ┌─────────────────────────┐
        │  Workload  ──▶  S3      │   6) PutObject con las credenciales temporales
        └───────────┬─────────────┘
                    ▼
        ┌─────────────────────────────────────────────────────────────────┐
        │ IAM evalúa: política del rol  ∩  session policy del Profile     │
        │   ✔ s3:PutObject  en  arn:aws:s3:::bucket/backups/*             │
        │   ✘ cualquier otra acción o recurso  → AccessDenied             │
        └─────────────────────────────────────────────────────────────────┘
                    │
                    ▼
            CloudTrail registra CreateSession + cada llamada a S3   (auditoría)
```

## Qué controles aplica

| Control | Dónde |
|---|---|
| Sin credenciales estáticas | Sesiones STS de 1 hora, renovadas por `aws_signing_helper` |
| Identidad del workload | Certificado X.509 firmado por tu CA; la clave privada no sale del host |
| Quién puede asumir el rol | Trust policy: servicio `rolesanywhere.amazonaws.com` + `aws:SourceArn` del Trust Anchor + CN del certificado |
| Mínimo privilegio | Solo `PutObject` bajo un prefijo y `ListBucket` con condición `s3:prefix` |
| Doble tope de permisos | Session policy en el Profile (intersección con la política del rol) |
| Revocación | CRL en el Trust Anchor; certificados de vida corta |
| Auditoría | CloudTrail: `CreateSession` y llamadas a S3 |

## Las dos piezas

- **Infraestructura (Terraform):** Trust Anchor, rol IAM, política y Profile. Repo
  [`terraform-roles-anywhere`](https://github.com/slashispy/terraform-roles-anywhere) (provider AWS `~> 6.0`).
- **Ejecución desde fuera de AWS (este repo):** [`scripts/06-aws-roles-anywhere.sh`](https://github.com/slashispy/kind-gitops-utility-belt/blob/main/scripts/06-aws-roles-anywhere.sh).

```bash
# Verifica qué rol se asumió (sin ninguna Access Key en el entorno)
make aws-ra ARGS="sts get-caller-identity"

# Sube un backup con credenciales temporales
make aws-ra ARGS="s3 cp ./backup.tar.gz s3://mi-bucket/backups/"
```

El script usa un perfil de AWS CLI temporal con `credential_process`, así que no escribe
en `~/.aws/credentials`, y descarta cualquier `AWS_ACCESS_KEY_ID` del entorno para que
no tenga prioridad sobre el helper.

## Qué falta para producción (deuda consciente)

- Emitir certificados con AWS Private CA, Vault PKI o cert-manager, con renovación automática.
- Publicar la CRL para revocar certificados comprometidos.
- Alarma ante `CreateSession` desde CNs o IPs inesperados.
- Estado remoto de Terraform (S3 + lock) y escaneo con Checkov/tfsec en el pipeline.
- Bucket cifrado con KMS y S3 Block Public Access.

> Nota: la PKI que se genera en el repo es solo de laboratorio. El flujo completo se
> validó a nivel de sintaxis y `terraform validate`; no se ejecutó contra una cuenta real de AWS.
