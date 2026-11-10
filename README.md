# kind-gitops-utility-belt

Herramientas de bootstrap para levantar el circuito **QuickTask GitOps** completo
en local sobre [KIND](https://kind.sigs.k8s.io/) (Kubernetes IN Docker) con
**Argo CD**. Este repo es el *tooling* del circuito: crea el cluster, instala
Argo CD, carga las imágenes de las apps, genera las claves JWT y arranca el modelo App of Apps.

Es una de las seis piezas del circuito:

| Repo | Rol |
|---|---|
| [`quicktask`](https://github.com/slashispy/quicktask) | Aplicación (API Go + MongoDB), valida JWT. |
| [`quicktask-auth`](https://github.com/slashispy/quicktask-auth) | Emisor de JWT (Quarkus, client credentials, RS256). |
| [`helm-chart-generic-app`](https://github.com/slashispy/helm-chart-generic-app) | Helm chart genérico y reutilizable. |
| [`gitops-app-values`](https://github.com/slashispy/gitops-app-values) | Values por app que parametrizan el chart. |
| [`gitops-argocd-apps`](https://github.com/slashispy/gitops-argocd-apps) | App of Apps + ApplicationSet de Argo CD. |
| **`kind-gitops-utility-belt`** | **Bootstrap del cluster y del circuito (este repo).** |

> 📖 **Tutorial detallado paso a paso:** [`docs/tutorial.md`](docs/tutorial.md)
> — qué ejecutar y cómo ver cada pieza funcionando.
> 🌐 **Sitio del proyecto (GitHub Pages):** https://slashispy.github.io/kind-gitops-utility-belt/

## Cómo funciona

```
 make up       ─▶ crea cluster KIND (kind/kind-config.yaml) + registry local localhost:5001
 make argocd   ─▶ instala Argo CD (manifiestos oficiales) y espera readiness
 make image    ─▶ docker build + docker push localhost:5001/{quicktask,quicktask-auth}:dev
 make keys     ─▶ par RSA + cliente demo -> Secrets del cluster (NO van a Git)
 make apps     ─▶ aplica SOLO app-of-apps.yaml (App of Apps)
                        │
                        ▼
      Argo CD reconcilia desde Git:
        root ─▶ AppProject(quicktask) + ApplicationSet
             ─▶ Application(quicktask)      = chart genérico + values
             ─▶ Application(quicktask-auth) = chart genérico + values
             ─▶ Deployment + Service + ConfigMap + Secret (+ MongoDB para quicktask)
```

### Flujo de autenticación

`quicktask-auth` (Quarkus) emite JWT RS256 por *client credentials*; `quicktask`
los valida con la **clave pública**. La clave privada solo la ve `quicktask-auth`.

```
 cliente ── client_id + client_secret ──▶ quicktask-auth ── JWT (firma con clave PRIVADA)
 cliente ── Authorization: Bearer JWT ──▶ quicktask       (valida con clave PÚBLICA)
```

`make keys` crea tres Secrets en el namespace `quicktask`
(`quicktask-auth-keys`, `quicktask-jwt-public`, `quicktask-auth-demo-client`).
Son los únicos datos sensibles del circuito y **no se versionan**: los values
de Git solo referencian los Secrets por nombre.

Las imágenes se publican en un **registry local** (contenedor `kind-registry`,
`registry:2`) conectado a la red `kind`. Desde el host es `localhost:5001`; los
nodos resuelven `localhost:5001` hacia `kind-registry:5000` mediante
`/etc/containerd/certs.d/localhost:5001/hosts.toml` (lo escribe
`00-create-cluster.sh`, junto con `containerdConfigPatches` en
`kind/kind-config.yaml`). Los values referencian `localhost:5001/<app>:<tag>`.
`make image` publica el tag `dev` de arranque en frío; luego el CI (Tekton)
publicará tags inmutables por SHA. Ver [`ci/pipeline.md`](ci/pipeline.md).

## Requisitos

| Herramienta | Uso |
|---|---|
| [Docker](https://docs.docker.com/get-docker/) | Runtime de los nodos KIND y build de la imagen. |
| [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) | Cluster de Kubernetes local. |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | Interacción con el cluster. |
| `make`, `bash` | Orquestación de los scripts. |

Verificadas con: kind v0.33, kubectl v1.36, Kubernetes 1.3x. No requiere `helm`
en local (Argo CD renderiza el chart dentro del cluster).

## Uso rápido (automatizado)

```bash
# Circuito completo de cero:
make bootstrap

# Ver el estado:
make status
```

`make bootstrap` encadena `up → argocd → image → keys → apps`. Cuando las
Applications `quicktask` y `quicktask-auth` aparezcan **Synced / Healthy**, el
circuito está desplegado.

### Acceder a la app

```bash
kubectl -n quicktask port-forward svc/quicktask 9090:8080
curl -fsS http://localhost:9090/health   # -> {"status":"ok"}
```

### Obtener un token y llamar a la API protegida

```bash
kubectl -n quicktask port-forward svc/quicktask-auth 9092:8080 &   # emisor de JWT
TOKEN=$(scripts/token.sh)                                           # cliente "demo"

curl -i -X POST http://localhost:9090/v1/users \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"name":"Ada","email":"ada@example.com","password":"supersecret123"}'
# HTTP/1.1 201 Created   (sin token o con token adulterado: 401)
```

### Acceder a la UI de Argo CD

```bash
# contraseña inicial de admin:
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo

kubectl -n argocd port-forward svc/argocd-server 9091:443
# abrir https://localhost:9091  (usuario: admin)
```

### Limpiar

```bash
make down    # elimina el cluster KIND y todo su estado
```

## Uso manual (paso a paso)

Si prefieres entender cada paso o no usar `make`:

```bash
# 1) Crear el cluster KIND
./scripts/00-create-cluster.sh

# 2) Instalar Argo CD y esperar a que esté listo
./scripts/01-install-argocd.sh

# 3) Construir las imágenes (quicktask y quicktask-auth) y publicarlas en localhost:5001
./scripts/02-build-and-push-image.sh

# 4) Generar las claves JWT y el cliente demo (Secrets, fuera de Git)
./scripts/04-generate-jwt-keys.sh

# 5) Aplicar la App of Apps (único manifiesto aplicado a mano)
./scripts/03-bootstrap-apps.sh

# 6) Observar
kubectl -n argocd get applications
kubectl -n quicktask get pods -w
```

## Targets del Makefile

| Target | Acción |
|---|---|
| `make up` | Crea el cluster KIND y el registry local (`localhost:5001`). |
| `make argocd` | Instala Argo CD y espera readiness. |
| `make image` | Build de `quicktask` y `quicktask-auth` (`:dev`) + `docker push` a `localhost:5001`. |
| `make keys` | Crea los Secrets JWT (par RSA + cliente demo). Idempotente; `FORCE=1` regenera. |
| `make apps` | Aplica la App of Apps. |
| `make bootstrap` | `up + argocd + image + keys + apps`. |
| `make status` | Applications, pods y servicios + comandos de port-forward. |
| `make aws-ra ARGS="..."` | Ejecuta AWS CLI desde fuera de AWS con IAM Roles Anywhere (sin Access Keys). Ver abajo. |
| `make down` | Elimina el cluster KIND. |

### AWS sin Access Keys (IAM Roles Anywhere)

`scripts/06-aws-roles-anywhere.sh` ejecuta cualquier comando `aws` con credenciales
temporales de STS obtenidas con un certificado X.509 (`aws_signing_helper`), sin
guardar Access Keys. La infraestructura (trust anchor, rol de mínimo privilegio,
profile) está en el proyecto Terraform `~/Developer/terraform/roles-anywhere`.

```bash
make aws-ra ARGS="sts get-caller-identity"
make aws-ra ARGS="s3 cp ./backup.tar.gz s3://mi-bucket/backups/"
```

Requiere `aws` CLI v2 y [`aws_signing_helper`](https://docs.aws.amazon.com/rolesanywhere/latest/userguide/credential-helper.html).
Variables: `RA_TF_DIR`, `RA_CERT`, `RA_KEY` (y `RA_*_ARN` / `AWS_REGION`, que por defecto se leen de `terraform output`).

## Configuración (variables de entorno)

Los scripts leen estas variables (con valores por defecto en `scripts/lib.sh`):

| Variable | Default | Descripción |
|---|---|---|
| `CLUSTER_NAME` | `quicktask-gitops` | Nombre del cluster KIND. |
| `ARGOCD_VERSION` | `stable` | Tag/branch de `argo-cd/install.yaml`. |
| `IMAGE_NAME` / `IMAGE_TAG` | `quicktask` / `dev` | Imagen de la app. |
| `QUICKTASK_DIR` | `~/Developer/go/proyectos/quicktask` | Ruta local del repo de la app (para `docker build`). |
| `QUICKTASK_AUTH_DIR` | `~/Developer/java/proyectos/quicktask-auth` | Ruta local del repo del emisor de JWT. |
| `AUTH_IMAGE_NAME` | `quicktask-auth` | Imagen del emisor de JWT (mismo `IMAGE_TAG`). |
| `ARGOCD_APPS_REPO` | `https://github.com/slashispy/gitops-argocd-apps` | Repo de la App of Apps. |
| `ARGOCD_APPS_REF` | `main` | Revisión del repo de Argo CD apps. |
| `APP_NAMESPACE` | `quicktask` | Namespace de la app. |

Ejemplo: build desde otra ruta:

```bash
QUICKTASK_DIR=/ruta/a/quicktask make image
```

## Estructura del repo

```
kind-gitops-utility-belt/
├── README.md
├── Makefile                      # orquesta los scripts
├── kind/
│   └── kind-config.yaml          # cluster 1 nodo + port mappings
├── scripts/
│   ├── lib.sh                    # config + helpers compartidos
│   ├── 00-create-cluster.sh
│   ├── 01-install-argocd.sh
│   ├── 02-build-and-push-image.sh
│   ├── 03-bootstrap-apps.sh
│   ├── 04-generate-jwt-keys.sh   # Secrets JWT (par RSA + cliente demo)
│   ├── 06-aws-roles-anywhere.sh  # AWS CLI sin Access Keys (IAM Roles Anywhere)
│   ├── token.sh                  # pide un JWT al cliente demo
│   ├── status.sh
│   └── 99-teardown.sh
├── ci/
│   └── pipeline.md               # evolución a CI/CD real con registry
└── docs/                         # sitio GitHub Pages (Jekyll)
    ├── _config.yml
    ├── index.md                  # visión end-to-end del proyecto
    └── tutorial.md               # tutorial paso a paso
```

## Resolución de problemas

- **`Too long: may not be more than 262144 bytes` al instalar Argo CD**: ya
  resuelto en el script (usa `kubectl apply --server-side`).
- **`address already in use` en `port-forward`**: 8080/8081 los reserva KIND;
  usa 9090 (app) y 9091 (Argo CD).
- **`quicktask` o `quicktask-auth` en `ImagePullBackOff`**: la imagen no está en el registry.
  Comprueba `curl localhost:5001/v2/_catalog` y re-ejecuta `make image`. Si el
  registry no existe o los nodos no lo resuelven, recrea con `make down && make up`
  (el `containerdConfigPatches` solo se aplica al crear el cluster).
- **Pods en `ContainerCreating` (`secret ... not found`)**: faltan los Secrets JWT.
  Ejecuta `make keys`.
- **`401` con un token recién emitido**: las claves se regeneraron (`FORCE=1`) sin
  reiniciar `quicktask`. Haz `kubectl -n quicktask rollout restart deploy quicktask quicktask-auth`.
- **La Application no aparece**: revisa que el `ApplicationSet` esté creado
  (`kubectl -n argocd get applicationsets`) y que el repo `gitops-app-values`
  sea accesible (es público).
- **Mongo no arranca**: comprueba el PVC (`kubectl -n quicktask get pvc`) y los
  eventos (`kubectl -n quicktask describe pod <mongodb-pod>`).
- **Reset total**: `make down && make bootstrap`.
