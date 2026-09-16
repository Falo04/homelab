#!/usr/bin/env bash
# Seed Argo CD into a fresh cluster, then hand the cluster over to GitOps.
set -euo pipefail

# Only has to be close to the version pinned in
# apps/infra/applications/argocd.yaml; Argo CD reconciles itself to whatever
# that Application says on the first sync.
CHART_VERSION="10.8.4"
NAMESPACE="argocd"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

kubectl cluster-info >/dev/null 2>&1 || {
  echo "no reachable cluster, check your KUBECONFIG" >&2
  exit 1
}

echo "==> Installing argo-cd $CHART_VERSION into namespace $NAMESPACE"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo update argo >/dev/null

# fullnameOverride has to match apps/infra/applications/argocd.yaml. If the
# names differ, Argo CD won't see these resources as its own: it creates a
# second set and prunes this one, killing the pod doing the sync.
helm upgrade --install argocd argo/argo-cd \
  --version "$CHART_VERSION" \
  --namespace "$NAMESPACE" --create-namespace \
  --set fullnameOverride=argocd

echo "==> waiting for argocd-server"
kubectl -n "$NAMESPACE" rollout status deploy/argocd-server --timeout=5m

echo "==> applying the app-of-apps"
kubectl apply -f "$repo_root/bootstrap/app-of-apps.yaml"

cat <<EOF

Argo CD is up and syncing from git.

  admin password
    kubectl -n $NAMESPACE get secret argocd-initial-admin-secret \\
      -o jsonpath='{.data.password}' | base64 -d; echo

  UI, until the Traefik IngressRoute resolves
    kubectl -n $NAMESPACE port-forward svc/argocd-server 8080:80

  watch it converge
    kubectl -n $NAMESPACE get applications -w
EOF
