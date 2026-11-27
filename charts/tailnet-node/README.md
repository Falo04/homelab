# tailnet-node

A Helm chart that puts one in-cluster Service on the tailnet: a **userspace
Tailscale node**, plus an **nginx** that terminates TLS for it with a
cert-manager certificate. Everything is named after `hostname`.

## Values

For values descriptions see [values.yaml](./values.yaml).

## Example (ArgoCD)

Add the chart as an extra source on the app's (multi-source) Application.
`.Release.Namespace` follows the Application's `destination.namespace`:

```yaml
# apps/services/applications/wallos.yaml
spec:
  sources:
    # ... the app's own sources ...
    - repoURL: https://github.com/Falo04/homelab.git
      targetRevision: main
      path: charts/tailnet-node
      helm:
        releaseName: wallos
        valuesObject:
          hostname: wallos
          authSecret: tailscale-auth # from a SopsSecret in apps/services/wallos
          ingress:
            backend:
              service: wallos
              port: 80
  destination:
    namespace: wallos
    server: https://kubernetes.default.svc
```

## Prerequisites

- **sops-secrets-operator** installed: the control and log server URLs come
  from `servers.sops.yaml`, encrypted into the chart.
- A Secret named `authSecret` in the release namespace with a `TS_AUTHKEY`
  field.
- **cert-manager** with the `ingress.issuer` ClusterIssuer (with ingress).
- A normal ClusterIP backend Service (with ingress). A headless one has no
  stable address for nginx to resolve at startup.
