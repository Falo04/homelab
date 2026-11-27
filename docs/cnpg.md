# PostgreSQL backup and restore

## Add backups to a cluster

Create the Garage bucket and key, then `cnpg-backup-secret.sops.yaml` producing
Secret `cnpg-backup-s3` with `ACCESS_KEY_ID` and `ACCESS_SECRET_KEY`.

`backup-values.yaml`:

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: cnpg-backup-values
data:
  clusterName: <app>-postgres
  destinationPath: s3://<app>-bucket/
```

`kustomization.yaml`:

```yaml
resources:
  - backup-values.yaml
  - cnpg-backup-secret.sops.yaml
  - postgres.yaml

components:
  - ../../../base/cnpg-backup
```

`postgres.yaml`:

```yaml
spec:
  plugins:
    - name: barman-cloud.cloudnative-pg.io
      isWALArchiver: true
      parameters:
        barmanObjectName: garage-store
```

## Restore

Create a new `Cluster` (example: `apps/infra/ntfy/postgres-test.yaml`):

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: <app>-postgres-test
  namespace: <app>
spec:
  instances: 1
  imageName: ghcr.io/cloudnative-pg/postgresql:17.5 # same major as source
  storage:
    size: 2Gi
  bootstrap:
    recovery:
      source: garage
  externalClusters:
    - name: garage
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: garage-store
          serverName: <app>-postgres # source cluster name
```

No `plugins:` block on the restored cluster.

### Point in time

```yaml
bootstrap:
  recovery:
    source: garage
    recoveryTarget:
      targetTime: "2026-09-16 10:00:00+02"
```
