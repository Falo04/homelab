# Cluster setup

Four steps, in order: Vault, k3s, Argo CD, then teaching Vault to trust the
cluster. Everything after that is GitOps, commit to `main` and Argo CD
reconciles.

## 1. Vault

Vault has to be running and reachable from the cluster before anything else,
since the operator pulls every secret from it. Mine runs alongside the cluster
at `https://vault.${DOMAIN}`. See [vault](/vault/README.md).

## 2. k3s

Deployed with [k3s-ansible](https://github.com/timothystewart6/k3s-ansible),
which also brings up Cilium as the CNI and disables k3s's bundled Traefik and
servicelb.

## 3. Argo CD

k3s-ansible doesn't install Argo CD, and this repo can't either:
`bootstrap/app-of-apps.yaml` *is* an `Application`, and that kind only exists
once Argo CD's CRDs are in the cluster. Applying it first fails with
`no matches for kind "Application"`. So seed it once:

```bash
./scripts/bootstrap-argocd.sh
```

That installs the chart and applies the app-of-apps. From there Argo CD manages
everything, including its own release, nothing else gets deployed by hand.

Initial admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

## 4. Connecting Kubernetes to Vault

Argo CD applies the cluster-side objects (`vault-secrets-operator` plus the
`vault-secrets` namespace, ServiceAccounts, `VaultConnection` and `VaultAuth`).
But Vault also has to be told to *trust this cluster*. Those steps run once,
against Vault, and can't live in this repo. Run them with a Vault token that has
admin rights (e.g. `export VAULT_ADDR=https://vault.int.felixwallner.com`).

### 4.1 Grab what Vault needs from the cluster

Vault verifies incoming logins by calling the cluster's TokenReview API, so it
needs a long-lived token for the `vault-token-reviewer` ServiceAccount, the API
server URL and its CA cert. Create a non-expiring token Secret for the reviewer
SA (k8s no longer auto-creates these):

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: vault-token-reviewer
  namespace: vault-secrets
  annotations:
    kubernetes.io/service-account.name: vault-token-reviewer
type: kubernetes.io/service-account-token
EOF

export TOKEN_REVIEW_JWT=$(kubectl -n vault-secrets get secret vault-token-reviewer -o go-template='{{ .data.token | base64decode }}')
export KUBE_CA_CERT=$(kubectl -n vault-secrets get secret vault-token-reviewer -o go-template='{{ index .data "ca.crt" | base64decode }}')
export KUBE_HOST=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
```

In fish:

```fish
echo '
apiVersion: v1
kind: Secret
metadata:
  name: vault-token-reviewer
  namespace: vault-secrets
  annotations:
    kubernetes.io/service-account.name: vault-token-reviewer
type: kubernetes.io/service-account-token' | kubectl apply -f -

set -x TOKEN_REVIEW_JWT (kubectl -n vault-secrets get secret vault-token-reviewer -o go-template='{{ .data.token | base64decode }}')
set -x KUBE_CA_CERT (kubectl -n vault-secrets get secret vault-token-reviewer -o go-template='{{ index .data "ca.crt" | base64decode }}' | string collect)
set -x KUBE_HOST (kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

string length $TOKEN_REVIEW_JWT   # must be non-zero
```

### 4.2 Enable and configure the Kubernetes auth method in Vault

```bash
vault auth enable kubernetes

vault write auth/kubernetes/config \
    token_reviewer_jwt="$TOKEN_REVIEW_JWT" \
    kubernetes_host="$KUBE_HOST" \
    kubernetes_ca_cert="$KUBE_CA_CERT"
```

This write replaces the whole config — always pass all three fields together.

On a cluster rebuild, skip `vault auth enable kubernetes` (it fails with `path
is already in use`) and re-run the `vault write` with fresh values from 4.1.

Verify:

```bash
vault read auth/kubernetes/config
```

`token_reviewer_jwt_set` must be `true` and `kubernetes_ca_cert` must match the
current cluster CA.

### 4.3 Create the policy and role the operator logs into

Each namespace has its own `vso-auth` ServiceAccount and a `VaultAuth` that logs
in against role `vso` with audience `vault`.

The policy is templated: an identity can read only the KV path whose first
segment matches its own namespace. Substitute the `kubernetes/` mount accessor
from `vault auth list -format=json | jq -r '.["kubernetes/"].accessor'`:

```bash
vault policy write k3s-infra-read - <<'EOF'
path "k3s-infra/data/{{identity.entity.aliases.auth_kubernetes_aeecc09a.metadata.service_account_namespace}}/*" {
  capabilities = ["read"]
}
path "k3s-infra/metadata/{{identity.entity.aliases.auth_kubernetes_aeecc09a.metadata.service_account_namespace}}/*" {
  capabilities = ["read", "list"]
}
EOF

vault write auth/kubernetes/role/vso \
    bound_service_account_names=vso-auth \
    bound_service_account_namespaces=vault-secrets,traefik,cert-manager,authentik,argocd,grafana,monitoring,ntfy \
    audience=vault \
    policies=k3s-infra-read \
    ttl=1h
```

Add every namespace that gets a `vso-auth` SA to
`bound_service_account_namespaces`, and store its secrets under
`k3s-infra/<namespace>/`.

After this, the operator can reach Vault (`VaultConnection`), log in
(`VaultAuth`), and you can start pulling secrets with `VaultStaticSecret` /
`VaultDynamicSecret` resources.
