# Homelab

k3s cluster managed with Argo CD. Secrets are encrypted with SOPS.

## Bootstrap

```bash
./scripts/bootstrap-argocd.sh
```

After that, commit to `main` and Argo CD syncs it.

## Docs

- [Cluster setup](docs/setup.md)
- [Secrets](docs/secrets.md)
- [PostgreSQL backup and restore](docs/cnpg.md)
- [PVC backup and restore](docs/pvc-backup.md)
- [ntfy](docs/ntfy.md)
- [tailnet-node chart](charts/tailnet-node/README.md)
