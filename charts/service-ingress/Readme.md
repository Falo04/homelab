# service-ingress

A Helm chart for a single **nginx reverse proxy** that terminates TLS for one
in-cluster Service. Each release fronts exactly one backend, on one hostname,
with one certificate.

## How it works

A service in this cluster is reached over the tailnet through its own
[tailscale-node](../tailscale-node/README.md), which raw-TCP-forwards to this
proxy.

## Values

For values descriptions see [values.yaml](./values.yaml).

## Example (ArgoCD)

Deploy the proxy alongside the app it fronts by adding it as an extra source on
that app's (multi-source) Application. `.Release.Namespace` follows the
Application's `destination.namespace`, so the proxy lands in the app's namespace:

```yaml
# apps/services/applications/wallos.yaml
spec:
  sources:
    # ... the app's own sources ...
    - repoURL: https://github.com/Falo04/homelab.git
      targetRevision: main
      path: charts/nginx-ingress
      helm:
        releaseName: wallos-ingress
        valuesObject:
          pod:
            fullnameOverride: wallos-ingress
          host: wallos.int.felixwallner.com
          tlsSecret: wallos-tls
          backend:
            service: wallos
            port: 80
  destination:
    namespace: wallos
    server: https://kubernetes.default.svc
```

The paired `tailscale-node` release then forwards to this proxy rather than to
the app directly:

```yaml
tailscale:
  hostname: wallos
  tcpForward:
    - port: 443
      targetPort: 443
      service: wallos-ingress
```

## Prerequisites

- **cert-manager** installed, with a `Certificate` in the release namespace whose
  `secretName` matches `tlsSecret` and whose `dnsNames` include `host`. The pod
  will not start until that Secret exists.
- A backend `Service` named `backend.service` in the release namespace. It must
  be a normal ClusterIP Service — a headless one has no stable address for nginx
  to resolve at startup.
- A DNS record pointing `host` at the tailnet address of the node that fronts it.
