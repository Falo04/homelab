# tailscale-node

A Helm chart for a single **userspace Tailscale node** that fronts an in-cluster
Service on your tailnet. Each release is one tailnet node with its own hostname,
its own auth key (pulled from Vault), and its own set of TCP forwards.

## How it works

The tailscaled container runs in **userspace mode** and reads a
[serve config](https://tailscale.com/kb/1242/tailscale-serve) that TCP-forwards
tailnet ports to a cluster Service. Its auth key comes from Vault via the Vault
Secrets Operator, and its node state is persisted in a Kubernetes Secret so the
node keeps its identity across pod restarts.

## Templates

| Template | Renders | What it does |
|----------|---------|--------------|
| `_helpers.tpl` | — | Shared name/label helpers (`fullname`, `labels`, `selectorLabels`). |
| `deployment.yaml` | `Deployment` | The tailscaled pod. Sets `TS_HOSTNAME`, mounts the serve config, reads the auth key from the Vault-synced Secret, and persists state to the `<fullname>-state` Secret. |
| `configmap.yaml` | `ConfigMap` | Builds the tailscale serve config (the `serve` key) from `tailscale.tcpForward`, one `TCPForward` entry per port. |
| `rbac.yaml` | `ServiceAccount` + `Role` + `RoleBinding` | The node's ServiceAccount and the minimal RBAC that lets tailscaled create/read/update its state Secret. |
| `staticsecret.yaml` | `VaultStaticSecret` | Syncs the tailnet auth key from Vault into a Secret named `<release>-auth` (with a `TS_AUTHKEY` field), via an **existing** `VaultAuth` (`vault.authRef`). |

## Values

For values descriptions see [values.yaml](./values.yaml).

## Example (ArgoCD)

Deploy the node alongside the app it fronts by adding it as an extra source on
that app's (multi-source) Application. `.Release.Namespace` follows the
Application's `destination.namespace`, so the node lands in the app's namespace:

```yaml
# apps/infra/applications/traefik.yaml
spec:
  sources:
    # ... the app's own sources ...
    - repoURL: https://github.com/Falo04/homelab.git
      targetRevision: main
      path: charts/tailscale-node
      helm:
        releaseName: traefik-tailscale
        valuesObject:
          tailscale:
            hostname: traefik
            tcpForward:
              - port: 443
                targetPort: 8443
                service: traefik
              - port: 80
                targetPort: 80
                service: traefik
          vault:
            authRef: vault-k8s
            mount: k3s-infra
            path: traefik/tailscale
  destination:
    namespace: traefik
    server: https://kubernetes.default.svc
```

## Prerequisites

- **Vault Secrets Operator** installed.
- An existing `VaultAuth` named `vault.authRef` in the release namespace (with
  its `VaultConnection` and a Kubernetes auth role bound to its ServiceAccount).
- A KV-v2 secret at `vault.mount`/`vault.path` containing a `TS_AUTHKEY` field.
