# tailscale-node

A Helm chart for a single **userspace Tailscale node** that fronts an in-cluster
Service on your tailnet. Each release is one tailnet node with its own hostname,
its own auth key, and its own set of TCP forwards.

## How it works

The tailscaled container runs in **userspace mode** and reads a
[serve config](https://tailscale.com/kb/1242/tailscale-serve) that TCP-forwards
tailnet ports to a cluster Service. Its auth key comes from an existing Secret
(`authSecret`), and its node state is persisted in a Kubernetes Secret so the
node keeps its identity across pod restarts.

## Templates

| Template | Renders | What it does |
|----------|---------|--------------|
| `_helpers.tpl` | — | Shared name/label helpers (`fullname`, `labels`, `selectorLabels`). |
| `deployment.yaml` | `Deployment` | The tailscaled pod. Sets `TS_HOSTNAME`, mounts the serve config, reads the auth key from `authSecret`, and persists state to the `<fullname>-state` Secret. |
| `configmap.yaml` | `ConfigMap` | Builds the tailscale serve config (the `serve` key) from `tailscale.tcpForward`, one `TCPForward` entry per port. |
| `rbac.yaml` | `ServiceAccount` + `Role` + `RoleBinding` | The node's ServiceAccount and the minimal RBAC that lets tailscaled create/read/update its state Secret. |
| `servers.sops.yaml` | `SopsSecret` | The control server (`TS_LOGIN_SERVER`) and log server (`TS_LOG_TARGET`) URLs, SOPS-encrypted. The same for every release; one per namespace, so at most one release per namespace. |

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
          authSecret: tailscale-auth   # from a SopsSecret in apps/infra/traefik
  destination:
    namespace: traefik
    server: https://kubernetes.default.svc
```

## Prerequisites

- **sops-secrets-operator** installed: the control and log server URLs come
  from `servers.sops.yaml`, encrypted into the chart.
- A Secret named `authSecret` in the release namespace with a `TS_AUTHKEY`
  field.
