# Upgrading

How to upgrade the two stacks safely. Both are plain Docker images, so an
upgrade is mostly: change the tag → pull → recreate → verify.

Current versions:

- **Traefik** — `traefik:v3.7` (pinned in `traefik/traefik-docker-compose.yaml`)
- **Vault** — `hashicorp/vault:1.13.3` (pinned in `vault-cluster/docker-compose.yml`)

## Before any upgrade

1. **Read the release notes / changelog** for the version you're moving to
   (links below). Watch for breaking changes and required config migrations.
2. **Back up state:**
   - Traefik certs — the `acme` Docker volume (`letsencrypt.json`).
   - Vault data — `vault-cluster/vault1/data/` (Raft storage). Take a Vault
     snapshot too (see below).
3. Prefer **one stack at a time** so a failure is easy to isolate.

Handy snapshot for Vault (Raft):

```bash
# needs a valid token in the container's env or -address/-token flags
just exec vault vault operator raft snapshot save /vault/data/pre-upgrade.snap
```

---

## Traefik

Traefik uses **pinned tags** — this is the recommended approach. Upgrade by
editing the tag, not by pulling `latest`.

### Steps

1. Pick the target version from the releases page (links below).
2. Bump the tag in `traefik/traefik-docker-compose.yaml`:

   ```yaml
   image: traefik:v3.8   # was v3.7
   ```

3. Pull and recreate just this stack:

   ```bash
   just pull traefik
   just up traefik        # recreates the container with the new image
   ```

   Or in one step: `just update traefik`.

4. Verify:

   ```bash
   just ps
   just logs traefik
   ```

   Confirm the dashboard loads at `https://traefik.${ROOT_DOMAIN}` and certs are
   still valid.

### Notes

- **Patch/minor** upgrades within `v3.x` are usually drop-in.
- **Major** upgrades (e.g. `v2 → v3`) have breaking config changes — read the
  migration guide first; static/dynamic config keys and CLI flags change.
- To roll back: restore the old tag and `just up traefik`. Certs in the `acme`
  volume are unaffected.

### Links

- Releases: https://github.com/traefik/traefik/releases
- Docker Hub tags: https://hub.docker.com/_/traefik/tags
- Changelog: https://github.com/traefik/traefik/blob/master/CHANGELOG.md
- v3 migration guide: https://doc.traefik.io/traefik/migration/v2-to-v3/
- v3 → v3 details: https://doc.traefik.io/traefik/migration/v3/

---

## Vault

Vault is currently on `latest`, which is convenient but risky — an upgrade can
happen unexpectedly on `just pull`, and **Vault does not support downgrades**.
Consider pinning a version (e.g. `hashicorp/vault:1.20`).

### Important: Vault upgrade rules

- **Never skip more than one major/minor line** without checking the upgrade
  guide — some versions require stepping through intermediate releases.
- **No downgrades.** Once the data directory is written by a newer version, an
  older binary may refuse to start. This is why the snapshot/backup matters.
- After the container restarts, Vault comes up **sealed** — you must
  **unseal** it again (unless auto-unseal is configured).

### Steps

1. Take a snapshot + back up `vault-cluster/vault1/data/` (see "Before any
   upgrade").
2. (Recommended) Pin the target version in `vault-cluster/docker-compose.yml`:

   ```yaml
   image: hashicorp/vault:1.20   # instead of :latest
   ```

3. Pull and recreate:

   ```bash
   just pull vault
   just up vault          # or: just update vault
   ```

4. **Unseal** and verify:

   ```bash
   just exec vault vault operator unseal   # repeat to meet the threshold
   just exec vault vault status            # check Version + Sealed=false
   ```

5. Confirm the UI at `https://vault.${ROOT_DOMAIN}` and that secrets read back.

### Rolling back

Downgrades aren't supported. To recover a bad upgrade: stop the stack, restore
the backed-up `data/` directory (or the Raft snapshot into a fresh node), pin
the previous image version, then `just up vault` and unseal.

### Links

- Releases / changelog: https://github.com/hashicorp/vault/releases
- Upgrade overview: https://developer.hashicorp.com/vault/docs/upgrading
- Version-specific upgrade guides: https://developer.hashicorp.com/vault/docs/upgrading/upgrade-guides
- Docker Hub tags: https://hub.docker.com/r/hashicorp/vault/tags
- Raft snapshots: https://developer.hashicorp.com/vault/docs/concepts/integrated-storage

---

## Quick reference

```bash
just pull <stack>     # pull the image for a stack
just update <stack>   # pull + recreate (down is not run; up -d re-creates)
just ps               # container status
just logs <stack>     # follow logs
```

Replace `<stack>` with `traefik` or `vault` (omit to act on all).
