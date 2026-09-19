# Vault backup and restore

Snapshots are taken **daily** by the `vault-backup` container in
[`vault/docker-compose.yml`](/vault/docker-compose.yml) and stored in a restic
repository on Garage.

## Setup

### 1. Garage

Create the bucket `vault-bucket` and a key scoped to it only.

### 2. Vault: a snapshot-only AppRole

Run once, with an admin token:

```bash
vault policy write vault-backup - <<'EOF'
path "sys/storage/raft/snapshot" {
  capabilities = ["read"]
}
EOF

vault auth enable approle
vault write auth/approle/role/vault-backup \
    token_policies=vault-backup \
    token_ttl=10m token_max_ttl=30m \
    secret_id_ttl=0 secret_id_num_uses=0

vault read  -field=role_id      auth/approle/role/vault-backup/role-id
vault write -f -field=secret_id auth/approle/role/vault-backup/secret-id
```

### 3. ntfy

Add a `vault-backup` service user following [ntfy.md](ntfy.md). Its token goes
into `vault-backup.env`.

### 4. The credentials file

`vault/vault-backup.env` on the Docker host, matched by the `*.env` rule in
`.gitignore`:

```env
RESTIC_PASSWORD=<long random string>
AWS_ACCESS_KEY_ID=<garage key id>
AWS_SECRET_ACCESS_KEY=<garage secret>
VAULT_BACKUP_ROLE_ID=<role_id from step 2>
VAULT_BACKUP_SECRET_ID=<secret_id from step 2>
NTFY_TOKEN=<vault-backup ntfy token>
```

Copy all of it into the password manager, next to the unseal keys.

## Restoring

Into a fresh, empty Vault. Steps 2 and 3 exist only because
`snapshot restore` needs an unsealed Vault to talk to; those keys are thrown
away at step 6.

```bash
# 1. Bring up an empty Vault (no vault1/data).
just up

# 2. Initialise it. These keys are temporary.
just exec vault vault operator init

# 3. Unseal with the temporary keys, to threshold.
just exec vault vault operator unseal <temp-key>
just exec vault vault login <temp-root-token>

# 4. Fetch the snapshot out of Garage.
just backup-restore                  # -> ./restore/tmp/vault-raft.snap

# 5. Restore it. -force is required: the snapshot comes from a different
#    cluster than the one that was just initialised.
just exec vault vault operator raft snapshot restore -force /restore/tmp/vault-raft.snap
```

Step 5 mounts `./restore` into the `vault` container — add it to the `vault`
service's volumes for the duration of the restore, or copy the file in with
`docker cp`.

```bash
# 6. Vault seals itself: the barrier keyring is now the OLD cluster's. Unseal
#    with the ORIGINAL unseal keys from the password manager. The temporary
#    keys from step 2 no longer work.
just exec vault vault operator unseal <original-key>

# 7. Verify.
just exec vault vault status                    # Sealed=false
just exec vault vault kv get k3s-infra/ntfy/auth
```
