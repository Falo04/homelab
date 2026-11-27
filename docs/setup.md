# Cluster setup

## 1. k3s

Deploy with [k3s-ansible](https://github.com/timothystewart6/k3s-ansible).

## 2. Argo CD

Have the SOPS cluster key (`AGE-SECRET-KEY-…`) ready, then:

```bash
./scripts/bootstrap-argocd.sh
```

Initial admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```
