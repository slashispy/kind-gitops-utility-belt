# kind-gitops-utility-belt

Herramientas de bootstrap para levantar el circuito **QuickTask GitOps** completo
en local sobre [KIND](https://kind.sigs.k8s.io/) (Kubernetes IN Docker) con
**Argo CD**. Este repo es el *tooling* del circuito: crea el cluster, instala
Argo CD, carga la imagen de la app y arranca el modelo App of Apps.

Es una de las cinco piezas del circuito:

| Repo | Rol |
|---|---|
| [`quicktask`](https://github.com/slashispy/quicktask) | Aplicación (API Go + MongoDB, JWT). |
| [`helm-chart-generic-app`](https://github.com/slashispy/helm-chart-generic-app) | Helm chart genérico y reutilizable. |
| [`gitops-app-values`](https://github.com/slashispy/gitops-app-values) | Values por app que parametrizan el chart. |
| [`gitops-argocd-apps`](https://github.com/slashispy/gitops-argocd-apps) | App of Apps + ApplicationSet de Argo CD. |
| **`kind-gitops-utility-belt`** | **Bootstrap del cluster y del circuito (este repo).** |

> 📖 **Tutorial detallado paso a paso:** [`docs/tutorial.md`](docs/tutorial.md)
> — qué ejecutar y cómo ver cada pieza funcionando.
> 🌐 **Sitio del proyecto (GitHub Pages):** https://slashispy.github.io/kind-gitops-utility-belt/

## Cómo funciona

```
 make up       ─▶ crea cluster KIND (kind/kind-config.yaml)
 make argocd   ─▶ instala Argo CD (manifiestos oficiales) y espera readiness
 make image    ─▶ docker build quicktask:dev  +  kind load docker-image
 make apps     ─▶ aplica SOLO app-of-apps.yaml (App of Apps)
                        │
                        ▼
      Argo CD reconcilia desde Git:
        root ─▶ AppProject(quicktask) + ApplicationSet
             ─▶ Application(quicktask) = chart genérico + values
             ─▶ Deployment + Service + ConfigMap + Secret + MongoDB (StatefulSet)
```

La imagen se inyecta en KIND con `kind load` (sin registry). El chart usa
`pullPolicy: IfNotPresent` y el tag fijo `dev`, de modo que el cluster usa esa
imagen local. La evolución a un registry real está descrita en
[`ci/pipeline.md`](ci/pipeline.md).

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

`make bootstrap` encadena `up → argocd → image → apps`. Cuando la Application
`quicktask` aparezca **Synced / Healthy**, la app está desplegada.

### Acceder a la app

```bash
kubectl -n quicktask port-forward svc/quicktask 9090:8080
curl -fsS http://localhost:9090/health   # -> {"status":"ok"}
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

# 3) Construir la imagen de quicktask y cargarla en KIND
./scripts/02-build-and-load-image.sh

# 4) Aplicar la App of Apps (único manifiesto aplicado a mano)
./scripts/03-bootstrap-apps.sh

# 5) Observar
kubectl -n argocd get applications
kubectl -n quicktask get pods -w
```

## Targets del Makefile

| Target | Acción |
|---|---|
| `make up` | Crea el cluster KIND. |
| `make argocd` | Instala Argo CD y espera readiness. |
| `make image` | Build de `quicktask:dev` + `kind load`. |
| `make apps` | Aplica la App of Apps. |
| `make bootstrap` | `up + argocd + image + apps`. |
| `make status` | Applications, pods y servicios + comandos de port-forward. |
| `make down` | Elimina el cluster KIND. |

## Configuración (variables de entorno)

Los scripts leen estas variables (con valores por defecto en `scripts/lib.sh`):

| Variable | Default | Descripción |
|---|---|---|
| `CLUSTER_NAME` | `quicktask-gitops` | Nombre del cluster KIND. |
| `ARGOCD_VERSION` | `stable` | Tag/branch de `argo-cd/install.yaml`. |
| `IMAGE_NAME` / `IMAGE_TAG` | `quicktask` / `dev` | Imagen de la app. |
| `QUICKTASK_DIR` | `~/Developer/go/proyectos/quicktask` | Ruta local del repo de la app (para `docker build`). |
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
│   ├── 02-build-and-load-image.sh
│   ├── 03-bootstrap-apps.sh
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
- **`quicktask` queda en `ImagePullBackOff`**: la imagen no está en el cluster.
  Re-ejecuta `make image` (build + `kind load`) y comprueba el tag `dev`.
- **La Application no aparece**: revisa que el `ApplicationSet` esté creado
  (`kubectl -n argocd get applicationsets`) y que el repo `gitops-app-values`
  sea accesible (es público).
- **Mongo no arranca**: comprueba el PVC (`kubectl -n quicktask get pvc`) y los
  eventos (`kubectl -n quicktask describe pod <mongodb-pod>`).
- **Reset total**: `make down && make bootstrap`.
