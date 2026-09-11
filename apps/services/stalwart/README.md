# Stalwart

Mail server backed by CloudNativePG.

## Before the first sync

1. Add `stalwart` to `bound_service_account_namespaces` on the Vault `vso` role
   ([docs/01-setup.md](/docs/01-setup.md) §4.3).
2. Write `k3s-infra/stalwart/recovery-admin` in Vault, key `user`, in the form
   `username:password`.
3. Add this file:

```yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: vault-stalwart-recovery-admin
  namespace: stalwart
spec:
  vaultAuthRef: vault-k8s
  mount: k3s-infra
  type: kv-v2
  path: stalwart/recovery-admin
  refreshAfter: 1h
  destination:
    create: true
    name: stalwart-recovery-admin
    labels:
      app.kubernetes.io/part-of: stalwart
```

## Deploy

Sign in at `https://{your-domain}/admin` with the recovery credentials and
create a permanent admin account. Everything else is configured there and stored
in Postgres, not in this repo.

## Then remove the recovery admin

It's a standing backdoor otherwise. Order matters:

1. One commit: drop the `STALWART_RECOVERY_ADMIN` env block from
   `statefulset.yaml`, drop `recovery-admin-secret.yaml` from
   `kustomization.yaml`, delete that file.
2. Let Argo sync, the pod rolls without the env var and the Secret is
   garbage-collected with its `VaultStaticSecret`.
3. _Only then_ delete `k3s-infra/stalwart/recovery-admin` in Vault.

Vault last: deleting it first leaves the credential live in the Secret while the
CR errors, and the missing key stops the pod from starting.
