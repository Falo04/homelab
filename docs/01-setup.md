# Cluster setup

Two steps, in order: k3s, then Argo CD. Everything after that is GitOps,
commit to `main` and Argo CD reconciles.

## 1. k3s

Deployed with [k3s-ansible](https://github.com/timothystewart6/k3s-ansible),
which also brings up Cilium as the CNI and disables k3s's bundled Traefik and
servicelb.

## 2. Argo CD

k3s-ansible doesn't install Argo CD, and this repo can't either:
`bootstrap/app-of-apps.yaml` *is* an `Application`, and that kind only exists
once Argo CD's CRDs are in the cluster. Applying it first fails with
`no matches for kind "Application"`. So seed it once:

```bash
./scripts/bootstrap-argocd.sh
```

It first asks for the SOPS cluster key (`AGE-SECRET-KEY-…`, kept in
1Password), and creates it in the cluster before anything syncs. Every other
secret is encrypted with it, see [secrets.md](secrets.md).

Then it installs the chart and applies the app-of-apps. From there Argo CD manages
everything, including its own release, nothing else gets deployed by hand.

Initial admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```
