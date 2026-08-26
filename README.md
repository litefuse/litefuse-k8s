# litefuse-k8s

Helm chart for deploying [Litefuse](https://github.com/litefuse/litefuse) — the
Apache Doris-backed LLM engineering platform — on Kubernetes.

The chart deploys the Litefuse web application and background worker together
with all backing stores:

| Component | Default | External option |
|---|---|---|
| Apache Doris (analytics) | DorisCluster CR via the [Doris Operator](https://github.com/apache/doris-operator) (bundled) | `doris.deploy=false` + `doris.host` |
| PostgreSQL (transactional) | [groundhog2k/postgres](https://github.com/groundhog2k/helm-charts) sub-chart | `postgresql.deploy=false` + `postgresql.host` |
| Redis (cache / queues) | [valkey-io/valkey](https://github.com/valkey-io/valkey-helm) sub-chart | `redis.deploy=false` + `redis.host` |
| S3 (blob storage) | [SeaweedFS](https://github.com/seaweedfs/seaweedfs) all-in-one sub-chart | `s3.deploy=false` + `s3.endpoint` / AWS / Azure / GCS |

## Repository layout

```
litefuse-k8s/
├── charts/litefuse/      # the Helm chart
│   ├── Chart.yaml
│   ├── values.yaml       # all configuration options, documented inline
│   └── templates/
└── examples/             # ready-to-use values files
    ├── values-dev.yaml            # laptop / small dev cluster
    ├── values-production.yaml     # HA Doris (3 FE / 3 BE), scaled web+worker, ingress
    └── values-external-doris.yaml # connect to managed / existing Doris
```

## Prerequisites

- Kubernetes 1.24+
- Helm **3.18+** (the SeaweedFS sub-chart uses `fromToml`)
- A default StorageClass (Doris FE/BE, PostgreSQL, Valkey and SeaweedFS all
  request PVCs by default)

## Quick start

```sh
git clone https://github.com/litefuse/litefuse-k8s.git && cd litefuse-k8s
helm dependency update charts/litefuse
helm install litefuse charts/litefuse -n litefuse --create-namespace
```

Then follow the printed notes; without an ingress:

```sh
kubectl port-forward -n litefuse svc/litefuse-web 3000:3000
```

For a development-sized install:

```sh
helm install litefuse charts/litefuse -n litefuse --create-namespace \
  -f examples/values-dev.yaml
```

See `charts/litefuse/README.md` for the full configuration reference.

## Relationship to the docker-compose deployment

The chart is the Kubernetes equivalent of the repo's `docker-compose.yml` /
`docker-compose.cluster.yml`: the same `litefuse/litefuse-web` and
`litefuse/litefuse-worker` images, the same `LITEFUSE_*` / `DORIS_*`
environment wiring, and the same Doris FE/BE custom configuration
(`disable_backend_black_list`, stream-load label retention,
`autobucket_min_buckets`, `max_tablet_version_num`) — shipped here as
ConfigMaps mounted through the Doris Operator.

## License

[MIT](LICENSE)
