# PVC backup and restore

## Add backups to a volume

Create the Garage bucket and key, then `pvc-backup-secret.sops.yaml` producing
Secret `pvc-backup-s3` with `ACCESS_KEY_ID`, `ACCESS_SECRET_KEY` and
`RESTIC_PASSWORD`.

`pvc-backup-values.yaml`:

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: pvc-backup-values
data:
  claimName: <app>-data
  repository: s3:https://s3.nas.felixwallner.com/<app>-bucket/restic
  sqliteDatabases: "db/<app>.db" # PVC-relative, space separated, may be ""
```

`kustomization.yaml`:

```yaml
namespace: <app>

resources:
  - pvc-backup-values.yaml
  - pvc-backup-secret.sops.yaml
  - pvc.yaml

components:
  - ../../../base/pvc-backup
```

## Restore

Stop the app:

```bash
kubectl scale deploy/<app> -n <app> --replicas=0
```

In a pod that mounts the claim writable:

```bash
# SQLite databases
restic restore latest --host <claimName> --target /restore --include /staging/sqlite
cp /restore/staging/sqlite/<app>.db /data/db/<app>.db

# rest of the volume
restic restore latest --host <claimName> --target /restore --include /data
cp -a /restore/data/. /data/

# on permission errors (wallos: uid 82)
chown -R 82:82 /data
```

Start the app:

```bash
kubectl scale deploy/<app> -n <app> --replicas=1
```
