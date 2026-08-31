# litefuse-k8s

Helm chart for deploying [Litefuse](https://github.com/litefuse/litefuse) — the
Apache Doris-backed LLM engineering platform — on Kubernetes.

The chart deploys the Litefuse web application and background worker together
with all backing stores:

| Component | Default | External option |
|---|---|---|
| Apache Doris (analytics) | DorisCluster CR via the [Doris Operator](https://github.com/apache/doris-operator) (bundled) | `doris.deploy=false` + `doris.host` |
| PostgreSQL (transactional) | [groundhog2k/postgres](https://github.com/groundhog2k/helm-charts) sub-chart | `postgresql.deploy=false` + `postgresql.host` |
| Redis (cache / queues) | [valkey-io/valkey](https://github.com/valkey-io/valkey-helm) sub-chart | `redis.deploy=false` + `redis.host` (standalone / cluster / sentinel) |
| S3 (blob storage) | [SeaweedFS](https://github.com/seaweedfs/seaweedfs) all-in-one sub-chart | `s3.deploy=false` + `s3.endpoint` / AWS / Azure / GCS |

Every store ships bundled by default so `helm install` alone yields a working
stack; each can be pointed at an external/managed service independently.

## Prerequisites

- Kubernetes 1.24+
- Helm **3.18+** (the SeaweedFS sub-chart uses `fromToml`)
- A default StorageClass (Doris FE/BE, PostgreSQL, Valkey and SeaweedFS all
  request PVCs by default)
- Capacity for the default footprint: ~6.5 CPU / 13Gi of requests and ~300Gi
  of volumes — or start from `examples/values-dev.yaml` for small clusters

## Quick start

### From the OCI registry

The published package bundles all sub-chart dependencies:

```sh
helm install litefuse oci://ghcr.io/litefuse/litefuse --version 1.0.0 \
  -n litefuse --create-namespace
```

### From source

```sh
git clone https://github.com/litefuse/litefuse-k8s.git && cd litefuse-k8s
helm dependency update charts/litefuse
helm install litefuse charts/litefuse -n litefuse --create-namespace
```

### After the install

Doris FE/BE take a few minutes to form a cluster; the web/worker pods restart
until the schema migrations succeed — this is expected. Then, without an
ingress:

```sh
kubectl port-forward -n litefuse svc/litefuse-web 3000:3000
# open http://localhost:3000 and sign up for the first account
```

For a development-sized install:

```sh
helm install litefuse charts/litefuse -n litefuse --create-namespace \
  -f examples/values-dev.yaml
```

## Configuration

All options live in `charts/litefuse/values.yaml` with inline documentation.
**[`charts/litefuse/README.md`](charts/litefuse/README.md) is the full
reference** — installation walk-through, application settings (URL, security
keys, SSO, ingress, SMTP), Doris sizing, connecting every store to external
services, chart-managed Secrets, scaling, upgrading and troubleshooting.

Ready-to-use values files live under [`examples/`](examples/):

| File | Purpose |
|---|---|
| `values-dev.yaml` | Laptop / small dev cluster: single replicas, reduced resources and volumes |
| `values-production.yaml` | HA Doris (3 FE / 3 BE, replication 3), scaled web+worker, ingress + TLS, pinned secrets |
| `values-external-doris.yaml` | Connect to a managed / existing Doris cluster |
| `minimal-installation/` | Full bundled stack with every credential sourced from one pre-created Secret (GitOps-friendly) |

## Repository layout

```
litefuse-k8s/
├── charts/litefuse/      # the Helm chart
│   ├── Chart.yaml
│   ├── values.yaml       # all configuration options, documented inline
│   ├── README.md         # full installation & configuration reference
│   ├── templates/
│   └── tests/            # helm-unittest suites
└── examples/             # ready-to-use values files (see table above)
```

## License

[MIT](LICENSE)
