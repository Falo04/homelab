# Homelab

My [k3s](https://k3s.io/) homelab cluster, managed with GitOps via
[Argo CD](https://argo-cd.readthedocs.io/). Cluster state lives in this repo:
Argo CD watches it and reconciles the cluster to match. Secrets are kept in
[HashiCorp Vault](/vault/README.md), run alongside the cluster and reachable
only over the local network and Tailscale.

> Work in progress — this cluster is still being built out.

## Layout

| Path              | What it holds                                                        |
| ----------------- | ------------------------------------------------------------------- |
| `bootstrap/`      | The [app-of-apps](bootstrap/app-of-apps.yaml) Application that seeds Argo CD |
| `apps/`           | Argo CD `Application` definitions and their manifests                |
| `vault/`          | HashiCorp Vault behind Traefik, LAN + Tailscale only ([README](/vault/README.md)) |

## How it works

The cluster is bootstrapped with a single **app-of-apps** Application. Once
applied, it points Argo CD back at this repo, and Argo CD takes over syncing
everything under `apps/` — including its own configuration.

```bash
kubectl apply -f bootstrap/app-of-apps.yaml
```

From there, changes are made by committing to `main`; Argo CD picks them up and
reconciles the cluster automatically.

## Secrets

Secrets are managed by HashiCorp Vault, deployed separately with Docker Compose
and fronted by Traefik (TLS via Let's Encrypt DNS-01). It is reachable only over
the local network and the tailnet — never the public internet. See
[`vault/README.md`](/vault/README.md) for setup, initialization, and upgrades.
