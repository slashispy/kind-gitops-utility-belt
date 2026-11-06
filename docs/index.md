---
layout: default
title: QuickTask GitOps Circuit
---

# QuickTask GitOps Circuit

Un circuito **GitOps completo y reproducible en local**: una API en Go con
MongoDB desplegada en Kubernetes (KIND) por **Argo CD**, usando un **Helm chart
genérico reutilizable** y el patrón **App of Apps + ApplicationSet**.

Con `make bootstrap` pasas de una máquina con Docker a una aplicación corriendo,
sincronizada desde Git y con auto-reparación.

**[→ Ir al tutorial paso a paso](./tutorial)**

---

## La idea en una imagen

```
   Desarrollador
        │  make bootstrap   (kind-gitops-utility-belt)
        ▼
 ┌──────────────────────── Cluster KIND ─────────────────────────┐
 │                                                                 │
 │  Argo CD                                                        │
 │    │  root  (App of Apps)  ◀── gitops-argocd-apps               │
 │    │    ├─ AppProject  quicktask                                │
 │    │    └─ ApplicationSet ── lee ──▶ gitops-app-values          │
 │    │                                   apps/*/metadata.yaml     │
 │    │                 genera ▼                                   │
 │    │    Application  quicktask                                  │
 │    │      chart  = helm-chart-generic-app                       │
 │    │      values = gitops-app-values/apps/quicktask/values.yaml │
 │    ▼                                                            │
 │  namespace quicktask                                            │
 │    ├─ Deployment quicktask   (probes /health y /ready)          │
 │    ├─ Service ClusterIP :8080                                   │
 │    ├─ ConfigMap  · Secret                                       │
 │    └─ StatefulSet MongoDB + Service headless + PVC              │
 └─────────────────────────────────────────────────────────────────┘
```

## Los 5 repositorios

Cada repo tiene una única responsabilidad (separación estricta de
responsabilidades):

| Repo | Responsabilidad |
|---|---|
| [`quicktask`](https://github.com/slashispy/quicktask) | **Aplicación.** API Go 1.25 con MongoDB, JWT, `/health` y `/ready`, tests unitarios y de integración (testcontainers) y CI en GitHub Actions. |
| [`helm-chart-generic-app`](https://github.com/slashispy/helm-chart-generic-app) | **Chart genérico.** Despliega cualquier app stateless parametrizada por values; MongoDB opcional; `values.schema.json` valida el contrato. No conoce `quicktask`. |
| [`gitops-app-values`](https://github.com/slashispy/gitops-app-values) | **Configuración por app.** `apps/<app>/{values.yaml,metadata.yaml}`. Añadir una app = añadir una carpeta. |
| [`gitops-argocd-apps`](https://github.com/slashispy/gitops-argocd-apps) | **Orquestación Argo CD.** App of Apps, AppProject y ApplicationSet con git files generator. |
| [`kind-gitops-utility-belt`](https://github.com/slashispy/kind-gitops-utility-belt) | **Bootstrap (este repo).** Cluster KIND, instalación de Argo CD, carga de imagen, Makefile y este sitio. |

## Cómo fluye un despliegue

1. **`make up`**: crea el cluster KIND.
2. **`make argocd`**: instala Argo CD con server-side apply.
3. **`make image`**: construye `quicktask:dev` y lo carga en el nodo (`kind load`).
4. **`make apps`**: aplica *un solo manifiesto*, la Application `root`.
5. Desde ahí **Argo CD lo reconcilia todo desde Git**: proyecto, ApplicationSet,
   Application y los recursos de Kubernetes.

Después de ese primer `kubectl apply`, el cluster no se toca a mano: si alguien
cambia algo, el *self-heal* lo revierte; si cambia Git, Argo CD lo aplica.

## Decisiones de diseño

- **Un chart genérico, muchas apps.** La diferencia entre aplicaciones vive en
  los *values*, no en copias del chart. Esto es el núcleo del patrón de
  reutilización.
- **Values en un repo aparte.** Cambiar configuración no implica tocar el chart,
  y el chart se versiona independientemente.
- **ApplicationSet con múltiples sources.** El chart y los values viven en repos
  distintos; Argo CD los une con `$values`. Añadir una app no requiere editar
  manifiestos de Argo CD.
- **App of Apps como único punto de entrada.** Un solo `kubectl apply` arranca
  todo; el resto es declarativo.
- **Imagen local sin registry.** `kind load` + `pullPolicy: IfNotPresent` + tag
  `dev` mantienen la demo autocontenida. La evolución a GHCR con tags inmutables
  está en [`ci/pipeline.md`](https://github.com/slashispy/kind-gitops-utility-belt/blob/main/ci/pipeline.md).
- **Readiness real.** `/ready` hace ping a MongoDB; `/health` solo indica que el
  proceso vive. Cada probe usa el endpoint adecuado.
- **Sin secretos reales.** Los valores del Secret son de demostración y están
  señalados como tales; en producción irían por External Secrets o SOPS.

## Qué demuestra este proyecto

- Kubernetes y Helm (templates, helpers, schema de values, toggles opcionales).
- GitOps con Argo CD: App of Apps, ApplicationSet, AppProject, sync automática,
  prune y self-heal.
- Automatización reproducible: scripts idempotentes y Makefile.
- Testing y CI de la aplicación: unitarios, integración con Docker, `-race`,
  cobertura y build de imagen.
- Documentación orientada a que un tercero pueda reproducirlo.

## Probarlo

```bash
git clone https://github.com/slashispy/kind-gitops-utility-belt
git clone https://github.com/slashispy/quicktask
cd kind-gitops-utility-belt
make bootstrap     # up + argocd + image + apps
make status
```

Requisitos: Docker, kind, kubectl y make. El detalle, con qué mirar en cada paso,
está en el **[tutorial](./tutorial)**.

## Fuera de alcance (deuda consciente)

Registry remoto (GHCR) y firmado de imágenes, gestión real de secretos, TLS con
cert-manager, observabilidad y multi-cluster. Son incrementales: el modelo GitOps
no cambia, solo se enriquecen los extremos.

---

Autor: [@slashispy](https://github.com/slashispy)
