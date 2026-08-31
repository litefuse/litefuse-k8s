# litefuse

Helm chart for [Litefuse](https://github.com/litefuse/litefuse), the Apache
Doris-backed LLM engineering platform (tracing, evals, prompt management).

Deploys:

- **litefuse-web** — Next.js UI + API (runs Postgres/Doris migrations on start)
- **litefuse-worker** — background ingestion / evaluation processor
- **Apache Doris** — analytics store, as a `DorisCluster` CR managed by the
  bundled [Doris Operator](https://github.com/apache/doris-operator)
- **PostgreSQL** (groundhog2k/postgres), **Valkey** (Redis-compatible) and
  **SeaweedFS** (S3-compatible) sub-charts for the remaining stores

Every store can be switched to an external endpoint via `<store>.deploy=false`
plus its connection fields — see [External stores](#external-stores).

## Table of contents

- [Prerequisites](#prerequisites)
- [Installing](#installing)
- [How configuration works](#how-configuration-works)
- [Application configuration](#application-configuration)
- [Doris](#doris)
- [External stores](#external-stores)
- [Secrets managed by the chart](#secrets-managed-by-the-chart)
- [Scaling & operations](#scaling--operations)
- [Upgrading](#upgrading)
- [Troubleshooting](#troubleshooting)
- [Testing](#testing)
- [Uninstalling](#uninstalling)

## Prerequisites

- Kubernetes **1.24+**, Helm **3.18+** (the SeaweedFS sub-chart uses `fromToml`)
- A default StorageClass, or set the per-store `storageClass` fields
- Cluster capacity for the default (single-replica) footprint:

  | | CPU requests | Memory requests | PVC |
  |---|---|---|---|
  | Doris FE ×1 | 2 | 4Gi | 20Gi |
  | Doris BE ×1 | 4 | 8Gi | 200Gi |
  | SeaweedFS | 0.5 | 1Gi | 50Gi |
  | PostgreSQL | — | — | 20Gi |
  | Valkey | — | — | 8Gi |
  | web + worker | — | — | — |

  ≈ **6.5 CPU / 13Gi requests and ~300Gi of volumes**. For a laptop-sized
  cluster use the repository's `examples/values-dev.yaml`, which roughly
  halves this.

## Installing

### From the OCI registry (recommended)

The published package bundles all sub-chart dependencies — no `helm repo add`
needed:

```sh
helm install litefuse oci://ghcr.io/litefuse/litefuse --version 1.0.0 \
  -n litefuse --create-namespace
```

Discover the configuration without cloning the repository:

```sh
helm show values oci://ghcr.io/litefuse/litefuse --version 1.0.0   # all options, annotated
helm show readme oci://ghcr.io/litefuse/litefuse --version 1.0.0   # this document
```

### From source

```sh
git clone https://github.com/litefuse/litefuse-k8s.git && cd litefuse-k8s
helm dependency update charts/litefuse
helm install litefuse charts/litefuse -n litefuse --create-namespace
```

(`helm dependency update` fetches the sub-charts directly from the repository
URLs in `Chart.yaml` — no `helm repo add` needed.)

### What to expect on a fresh install

The first install brings in the Doris Operator CRDs from the bundled
dependency, then creates a `DorisCluster` CR. **Doris FE/BE take a few minutes
to form a cluster, and the web/worker pods restart until the Doris schema
migrations succeed — this is expected.** Watch progress with:

```sh
kubectl get doriscluster -n litefuse
kubectl get pods -n litefuse -w
```

The install is done when the DorisCluster reports its FE/BE available and the
web/worker pods are `Running` and `Ready`.

### Accessing the UI

Without an ingress:

```sh
kubectl port-forward -n litefuse svc/litefuse-web 3000:3000
# open http://localhost:3000
```

For a real deployment enable the [ingress](#ingress) and set
`litefuse.nextauth.url` to the canonical external URL.

Sign up for the first account via the UI (disable public sign-up afterwards
with `litefuse.features.signUpDisabled=true`), or bootstrap headlessly with
the `LITEFUSE_INIT_ORG_*` / `LITEFUSE_INIT_USER_*` environment variables via
`litefuse.additionalEnv`. Do **not** seed projects via
`LITEFUSE_INIT_PROJECT_*`: init-created projects skip Doris split-table
registration until their first ingest, and periodic jobs error on the missing
table meanwhile. Create projects via the UI/API instead.

### Offline rendering / GitOps

`helm template` and GitOps diff tools render without cluster access, so the
Doris CRD preflight check fails. Either pass
`--api-versions doris.selectdb.com/v1/DorisCluster` or set
`doris.crdCheck=false`.

Ready-to-use values files (dev sizing, production HA topology, external
Doris, single-Secret setup) live in the repository under
[`examples/`](https://github.com/litefuse/litefuse-k8s/tree/main/examples)
— they are deliberately not part of the chart package.

## How configuration works

All options live in `values.yaml` with inline docs; the chart's helpers render
them into environment variables on the web/worker pods. Three rules:

1. **Prefer the structured fields** (`litefuse.*`, `postgresql.*`, `redis.*`,
   `doris.*`, `s3.*`). They are validated at render time and wired into the
   right Secrets automatically.
2. **`litefuse.additionalEnv` is the escape hatch** for anything without a
   structured field. Setting the *same* variable both ways is rejected at
   render time (e.g. `features.telemetryEnabled` vs
   `additionalEnv[name: TELEMETRY_ENABLED]`) — pick one.
3. Litefuse env vars use the **`LITEFUSE_` prefix**. A stale
   `LANGFUSE_`-prefixed variable is silently ignored (the worker hard-exits on
   a missing `LITEFUSE_S3_EVENT_UPLOAD_BUCKET`, for example) — mind this when
   migrating values from langfuse-k8s.

Sensitive fields accept either an inline value or a reference to an existing
Secret, everywhere the pattern below appears:

```yaml
someSecretField:
  value: ""                # inline (fine for testing)
  secretKeyRef:            # preferred: reference your own Secret
    name: my-secret
    key: my-key
```

`litefuse.additionalEnvFrom`, `extraContainers`, `extraInitContainers`,
`extraVolumes` / `extraVolumeMounts` and `extraManifests` exist for anything
beyond env vars.

## Application configuration

### Canonical URL

```yaml
litefuse:
  nextauth:
    url: https://litefuse.example.com   # REQUIRED for any real deployment
```

### Security keys

| Key | Env var | Format |
|---|---|---|
| `litefuse.salt` | `SALT` | any string (`openssl rand -base64 32`) |
| `litefuse.encryptionKey` | `ENCRYPTION_KEY` | 256-bit hex (`openssl rand -hex 32`) |
| `litefuse.nextauth.secret` | `NEXTAUTH_SECRET` | any string (`openssl rand -base64 32`) |

Left empty, all three are **auto-generated on first install** and persisted in
the `<release>-app` Secret, which is kept across uninstalls
(`helm.sh/resource-policy: keep`). Losing `SALT` or `ENCRYPTION_KEY` is
unrecoverable — API keys and encrypted data become unreadable.

Pin them for production, especially under GitOps where `helm template` cannot
look up the generated Secret:

```yaml
litefuse:
  salt:
    secretKeyRef: { name: litefuse-app-credentials, key: salt }
  encryptionKey:
    secretKeyRef: { name: litefuse-app-credentials, key: encryption-key }
  nextauth:
    secret:
      secretKeyRef: { name: litefuse-app-credentials, key: nextauth-secret }
```

### Feature flags

| Value | Default | Effect |
|---|---|---|
| `litefuse.features.telemetryEnabled` | `false` | Anonymous usage statistics (opt-in) |
| `litefuse.features.signUpDisabled` | `false` | Disable public sign-up after creating your accounts |
| `litefuse.features.experimentalFeaturesEnabled` | `false` | Enable experimental features |
| `litefuse.features.backgroundMigrationsEnabled` | `false` | Run background migrations on worker startup |

### Logging & runtime

| Value | Default | Notes |
|---|---|---|
| `litefuse.logging.level` | `info` | `trace`/`debug`/`info`/`warn`/`error`/`fatal` |
| `litefuse.logging.format` | `text` | `text` or `json` (for log collectors) |
| `litefuse.timezone` | `UTC` | Applied to app pods **and** bundled Doris. Keep UTC — Doris date partitioning depends on it |
| `litefuse.nodeEnv` | `production` | Node.js environment |

### SMTP (transactional email)

```yaml
litefuse:
  smtp:
    connectionUrl: "smtp://user:password@smtp.example.com:587"
    fromAddress: "litefuse@example.com"   # required when connectionUrl is set
```

### SSO / authentication providers

Supported providers: `auth0`, `cognito`, `azureAd`, `github`,
`githubEnterprise`, `gitlab`, `google`, `keycloak`, `okta`, `workos`,
`custom` (validated at render time). Options are written in camelCase and
rendered as `AUTH_<PROVIDER>_<OPTION>` env vars — any option the app
understands works, not just the ones shown here:

```yaml
litefuse:
  auth:
    disableUsernamePassword: true   # SSO-only login
    providers:
      azureAd:
        clientId: "<client id>"
        clientSecret:
          secretKeyRef: { name: my-sso-secret, key: azure-client-secret }
        tenantId: "<tenant id>"
      google:
        clientId: "<client id>"
        clientSecret:
          secretKeyRef: { name: my-sso-secret, key: google-client-secret }
```

`litefuse.allowedOrganizationCreators` (EE) restricts who may create
organizations.

### Ingress

```yaml
litefuse:
  ingress:
    enabled: true
    className: nginx
    annotations:
      # SDK batch ingestion posts can be large — do not cap at the nginx 1m default
      nginx.ingress.kubernetes.io/proxy-body-size: 100m
    hosts:
      - host: litefuse.example.com
        paths:
          - path: /
            pathType: Prefix
    tls:
      enabled: true
      secretName: litefuse-tls
```

Only the web Service is exposed; the worker has no HTTP endpoint.

### Ingestion batching (OTel grouper)

`litefuse.otelGroup.*` controls ingestion batching: a group ships when it hits
`targetBytes` (64MB) OR `targetRows` (100k) OR `maxFiles` (1000), or when its
oldest entry has waited `flushMs` (1s). Bigger batches mean higher throughput
and lower Doris BE fan-out; `flushMs` bounds latency at low traffic. **Keep
`maxFiles` modest (1000)** — a huge value makes a single cut scan a giant
pending list and can stall shared Redis.

### Everything else (additionalEnv)

```yaml
litefuse:
  additionalEnv:
    - name: LITEFUSE_SOME_FLAG
      value: "true"
    - name: SOME_SECRET_SETTING
      valueFrom:
        secretKeyRef: { name: my-secret, key: some-key }
```

## Doris

### Bundled cluster (default)

`doris.deploy=true` renders a `DorisCluster` CR; the bundled
[Doris Operator](https://github.com/apache/doris-operator) reconciles it into
FE/BE StatefulSets.

| Value | Default | Notes |
|---|---|---|
| `doris.operator.enabled` | `true` | The operator installs **cluster-scoped** resources with static names — run only ONE per Kubernetes cluster. Set `false` to reuse an existing operator |
| `doris.cluster.fe.replicas` / `be.replicas` | 1 / 1 | Use 3 / 3+ for production HA (FE needs a quorum) |
| `doris.cluster.fe.image` / `be.image` | `apache/doris:fe-4.0.6` / `be-4.0.6` | Keep the fe-/be- tags in lockstep |
| `doris.cluster.fe.jvmHeapMb` | 4096 | FE JVM heap (-Xmx/-Xms). **Must leave ~2Gi+ headroom below the FE memory limit** or the pod is OOMKilled — the image default is a fixed 8G heap, which overruns any limit ≤ 8Gi |
| `doris.cluster.fe.config` / `be.config` | tuned | Extra settings appended into the chart-managed `fe.conf` / `be.conf` |
| `doris.cluster.enableRestartWhenConfigChange` | `true` | Operator rolls FE/BE automatically when the config ConfigMaps change. The operator hashes ONLY the main config file, which is why this chart merges all settings into it instead of a separate `*_custom.conf` |
| `doris.cluster.persistence.*` | 20Gi FE / 200Gi BE | FE metadata + BE storage PVCs; size BE for expected trace volume |
| `doris.replicationNum` | derived | Replication factor for created tables. Defaults to `min(3, be.replicas)` for the bundled cluster; must not exceed the BE count (validated) |

The default `fe.config` / `be.config` carry the settings the docker-compose
deployment runs with: backend blacklist off, stream-load label retention
raised for exactly-once redrives (`streaming_label_keep_max_second`,
`label_num_threshold` — the latter costs FE heap, mind `jvmHeapMb`),
`autobucket_min_buckets=10` so auto-created day partitions never start at 1
bucket, and `max_tablet_version_num=5000` for compaction headroom on
high-frequency stream loads. Edit them via values if your workload needs
different headroom.

The bundled cluster only provisions the built-in `root` user (empty password);
`doris.auth.username` must stay `root` when `doris.deploy=true` (validated).

### External Doris

```yaml
doris:
  deploy: false
  operator:
    enabled: false
  host: my-doris-fe.example.com   # FE endpoint (MySQL protocol + HTTP)
  httpPort: 8030
  queryPort: 9030
  # Managed offerings often expose HTTP elsewhere — override the full URL then:
  # feHttpUrl: http://my-doris-fe.example.com:8080
  database: litefuse
  auth:
    username: admin
    existingSecret: my-doris-credentials
    existingSecretKey: password
  replicationNum: 3   # keep 3 with >= 3 BEs
```

**A single-BE external Doris needs `replicationNum: 1`** — the app default of
3 makes every `CREATE TABLE` fail when fewer backends are alive.

### Connection tuning

| Value | Default | Env var |
|---|---|---|
| `doris.maxOpenConnections` | 100 | `DORIS_MAX_OPEN_CONNECTIONS` — MySQL-protocol connections per pod |
| `doris.requestTimeoutMs` | 30000 | `DORIS_REQUEST_TIMEOUT_MS` — per-read socket inactivity, not total request duration (Stream Load has healthy quiet phases) |
| `doris.migration.autoMigrate` | `true` | Run Doris schema migrations on startup |

## External stores

Each bundled store follows the same pattern: `<store>.deploy: false` plus
connection + auth fields. Validation fails at render time if a required
endpoint is missing.

### PostgreSQL

Bundled: single-instance `postgres:17` via the groundhog2k sub-chart
(`postgresql.storage.requestedSize`, default 20Gi). For HA or managed
Postgres:

```yaml
postgresql:
  deploy: false
  host: my-postgres.example.com
  port: 5432          # default
  args: ""            # extra connection-string args, e.g. sslmode=require
  auth:
    username: litefuse
    database: litefuse
    existingSecret: my-postgres-credentials   # or password: "..."
    secretKeys:
      userPasswordKey: password
```

Additional knobs for managed/cloud databases:

- `postgresql.directUrl` — separate connection string for **migrations**
  (different user, or bypassing a pooler like pgbouncer on `DATABASE_URL`).
  Configure long timeouts for that user; migrations can take a while on large
  deployments.
- `postgresql.shadowDatabaseUrl` — required when the database user lacks
  `CREATE DATABASE` permission (common on cloud Postgres); see the Prisma
  docs.
- `postgresql.migration.autoMigrate` — run Postgres migrations on startup
  (default `true`).
- Connection budget: each web/worker replica opens its own Prisma pool. When
  scaling into dozens of replicas, cap per-pod connections via
  `postgresql.args` (e.g. `connection_limit=20&pool_timeout=30`) and size
  Postgres `max_connections` accordingly.

### Redis / Valkey

Bundled: standalone Valkey 8.0 with ACL auth (`default` user, generated
password) and the required `maxmemory-policy noeviction` — Litefuse loses job
data under eviction, so the chart refuses to render without it.

External standalone:

```yaml
redis:
  deploy: false
  host: my-redis.example.com
  port: 6379
  auth:
    username: "default"        # null to omit from the connection string
    existingSecret: my-redis-credentials
    existingSecretPasswordKey: password
```

Redis Cluster (requires `deploy: false`):

```yaml
redis:
  deploy: false
  cluster:
    enabled: true
    nodes: ["redis-1:6379", "redis-2:6379", "redis-3:6379"]
```

Redis Sentinel (requires `deploy: false`; mutually exclusive with cluster
mode):

```yaml
redis:
  deploy: false
  sentinel:
    enabled: true
    masterName: mymaster
    nodes: "sentinel-1:26379,sentinel-2:26379,sentinel-3:26379"
```

TLS (`redis.tls.enabled` + `caPath`/`certPath`/`keyPath`) works for both the
bundled Valkey and external endpoints; mount the certificate files via
`litefuse.extraVolumes` / `extraVolumeMounts`. Configure `maxmemory-policy
noeviction` on any external Redis/Valkey yourself.

### S3 / blob storage

Bundled: SeaweedFS in all-in-one mode with auth enabled and the `litefuse`
bucket auto-created (`s3.allInOne.data.size`, default 50Gi). Any bucket you
reference in values must appear in `s3.allInOne.s3.createBuckets` — validated
at render time so uploads don't fail with `NoSuchBucket` later.

External S3 (AWS):

```yaml
s3:
  deploy: false
  bucket: my-litefuse-bucket
  region: eu-west-1
  forcePathStyle: false
  accessKeyId:
    secretKeyRef: { name: my-s3-credentials, key: access-key-id }
  secretAccessKey:
    secretKeyRef: { name: my-s3-credentials, key: secret-access-key }
```

Leave `accessKeyId`/`secretAccessKey` empty to use the pod's ambient identity
(IRSA / instance profile) via the AWS SDK default credential chain.

MinIO or another S3-compatible gateway: additionally set `s3.endpoint:
http://minio.example.com:9000` and keep `forcePathStyle: true`.

Azure Blob / GCS: set `s3.storageProvider: azure` or `gcs`; for GCS supply
`s3.gcs.credentials` (JSON inline or `secretKeyRef`), or rely on the pod's
service-account credentials.

Per-upload-type sections override the global fields independently:

| Section | Enabled | Default prefix | Notes |
|---|---|---|---|
| `s3.eventUpload` | always | `events/` | Raw trace/event payloads — required by the worker |
| `s3.mediaUpload` | `true` | `media/` | Multi-modal attachments; `maxContentLength` (1GB), `downloadUrlExpirySeconds` (1h) |
| `s3.batchExport` | `false` | `exports/` | UI batch exports — enable if you need them |

`s3.concurrency.reads` / `writes` (default 50 each) cap concurrent S3
operations per pod.

## Secrets managed by the chart

| Secret | Contents | Notes |
|---|---|---|
| `<release>-app` | `SALT`, `ENCRYPTION_KEY`, `NEXTAUTH_SECRET` | Auto-generated when not pinned; **kept on uninstall** — losing it is unrecoverable |
| `litefuse-postgresql-auth` | Postgres superuser + litefuse user credentials | Fixed name (also consumed by the sub-chart) |
| `litefuse-redis-auth` | Valkey ACL users (one key per username) | Fixed name |
| `litefuse-s3-auth` | S3 access/secret key + SeaweedFS IAM config | Fixed name |

The three store Secrets have fixed default names because the sub-charts mount
them by name. Running two releases in one namespace requires overriding the
name in *both* places (e.g. `postgresql.settings.existingSecret` **and**
`postgresql.userDatabase.existingSecret`) — the chart validates that they stay
in sync at render time and fails with a descriptive message otherwise.

To source every credential from one pre-created Secret (GitOps-friendly), see
[`examples/minimal-installation/`](https://github.com/litefuse/litefuse-k8s/tree/main/examples/minimal-installation)
in the repository.

## Scaling & operations

- Each web/worker replica is one Node.js process (~1 core at saturation) —
  **scale out, not up**:

  ```yaml
  litefuse:
    web:
      replicas: 6
    worker:
      replicas: 12
  ```

- **HPA / KEDA / VPA** blocks exist for both web and worker
  (`litefuse.web.hpa.*`, `litefuse.worker.keda.*`, ...). KEDA and HPA/VPA are
  mutually exclusive per component (validated). Example:

  ```yaml
  litefuse:
    web:
      hpa:
        enabled: true
        minReplicas: 2
        maxReplicas: 10
        targetCPUUtilizationPercentage: 50
  ```

- **PodDisruptionBudgets** are created by default (`litefuse.web.pdb.create`,
  `litefuse.worker.pdb.create`; default `maxUnavailable: 1`).
- Scheduling controls (`nodeSelector`, `tolerations`, `affinity`,
  `topologySpreadConstraints`) exist globally under `litefuse.*` and per
  component under `litefuse.web.pod.*` / `litefuse.worker.pod.*`; Doris FE/BE
  have their own under `doris.cluster.fe.*` / `be.*`.
- The Doris Operator installs **cluster-scoped** resources with static names —
  run only ONE operator per Kubernetes cluster. For a second litefuse release
  set `doris.operator.enabled=false` and share the existing operator.
- The stack assumes **UTC** end to end (`litefuse.timezone`) — Doris date
  partitioning depends on it.

## Upgrading

```sh
helm upgrade litefuse oci://ghcr.io/litefuse/litefuse --version <ver> -n litefuse
# or, from source: helm dependency update charts/litefuse && helm upgrade litefuse charts/litefuse -n litefuse
```

- The web/worker images default to the chart's `appVersion`; pin
  `litefuse.image.tag` to control the app version independently of the chart
  version. Web runs Postgres/Doris migrations on startup.
- **Helm never upgrades CRDs.** When a chart upgrade bumps the Doris Operator
  dependency, apply its updated CRDs manually (`kubectl apply -f` from the
  operator release) before upgrading.
- With `enableRestartWhenConfigChange: true` (default), edits to
  `doris.cluster.fe.config` / `be.config` roll the FE/BE pods automatically on
  upgrade.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `helm template` fails: `Doris Operator CRD not found` | Rendering offline or against a fresh cluster. Pass `--api-versions doris.selectdb.com/v1/DorisCluster` or set `doris.crdCheck=false`; for a fresh cluster, install the operator (or apply its CRDs) first |
| web/worker CrashLoopBackOff in the first minutes | Expected while Doris FE/BE form a cluster and migrations retry. Watch `kubectl get doriscluster`; investigate only if it persists after Doris is Ready |
| Doris FE pod OOMKilled | `doris.cluster.fe.jvmHeapMb` too close to (or the 8G image default above) the container memory limit — keep ~2Gi+ headroom |
| `CREATE TABLE` fails with replication errors | `doris.replicationNum` exceeds alive BEs. Single-BE clusters need `replicationNum: 1` |
| Uploads fail with `NoSuchBucket` | A bucket referenced in `s3.*` is missing from `s3.allInOne.s3.createBuckets` (render-time validation covers values-defined buckets) |
| Worker exits: missing `LITEFUSE_S3_EVENT_UPLOAD_BUCKET` | A stale `LANGFUSE_`-prefixed env var from a langfuse-k8s migration — Litefuse only reads the `LITEFUSE_` prefix |
| Render fails after setting `<store>.auth.existingSecret` | The sub-chart still mounts the chart-managed Secret name. Follow the error message: also point the sub-chart pass-through (`settings.existingSecret`, `usersExistingSecret`, `existingConfigSecret`) at your Secret |
| Jobs disappear under memory pressure (external Redis) | The external Redis/Valkey must run `maxmemory-policy noeviction` |

## Testing

Template-level unit tests live in `tests/` (ported from langfuse-k8s and
extended with Doris-specific suites), run with the
[helm-unittest](https://github.com/helm-unittest/helm-unittest) plugin:

```sh
helm plugin install https://github.com/helm-unittest/helm-unittest
helm unittest .
```

The Doris suites pin down the behaviors that are easy to regress: the
DorisCluster CR shape (`enableRestartWhenConfigChange`, configMapInfo,
persistence), the merged fe.conf/be.conf ConfigMaps (JVM heap sizing,
`enable_fqdn_mode`, tuning merged into the hashed main file — never a
`*_custom.conf`), the `DORIS_*` env wiring (bundled/external/feHttpUrl,
replicationNum derivation, additionalEnv takeover), and the render-time
validations (external host required, replicationNum vs BE count, CRD
preflight).

## Uninstalling

```sh
helm uninstall litefuse -n litefuse
```

Kept intentionally after uninstall:

- **PVCs** for Doris FE/BE, PostgreSQL, Valkey and SeaweedFS (the data)
- The **`<release>-app` Secret** (SALT / ENCRYPTION_KEY / NEXTAUTH_SECRET)
  and generated store-credential Secrets — they unlock those volumes

A reinstall with the same release name picks all of this up and comes back
with the data intact. Delete the PVCs and Secrets manually only if you also
mean to discard the data.
