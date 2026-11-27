# Secrets

## Editing

```fish
set -x GPG_TTY (tty)   # YubiKey plugged in
sops edit apps/<infra|services>/<app>/<name>.sops.yaml
```

Commit and push. If the file's header comment says so, restart the app:

```bash
kubectl -n <namespace> rollout restart deploy/<name>        # or statefulset/<name>
```

Without the YubiKey, use the cluster key:

```bash
bash -c 'read -rsp "key: " k; echo; SOPS_AGE_KEY="$k" sops edit <file>'
```

Never `sops decrypt <file> > <file>`. Once per clone:

```bash
pre-commit install
```

## Adding

```bash
sops edit apps/<infra|services>/<app>/<name>.sops.yaml
```

Replace the example content with:

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

Add the file under `resources:` in the app's `kustomization.yaml`.

## Rotating keys

1. Change the keys in `.sops.yaml`.
2. Re-encrypt every file:

   ```bash
   find . -name '*.sops.yaml' -not -path './.sops.yaml' -exec sops updatekeys -y {} \;
   ```

3. New cluster key: replace the `sops-age-key` Secret in `sops-secrets-operator`.
4. Leaked cluster key: also rotate every secret value.
