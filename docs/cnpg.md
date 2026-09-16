# PostgreSQL backup, restore and upgrades

Every Postgres database in the cluster runs as a
[CloudNativePG](https://cloudnative-pg.io/) `Cluster`. Backups go to Garage
(S3-compatible, on the NAS) through the
[barman-cloud plugin](https://github.com/cloudnative-pg/plugin-barman-cloud).

## Adding backups to a cluster

Three edits in the app's directory.

**1.** `backup-values.yaml`:

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: cnpg-backup-values
data:
  clusterName: <app>-postgres
  destinationPath: s3://<app>-bucket/
  vaultPath: <app>/backup
```

The bucket must already exist in Garage, with an access key whose
`ACCESS_KEY_ID` / `ACCESS_SECRET_KEY` are stored at `k3s-infra/<app>/backup`
in Vault. The namespace also needs `vault-auth.yaml` (all app namespaces
already have it).

**2.** `kustomization.yaml`, add the values file and the component:

```yaml
resources:
  - backup-values.yaml
  - postgres.yaml

components:
  - ../../../base/cnpg-backup
```

**3.** `postgres.yaml`, attach the plugin as a WAL archiver:

```yaml
spec:
  plugins:
    - name: barman-cloud.cloudnative-pg.io
      isWALArchiver: true
      parameters:
        barmanObjectName: garage-store
```

## Restoring

A restore never writes to the existing cluster. You create a **new** `Cluster`
that bootstraps from the object store, which is also how you test that backups
are good.

`apps/infra/ntfy/postgres-test.yaml` is the worked example:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: ntfy-postgres-test
  namespace: ntfy
spec:
  instances: 1
  # Must match the source cluster's major version.
  imageName: ghcr.io/cloudnative-pg/postgresql:17.5
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
          serverName: ntfy-postgres
```

Three fields carry all the weight:

- `serverName`: the **source** cluster's name. Without it the plugin looks
  for a backup under the new cluster's own name, which does not exist.
- `imageName`: must match the source's major version.
- No `plugins:` block, so the restored cluster does not archive. It cannot
  contaminate the real cluster's backup chain.

### Point in time

Add a `recoveryTarget` to stop somewhere other than the end of the archive:

```yaml
bootstrap:
  recovery:
    source: garage
    recoveryTarget:
      targetTime: "2026-09-16 10:00:00+02"
```
