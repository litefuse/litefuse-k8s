# Minimal installation with a single pre-created Secret

Runs the full bundled stack (Doris, PostgreSQL, Valkey, SeaweedFS) with every
credential sourced from one Kubernetes Secret instead of chart-generated ones.
Useful under GitOps where `helm template` cannot look up generated Secrets.

```sh
kubectl create namespace litefuse
kubectl apply -n litefuse -f secret.yaml
helm install litefuse ../../charts/litefuse -n litefuse -f values.yaml
```

Replace every `your-*` placeholder in `secret.yaml` before applying. The
bundled Doris cluster authenticates as the built-in `root` user without a
password; for an external password-protected Doris set
`doris.auth.existingSecret` / `doris.auth.existingSecretKey` in values.
