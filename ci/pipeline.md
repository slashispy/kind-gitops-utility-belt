# Pipeline — del registry local a un circuito GitOps "real"

Este documento describe cómo evolucionar la demo (registry local en KIND) hacia un **circuito CI/CD real** con registry remoto, sin cambiar
el modelo GitOps. Es el "paso siguiente" natural del portfolio.

## Dónde estamos (demo en KIND con registry local)

```
 dev ── docker build/push ──> kind-registry (localhost:5001) ──> cluster KIND
                                                                      │
 Argo CD  ◀── reconcilia ── Git (chart + values + argo apps) ─────────┘
```

- La imagen se publica en un registry local conectado a la red de KIND
  (`localhost:5001` en el host, `kind-registry:5000` en el cluster).
- Arranque en frío con tag `dev`; el CI (Tekton, ver spec `quicktask-tekton-ci`)
  publicará tags inmutables por SHA.
- **Limitación**: el registry es local; no hay promoción entre entornos.

## Dónde queremos llegar (CI build + registry + GitOps CD)

```
 push a quicktask (main/tag)
     │
     ▼
 [CI] GitHub Actions
     ├─ fmt + vet + unit tests (-race) + cobertura
     ├─ tests de integración (MongoDB vía testcontainers)
     ├─ docker build  ──>  tag inmutable (ghcr.io/slashispy/quicktask:<sha>)
     └─ docker push  ──>  GHCR
     │
     ▼
 [CD] bump de la imagen en gitops-app-values
     └─ actualiza apps/quicktask/values.yaml  image.tag: <sha>
        (commit automatizado o PR)
     │
     ▼
 Argo CD detecta el cambio en Git y sincroniza el nuevo tag en el cluster.
```

### Fase CI (repo `quicktask`)

Ya existe `.github/workflows/ci.yml` con fmt, vet, build, tests unitarios con
cobertura, tests de integración Docker y build de imagen. Para cerrar el circuito
faltaría **publicar** la imagen:

```yaml
# extracto conceptual — build & push a GHCR
- uses: docker/login-action@v3
  with:
    registry: ghcr.io
    username: ${{ github.actor }}
    password: ${{ secrets.GITHUB_TOKEN }}
- uses: docker/build-push-action@v6
  with:
    context: .
    push: true
    tags: ghcr.io/slashispy/quicktask:${{ github.sha }}
```

Clave de diseño: **tag inmutable por commit** (`<sha>` o `<version>`), nunca
`latest`. Así cada despliegue es trazable a un commit exacto.

### Fase CD (GitOps, repo `gitops-app-values`)

El principio GitOps es que **Git es la fuente de verdad**; el cluster no se toca
a mano. Para desplegar una nueva imagen se cambia `image.tag` en
`gitops-app-values/apps/quicktask/values.yaml`. Dos estrategias:

1. **Bump automatizado desde CI** (write-back): un step al final del pipeline de
   `quicktask` hace checkout de `gitops-app-values`, actualiza `image.tag` y
   abre un PR (o commitea a `main`). Simple y explícito.
2. **Argo CD Image Updater**: un controlador que observa el registry y actualiza
   el tag en Git automáticamente según una política (semver, regex de tags…).
   Menos YAML de pipeline, a cambio de otro componente a operar.

En ambos casos, **Argo CD** reconcilia el cambio de Git hacia el cluster con la
`syncPolicy automated { prune, selfHeal }` que ya define el ApplicationSet.

## Promoción entre entornos

La estructura `apps/<app>/` de `gitops-app-values` está preparada para crecer a
`apps/<app>/<entorno>/` (p. ej. `dev`, `staging`, `prod`). La promoción es un
cambio de tag de un entorno a otro en Git — un PR revisable y auditable.

## Qué queda fuera de esta demo (deuda consciente)

- Registry remoto real (GHCR) y credenciales de pull en el cluster.
- Firmado de imágenes (cosign) y verificación de procedencia.
- Secretos de verdad vía **External Secrets Operator** o **SOPS** (hoy el Secret
  del chart lleva valores de ejemplo).
- TLS/Ingress con cert-manager, y observabilidad (Prometheus/Grafana).

Todo esto es incremental: el modelo GitOps (chart genérico + values + Argo CD)
no cambia; solo se enriquecen los extremos (CI y seguridad).
