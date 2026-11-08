---
layout: default
title: Tutorial paso a paso
---

# Tutorial paso a paso: del cero al circuito GitOps funcionando

Esta guía te lleva de una máquina vacía a **quicktask + MongoDB corriendo en
Kubernetes (KIND), desplegados por Argo CD**, y te enseña cómo ver y comprobar
cada pieza. Todos los comandos y salidas de este tutorial fueron ejecutados y
verificados sobre el circuito real.

> **Tiempo estimado:** 10-15 minutos (la mayor parte es descarga de imágenes).

## Índice

0. [Requisitos](#0-requisitos)
1. [Clonar y preparar](#1-clonar-y-preparar)
2. [Crear el cluster KIND](#2-crear-el-cluster-kind)
3. [Instalar Argo CD](#3-instalar-argo-cd)
4. [Abrir la UI de Argo CD](#4-abrir-la-ui-de-argo-cd)
5. [Construir las imágenes y crear las claves JWT](#5-construir-las-imágenes-y-crear-las-claves-jwt)
6. [Arrancar el circuito GitOps](#6-arrancar-el-circuito-gitops)
7. [Ver cada recurso funcionando](#7-ver-cada-recurso-funcionando)
8. [Probar la aplicación](#8-probar-la-aplicación)
9. [Ver GitOps en acción (self-heal)](#9-ver-gitops-en-acción-self-heal)
10. [Cambiar algo vía Git](#10-cambiar-algo-vía-git)
11. [Limpiar](#11-limpiar)
12. [Resolución de problemas](#12-resolución-de-problemas)

---

## 0. Requisitos

| Herramienta | Para qué | Verificar |
|---|---|---|
| Docker | Corre los nodos KIND y construye las imágenes | `docker info` |
| kind | Cluster de Kubernetes local | `kind version` |
| kubectl | Cliente de Kubernetes | `kubectl version --client` |
| make, bash, curl, openssl, python3 | Orquestación, claves JWT y pruebas | `make --version` |

**Docker debe estar corriendo** antes de empezar. No necesitas `helm` ni `go`
instalados: Argo CD renderiza el chart dentro del cluster y las imágenes (Go y
Quarkus) se compilan dentro de Docker.

```bash
docker info >/dev/null && echo "docker ok"
kind version
kubectl version --client
```

## 1. Clonar y preparar

El circuito son 6 repos, pero **solo necesitas clonar tres** en tu máquina: este
(el tooling), `quicktask` y `quicktask-auth` (para construir las imágenes). El
resto lo lee Argo CD directamente desde GitHub.

```bash
mkdir -p ~/Developer/go/proyectos ~/Developer/java/proyectos
cd ~/Developer/go/proyectos
git clone https://github.com/slashispy/kind-gitops-utility-belt
git clone https://github.com/slashispy/quicktask
git clone https://github.com/slashispy/quicktask-auth ~/Developer/java/proyectos/quicktask-auth
cd kind-gitops-utility-belt
```

Si clonas los repos en otras rutas, indícalas cuando construyas las imágenes:
`QUICKTASK_DIR=/mi/ruta/quicktask QUICKTASK_AUTH_DIR=/mi/ruta/quicktask-auth make image`.

Mira los targets disponibles:

```bash
make help
```

## 2. Crear el cluster KIND

```bash
make up
```

**Qué hace:** ejecuta `scripts/00-create-cluster.sh`, que crea el cluster
`quicktask-gitops` (1 nodo control-plane) con `kind/kind-config.yaml`.

**Cómo verlo:**

```bash
kind get clusters
# quicktask-gitops

kubectl get nodes
# NAME                             STATUS   ROLES           AGE   VERSION
# quicktask-gitops-control-plane   Ready    control-plane   1m    v1.xx

docker ps --filter name=quicktask-gitops
# el "nodo" de Kubernetes es, en realidad, un contenedor Docker
```

## 3. Instalar Argo CD

```bash
make argocd
```

**Qué hace:** crea el namespace `argocd`, aplica los manifiestos oficiales de
Argo CD y espera a que los Deployments estén disponibles. Tarda 2-4 minutos.

> **Nota técnica.** El script usa `kubectl apply --server-side --force-conflicts`.
> El CRD `applicationsets.argoproj.io` es tan grande que un `apply` normal falla
> con `metadata.annotations: Too long: may not be more than 262144 bytes`. El
> server-side apply no guarda esa anotación y además es idempotente.

**Cómo verlo** (en otra terminal puedes seguirlo en vivo con `-w`):

```bash
kubectl -n argocd get pods -w
```

Resultado esperado: 7 pods en `Running` y `1/1`:

```
argocd-application-controller-0
argocd-applicationset-controller-…
argocd-dex-server-…
argocd-notifications-controller-…
argocd-redis-…
argocd-repo-server-…
argocd-server-…
```

Comprueba también los CRDs que Argo CD añadió al cluster:

```bash
kubectl get crd | grep argoproj
# applications.argoproj.io, applicationsets.argoproj.io, appprojects.argoproj.io
```

## 4. Abrir la UI de Argo CD

Obtén la contraseña inicial del usuario `admin`:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Abre el túnel (**deja esta terminal abierta**):

```bash
kubectl -n argocd port-forward svc/argocd-server 9091:443
```

Entra en **<https://localhost:9091>**, acepta el certificado autofirmado y usa
`admin` + la contraseña. En este punto la UI aparece **vacía**: aún no hay
ninguna aplicación.

> **¿Por qué 9091 y no 8081?** `kind-config.yaml` reserva los puertos 8080 y
> 8081 del host (mapeos opcionales a NodePort). Si hicieras `port-forward` sobre
> ellos obtendrías `address already in use`. Por eso usamos 9090 (app) y 9091
> (Argo CD).

## 5. Construir las imágenes y crear las claves JWT

```bash
make image
make keys
```

**`make image`** hace `docker build` de **dos imágenes** (`quicktask:dev`, Go, y
`quicktask-auth:dev`, Quarkus) y las copia **dentro del nodo** con
`kind load docker-image`. No hay registry: el chart usa `pullPolicy: IfNotPresent`
y el tag fijo `dev`.

```bash
docker exec quicktask-gitops-control-plane crictl images | grep quicktask
# docker.io/library/quicktask        dev   …
# docker.io/library/quicktask-auth   dev   …
```

Si falta alguna, el pod acabará en `ImagePullBackOff`.

**`make keys`** crea los datos sensibles del flujo de autenticación como
**Secrets del cluster** (nunca van a Git):

| Secret | Contenido | Quién lo usa |
|---|---|---|
| `quicktask-auth-keys` | `private.pem`, clave **privada** RSA | solo `quicktask-auth` (firma) |
| `quicktask-jwt-public` | `public.pem`, clave **pública** | `quicktask` (valida) |
| `quicktask-auth-demo-client` | `client-id`, `client-secret`, `secret-hash` (bcrypt) | `quicktask-auth` lee el hash; tú el secret |

```bash
kubectl -n quicktask get secret
```

Es idempotente: si los Secrets ya existen no los toca (`FORCE=1 make keys` los
regenera). Debe ejecutarse **antes** de `make apps`; si no, los pods esperan en
`ContainerCreating` hasta que los Secrets existan.

## 6. Arrancar el circuito GitOps

```bash
make apps
```

**Qué hace:** aplica **un único manifiesto**, `app-of-apps.yaml`, leído desde
`gitops-argocd-apps`. A partir de ahí no se toca nada más a mano; Argo CD hace
el resto leyendo Git:

```
root (Application)
 ├─ AppProject  quicktask            ← projects/quicktask-project.yaml
 └─ ApplicationSet  quicktask-apps   ← apps/applicationset.yaml
        └─ lee gitops-app-values/apps/*/metadata.yaml
            ├─ Application  quicktask
            │    ├─ chart:  helm-chart-generic-app
            │    └─ values: gitops-app-values/apps/quicktask/values.yaml
            │         └─ Deployment · Service · ConfigMap · Secret · MongoDB
            └─ Application  quicktask-auth
                 ├─ chart:  helm-chart-generic-app          (el MISMO chart)
                 └─ values: gitops-app-values/apps/quicktask-auth/values.yaml
                      └─ Deployment · Service · ConfigMap
```

Añadir `quicktask-auth` al circuito no tocó ni el ApplicationSet ni los
manifiestos de Argo CD: bastó una carpeta `apps/quicktask-auth/` en
`gitops-app-values`.

**Cómo verlo, capa por capa:**

```bash
# 1) Las Applications (en vivo)
kubectl -n argocd get applications -w
# NAME        SYNC STATUS   HEALTH STATUS
# root             Synced        Healthy
# quicktask        Synced        Healthy
# quicktask-auth   Synced        Healthy

# 2) El proyecto y el ApplicationSet que creó root
kubectl -n argocd get appproject,applicationset

# 3) Los pods de la app
kubectl -n quicktask get pods -w
# quicktask-xxxxxxxxxx-xxxxx        1/1   Running
# quicktask-auth-xxxxxxxxxx-xxxxx   1/1   Running
# quicktask-mongodb-0               1/1   Running
```

> **Es normal que `quicktask` se reinicie 1-3 veces al arrancar.** La app
> intenta conectar a Mongo al iniciar; el Service headless solo resuelve DNS
> cuando `quicktask-mongodb-0` está `Ready`, así que los primeros intentos
> fallan (`no such host`) y Kubernetes reinicia el contenedor hasta que Mongo
> responde. Puedes verlo con
> `kubectl -n quicktask logs deploy/quicktask --previous`.

## 7. Ver cada recurso funcionando

### En la UI de Argo CD

Con el port-forward del paso 4 abierto, refresca <https://localhost:9091>:

- Aparecen las tarjetas **root**, **quicktask** y **quicktask-auth**, todas `Healthy` y `Synced`.
- Entra en **quicktask**: verás el grafo con Deployment → ReplicaSet → Pod,
  Service, ConfigMap, Secret, StatefulSet → Pod → PVC.
- Cada nodo muestra su estado; haz clic para ver el manifiesto, el diff con Git
  y los eventos.

### Por línea de comandos

```bash
kubectl -n quicktask get all,pvc,cm,secret
```

Resultado esperado:

| Recurso | Nombre | Qué es |
|---|---|---|
| `deployment` | `quicktask` | La API Go (1 réplica). |
| `service` | `quicktask` (ClusterIP :8080) | Acceso interno a la API. |
| `statefulset` | `quicktask-mongodb` | MongoDB 7.0 con 1 réplica. |
| `service` | `mongodb` (headless) | DNS estable `mongodb.quicktask.svc.cluster.local`. |
| `pvc` | `data-quicktask-mongodb-0` (1Gi) | Volumen persistente de Mongo. |
| `configmap` | `quicktask-config` | `MONGO_DB_NAME`, `PORT`, `JWT_PUBLIC_KEY_PATH`, `JWT_ISSUER`, `JWT_AUDIENCE`. |
| `secret` | `quicktask-secret` | `MONGO_URI` (valor de demo). |
| `deployment` | `quicktask-auth` | Emisor de JWT (Quarkus, 1 réplica, sin base de datos). |
| `service` | `quicktask-auth` (ClusterIP :8080) | Acceso al emisor de JWT. |
| `secret` (creados por `make keys`) | `quicktask-auth-keys`, `quicktask-jwt-public`, `quicktask-auth-demo-client` | Claves RSA y cliente demo; **no están en Git**. |

Para ver cómo el chart inyectó la configuración en el contenedor:

```bash
kubectl -n quicktask describe deploy quicktask | sed -n '/Environment/,/Mounts/p'
kubectl -n quicktask get cm quicktask-config -o yaml
```

### Estado global en una sola pantalla

```bash
make status
```

## 8. Probar la aplicación

Abre el túnel hacia la API (**en otra terminal**):

```bash
kubectl -n quicktask port-forward svc/quicktask 9090:8080
```

### Health y readiness (sin autenticación)

```bash
curl -i http://localhost:9090/health
# HTTP/1.1 200 OK   {"status":"ok"}

curl -i http://localhost:9090/ready
# HTTP/1.1 200 OK   {"status":"ok"}   ← además hace ping a MongoDB
```

Son los endpoints que usan las probes `liveness` (`/health`) y `readiness`
(`/ready`) del Deployment.

### Endpoint protegido: `POST /v1/users`

Sin token debe rechazarse:

```bash
curl -i -X POST http://localhost:9090/v1/users -d '{}'
# HTTP/1.1 401 Unauthorized
```

Para crear un usuario necesitas un JWT que emite **`quicktask-auth`** (Quarkus).
Abre el túnel hacia el emisor (**en otra terminal**) y pide un token con el
cliente de demo que creó `make keys`:

```bash
kubectl -n quicktask port-forward svc/quicktask-auth 9092:8080
```

```bash
TOKEN=$(scripts/token.sh)

# Qué lleva dentro (claims):
echo "$TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null; echo
# {"iss":"http://quicktask-auth","aud":"quicktask","sub":"demo-service",
#  "user_id":"demo-service","iat":…,"exp":…,"jti":"…"}
```

`scripts/token.sh` lee `client-id` y `client-secret` del Secret
`quicktask-auth-demo-client` y hace `POST /v1/auth/token` con
`grant_type=client_credentials`. El token está firmado con **RS256** y vive 15
minutos. Ahora sí:

```bash
curl -i -X POST http://localhost:9090/v1/users \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"name":"Ada","email":"ada@example.com","password":"supersecret123"}'
# HTTP/1.1 201 Created
```

La contraseña debe tener entre 8 y 100 caracteres.

**Qué pasa con tokens que no deberían funcionar** (todos devuelven `401`):

```bash
# Token adulterado (se cambia el último carácter de la firma)
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://localhost:9090/v1/users \
  -H "Authorization: Bearer ${TOKEN%?}x" -d '{}'

# Credenciales de cliente incorrectas en el emisor
curl -s -w ' %{http_code}\n' -X POST http://localhost:9092/v1/auth/token \
  -H 'Content-Type: application/json' \
  -d '{"grant_type":"client_credentials","client_id":"demo","client_secret":"mal"}'
# {"error":"invalid_client",…} 401
```

`quicktask` solo conoce la clave **pública**, así que aunque alguien lea su
configuración no puede fabricar tokens válidos. Además fija el algoritmo en
RS256, de modo que un token `HS256` o `alg=none` se rechaza.

La clave pública también se publica para quien quiera validar tokens:

```bash
curl -s http://localhost:9092/.well-known/jwks.json
```

### Comprobar que se guardó en MongoDB

```bash
kubectl -n quicktask exec quicktask-mongodb-0 -- \
  mongosh quicktask --quiet \
  --eval 'db.users.find({}, {name:1, email:1}).toArray()'
# [ { _id: ObjectId('…'), name: 'Ada', email: 'ada@example.com' } ]
```

La contraseña **no** se muestra porque la proyección la excluye; en la base de
datos está almacenada con hash bcrypt.

### Logs de la app

```bash
kubectl -n quicktask logs deploy/quicktask -f
# Connected to MongoDB successfully
# 🚀 Starting server on port 8080
```

## 9. Ver GitOps en acción (self-heal)

El `ApplicationSet` activa `syncPolicy.automated` con `selfHeal: true`. Cualquier
cambio manual en el cluster que se desvíe de Git se revierte solo.

Terminal A: observa las réplicas.

```bash
kubectl -n quicktask get deploy quicktask -w
```

Terminal B: rompe el estado a mano.

```bash
kubectl -n quicktask scale deploy/quicktask --replicas=3
```

En unos segundos vuelve a **1 réplica**: Argo CD detectó la deriva (`OutOfSync`)
y la corrigió. En la UI se ve como un parpadeo del estado de la app. **Git es la
fuente de verdad; el cluster no se edita a mano.**

## 10. Cambiar algo vía Git

La forma correcta de cambiar el despliegue es un commit:

1. Haz fork de `gitops-app-values` (o usa el tuyo) y cambia, por ejemplo,
   `replicaCount: 2` en `apps/quicktask/values.yaml`.
2. Haz push a `main`.
3. Argo CD consulta Git cada ~3 minutos. Para acelerarlo, pulsa **Refresh** en
   la UI o ejecuta:

```bash
kubectl -n argocd annotate application quicktask \
  argocd.argoproj.io/refresh=hard --overwrite
kubectl -n quicktask get pods -w
```

> Si usas un fork, recuerda apuntar a él en `apps/applicationset.yaml` y
> `metadata.yaml` (y añadirlo a `sourceRepos` en el AppProject).

**Añadir otra aplicación** es crear `apps/<nombre>/{metadata.yaml,values.yaml}`
en `gitops-app-values`: el ApplicationSet la detecta y genera su Application sin
tocar nada más. Ese es el patrón de reutilización del chart genérico.

## 11. Limpiar

```bash
make down
```

Elimina el cluster KIND y **todos sus datos** (incluido el volumen de Mongo). Para
volver a empezar: `make bootstrap`, que encadena `up → argocd → image → apps`.

## 12. Resolución de problemas

| Síntoma | Causa probable | Solución |
|---|---|---|
| `metadata.annotations: Too long` al instalar Argo CD | `apply` cliente con un CRD enorme | Ya resuelto: el script usa `--server-side`. Si lo ejecutas a mano, añade `--server-side --force-conflicts`. |
| `address already in use` en `port-forward` | 8080/8081 están reservados por KIND | Usa 9090 y 9091 como en este tutorial. |
| Pod `quicktask` o `quicktask-auth` en `ImagePullBackOff` | La imagen no está en el nodo | `make image` y verifica con `crictl images`. |
| Pods en `ContainerCreating` (`secret … not found`) | No se ejecutó `make keys` | `make keys`; los pods arrancan solos al existir los Secrets. |
| `401` con un token recién emitido | Las claves cambiaron (`FORCE=1 make keys`) y los pods usan las anteriores | `kubectl -n quicktask rollout restart deploy quicktask quicktask-auth` y pide un token nuevo. |
| `token.sh` falla con `Connection refused` | Falta el port-forward del emisor | `kubectl -n quicktask port-forward svc/quicktask-auth 9092:8080`. |
| Pod `quicktask` reiniciando 1-3 veces | Arranca antes que Mongo (DNS del headless) | Es transitorio. Mira `logs --previous`. |
| `quicktask` en `CrashLoopBackOff` persistente | Mongo no llega a `Ready` | `kubectl -n quicktask describe pod quicktask-mongodb-0` y revisa el PVC. |
| Application `Unknown` / `ComparisonError` | Argo CD no alcanza el repo | `kubectl -n argocd describe application quicktask`; confirma que los repos son públicos y que `targetRevision` existe. |
| La UI no abre | Falta el port-forward | Relanza el comando del paso 4. |
| Cambié Git y no se aplica | Aún no hizo refresh | Pulsa Refresh o anota `argocd.argoproj.io/refresh=hard`. |
| Quiero empezar de cero | — | `make down && make bootstrap`. |

---

[← Volver al proyecto](./)
