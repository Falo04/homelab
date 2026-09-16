# PersistentVolumeClaim backup and restore

Volumes that are not a CNPG `Cluster` are backed up with
[restic](https://restic.net/) into the same Garage instance on the NAS. See
[cnpg.md](cnpg.md) for Postgres, which has its own mechanism.

## Adding backups to a volume

Two edits in the app's directory.

**1.** `pvc-backup-values.yaml`:

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: pvc-backup-values
data:
  claimName: <app>-data
  repository: s3:https://s3.nas.felixwallner.com/<app>-bucket/restic
  vaultMount: k3s-services # k3s-infra for apps under apps/infra
  vaultPath: <app>/backup
  sqliteDatabases: "db/<app>.db" # PVC-relative, space separated, may be ""
```

**2.** `kustomization.yaml`, add the values file and the component:

```yaml
namespace: <app>

resources:
  - pvc-backup-values.yaml
  - pvc.yaml

components:
  - ../../../base/pvc-backup
```

Prerequisites, same as CNPG plus one: the bucket must exist in Garage, and
`<vaultMount>/<vaultPath>` must hold `ACCESS_KEY_ID`, `ACCESS_SECRET_KEY` **and
`RESTIC_PASSWORD`**. The restic password is what the repository is encrypted
with, lose it and the backups are unreadable, so it belongs in Vault and
nowhere else. The namespace also needs `vault-auth.yaml`.

An app that already has CNPG backups can reuse its existing Garage key; only
`RESTIC_PASSWORD` has to be added to the same Vault path. The restic repository
lives under a `restic/` prefix so it does not collide with barman-cloud's
layout in the same bucket.

## SQLite

A running SQLite database cannot be copied as a file. A plain `cp` during a
write yields a torn page, and with `journal_mode=delete` (what wallos uses) it
can also miss an in-flight rollback journal. Either way the copy restores to a
corrupt database, and nothing warns you.

So the CronJob runs in two stages:

1. `sqlite-snapshot` opens each database in `sqliteDatabases` read-only and
   runs SQLite's online backup API into an emptyDir, then checks the result:

   ```sh
   sqlite3 "file:$src?mode=ro" ".timeout 30000" ".backup '$out'"
   check="$(sqlite3 "$out" "pragma integrity_check;")"
   ```

   `mode=ro` is required because the volume is mounted read-only, a writable
   open would try to create a journal next to the live database and fail.
   `.timeout` makes `.backup` wait out a concurrent writer instead of failing
   on `SQLITE_BUSY`. A failed `integrity_check` exits non-zero and fails the
   whole job, which leaves the previous good snapshot as the newest one.

2. `restic` backs up the volume _minus_ the live database files (and their
   `-journal`/`-wal`/`-shm` siblings), plus the consistent copies from stage 1.

Apps with no SQLite set `sqliteDatabases: ""`; stage 1 then exits immediately
and the whole volume is backed up as-is.

## Layout inside a snapshot

Each snapshot has two roots:

- `/data` — the volume, live databases excluded
- `/staging/sqlite/<name>.db` — the consistent database copies

Snapshots are tagged `pvc` and pinned to `--host <claimName>`. The host is not
cosmetic: restic defaults it to the pod's hostname, which is a new random name
every run, and `restic forget` groups by host, without a stable host every
snapshot is its own group and retention never prunes anything.

Retention is 7 daily, 4 weekly, 6 monthly, applied with `--prune` at the end of
each run.

## Restoring

The database file is mounted from the volume, so wallos has to stop before it
can be replaced, otherwise it will happily write over the restored file.

```console
kubectl scale deploy/wallos -n wallos --replicas=0
```

Then run a pod that mounts the claim **writable** and restores into it. The
paths in the snapshot are prefixed, so restore to a staging target and move the
file into place rather than restoring straight onto `/data`:

```console
$ restic restore latest --host wallos-data --target /restore \
    --include /staging/sqlite
$ cp /restore/staging/sqlite/wallos.db /data/db/wallos.db
```

The uploaded logos come from the other root:

```console
restic restore latest --host wallos-data --target /restore --include /data
cp -a /restore/data/logos/. /data/logos/
```

Watch the file ownership: wallos runs as uid 82 (`www-data`) with `fsGroup: 82`,
and restic restores the uid it recorded. `chown -R 82:82 /data` after a restore
if the pod comes back with permission errors.

Finally:

```console
kubectl scale deploy/wallos -n wallos --replicas=1
```
