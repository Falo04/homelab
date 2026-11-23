# Secrets

Every secret lives next to the app that uses it, as a `*.sops.yaml` file: a
`SopsSecret` whose `data`/`stringData` values are encrypted with
[SOPS](https://github.com/getsops/sops). Everything else in the file (names,
labels, key names, comments) stays readable. In the cluster,
[sops-secrets-operator](https://github.com/isindir/sops-secrets-operator)
decrypts each one into a normal `Secret` of the same name.

Each file is encrypted to two keys, either of which can decrypt it alone
([`.sops.yaml`](/.sops.yaml)):

| Key         | Type | Where                                                         |
| ----------- | ---- | ------------------------------------------------------------- |
| cluster key | age  | Secret `sops-age-key` in `sops-secrets-operator`; 1Password   |
| owner key   | GPG  | YubiKey                                                       |

## Editing

YubiKey plugged in, and in fish `set -x GPG_TTY (tty)` so GPG can ask for the
PIN.

```bash
sops edit apps/services/wallos/oidc-secret.sops.yaml
```

Save and close, commit, push. The operator updates the `Secret` within a few
minutes. Apps that read a secret only at startup need a restart afterwards;
each such file says so in its header comment:

| Namespace   | Restart                                          |
| ----------- | ------------------------------------------------ |
| `wallos`    | `kubectl -n wallos rollout restart deploy/wallos` |
| `trek`      | `kubectl -n trek rollout restart deploy/trek`     |
| `livesync`  | `kubectl -n livesync rollout restart deploy/livesync` |
| `bookorbit` | `kubectl -n bookorbit rollout restart deploy/bookorbit` |
| `ntfy`      | `kubectl -n ntfy rollout restart deploy/ntfy`     |
| `loki`      | `kubectl -n loki rollout restart statefulset/loki` |
| `tempo`     | `kubectl -n tempo rollout restart statefulset/tempo` |

Without the YubiKey, use the cluster key from 1Password for one command:

```bash
bash -c 'read -rsp "key: " k; echo; SOPS_AGE_KEY="$k" sops edit <file>'
```

Never `sops decrypt <file> > <file>`: always `sops edit`, so plaintext doesn't
end up on disk. The `sops-encrypted` pre-commit hook rejects an unencrypted
`*.sops.yaml` (run `pre-commit install` once per clone).

## Adding

```bash
sops edit apps/<infra|services>/<app>/<name>.sops.yaml
```

A new file opens with an example; replace it with:

```yaml
apiVersion: isindir.github.com/v1alpha3
kind: SopsSecret
metadata:
  name: <secret-name>
spec:
  secretTemplates:
    - name: <secret-name>
      stringData:
        SOME_KEY: some-value
```

and list the file under `resources:` in the app's `kustomization.yaml`. The
name must end in `.sops.yaml`, otherwise `.sops.yaml`'s rule doesn't match it.

## Keys

**New or replaced key** (new YubiKey, new cluster key): change `.sops.yaml`,
then re-encrypt every file to the new set of keys:

```bash
find . -name '*.sops.yaml' -not -path './.sops.yaml' -exec sops updatekeys -y {} \;
```

A new cluster key also has to replace the `sops-age-key` Secret.

**Cluster key leaked:** new key and `updatekeys` as above, **and** rotate the
secrets themselves. The repo is public, so every old ciphertext stays readable
in git history to whoever has the old key.

## Fresh cluster

`scripts/bootstrap-argocd.sh` asks for the cluster key and creates
`sops-age-key` before Argo CD syncs anything, see [01-setup.md](01-setup.md).
