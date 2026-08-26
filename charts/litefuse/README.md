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
plus its connection fields.

## Prerequisites

- Kubernetes 1.24+, Helm 3.18+
- A default StorageClass (or set the `storageClass` fields)

## Installing

```sh
helm dependency update .
helm install litefuse . -n litefuse --create-namespace
```

On a fresh cluster the first install brings in the Doris Operator CRDs from
the bundled dependency. Doris FE/BE take a few minutes to form a cluster;
web/worker pods restart until the Doris schema migrations succeed — this is
expected.

For offline rendering (`helm template`, GitOps diffs) either pass
`--api-versions doris.selectdb.com/v1/DorisCluster` or set
`doris.crdCheck=false`.

When installing from an OCI registry, discover the configuration with:

```sh
helm show values oci://<registry>/litefuse --version <ver>   # all options, annotated
helm show readme oci://<registry>/litefuse --version <ver>   # this document
```

Ready-to-use values files (dev sizing, production HA topology, external
Doris, single-Secret setup) live in the repository under
[`examples/`](https://github.com/litefuse/litefuse-k8s/tree/main/examples)
— they are deliberately not part of the chart package.

## Key configuration

All options live in `values.yaml` with inline docs. The most important ones:

### Litefuse application

| Value | Default | Notes |
|---|---|---|
| `litefuse.nextauth.url` | `http://localhost:3000` | Canonical external URL — set for any real deployment |
| `litefuse.salt` / `litefuse.encryptionKey` / `litefuse.nextauth.secret` | auto-generated | Persisted in the `<release>-app` Secret (kept on uninstall). Pin via `value` or `secretKeyRef` under GitOps |
| `litefuse.web.replicas` / `litefuse.worker.replicas` | 1 / 1 | Each replica is one Node.js process (~1 core at saturation) — scale out |
| `litefuse.ingress.*` | disabled | Standard ingress block; allow large bodies for SDK batch ingestion |
| `litefuse.otelGroup.*` | compose defaults | Ingestion batching knobs. Keep `maxFiles` at 1000 — huge values stall Redis |
| `litefuse.additionalEnv` | `[]` | Escape hatch for any `LITEFUSE_*` env var. `LITEFUSE_INIT_ORG_*`/`LITEFUSE_INIT_USER_*` bootstrap the first login; do NOT seed projects via `LITEFUSE_INIT_PROJECT_*` — init-created projects skip Doris split-table registration until their first ingest (periodic jobs error on the missing table meanwhile). Create projects via the UI/API instead |

### Doris

| Value | Default | Notes |
|---|---|---|
| `doris.deploy` | `true` | Deploy a DorisCluster CR via the operator |
| `doris.operator.enabled` | `true` | Install the operator as a dependency; disable if it already runs cluster-wide |
| `doris.cluster.fe.replicas` / `doris.cluster.be.replicas` | 1 / 1 | Use 3 / 3+ for production HA |
| `doris.replicationNum` | derived | Defaults to `min(3, be.replicas)` for the bundled cluster, 3 for external |
| `doris.cluster.fe.config` / `doris.cluster.be.config` | tuned | Extra settings appended into the chart-managed `fe.conf` / `be.conf` (ConfigMaps soft-linked into `conf/` by the operator) |
| `doris.cluster.fe.jvmHeapMb` | 4096 | FE JVM heap (-Xmx/-Xms); ships a full `fe.conf` because the FE start script reads JAVA_OPTS only from it. Keep ~2Gi+ headroom below the FE memory limit or the pod gets OOMKilled (image default is a fixed 8G heap) |
| `doris.cluster.enableRestartWhenConfigChange` | `true` | Operator watches the fe.conf/be.conf ConfigMaps and rolls FE/BE automatically on content changes. Without it config edits require a manual pod restart. NOTE: the operator hashes ONLY the main config file (`ResolveConfigMaps` reads the `fe.conf`/`be.conf` key), which is why this chart merges all settings into it instead of a separate `*_custom.conf` |
| `doris.cluster.persistence.*` | 20Gi FE / 200Gi BE | FE metadata + BE storage PVCs |
| `doris.host` (+ `httpPort`, `queryPort`) or `doris.feHttpUrl` | — | External Doris when `deploy=false` |
| `doris.auth.*` | root / empty | External clusters: prefer `existingSecret` |

The default `fe_custom.conf` / `be_custom.conf` carry the settings the
docker-compose deployment runs with (backend blacklist off, stream-load label
retention for exactly-once redrives, `autobucket_min_buckets=10`,
`max_tablet_version_num=5000`). Edit them via values if your workload needs
different headroom.

### Stores

| Value | Default | Notes |
|---|---|---|
| `postgresql.deploy` / `.host` / `.auth.*` | bundled | External: also see `directUrl`, `shadowDatabaseUrl` for restricted DB users |
| `redis.deploy` / `.host` / `.auth.*` | bundled | External standalone, or `redis.cluster.*` / `redis.sentinel.*` |
| `s3.deploy` / `.endpoint` / `.bucket` / `.accessKeyId` ... | bundled | External S3/MinIO/OSS; `storageProvider: azure|gcs` supported. Per-upload-type overrides under `eventUpload` / `mediaUpload` / `batchExport` |

Chart-managed store credentials are generated into `litefuse-postgresql-auth`,
`litefuse-redis-auth` and `litefuse-s3-auth` Secrets (names overridable — they
must stay in sync with the sub-chart pass-through values, which is validated
at render time).

## Scaling & operations

- The Doris Operator installs **cluster-scoped** resources with static names —
  run only ONE operator per Kubernetes cluster. For a second litefuse release
  set `doris.operator.enabled=false` and share the existing operator.
- **HPA / KEDA / VPA / PDB** blocks exist for both web and worker
  (`litefuse.web.hpa.*`, `litefuse.worker.keda.*`, ...).
- Postgres connection budget: each web/worker replica opens its own Prisma
  pool. When scaling into dozens of replicas, cap per-pod connections via
  `postgresql.args` (e.g. `connection_limit=20&pool_timeout=30`) and size
  Postgres `max_connections` accordingly.
- The stack assumes **UTC** end to end (`litefuse.timezone`) — Doris date
  partitioning depends on it.

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

PVCs and the generated credential Secrets are intentionally kept. Delete them
manually only if you also discard the data volumes they unlock.
