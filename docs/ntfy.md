# ntfy

Private push notifications for alerts. ntfy runs in the `ntfy` namespace and
is reachable only in-cluster and over the tailnet at
`https://ntfy.int.felixwallner.com`. Alertmanager and Grafana publish to it
over the cluster network; phones subscribe over Tailscale.

## Users and tokens

| User           | Role  | Used by               | Access                 |
| -------------- | ----- | --------------------- | ---------------------- |
| `felix`        | admin | phone app / web UI    | everything             |
| `alertmanager` | user  | Alertmanager webhook  | `homelab-alerts` write |
| `grafana`      | user  | Grafana contact point | `homelab-alerts` write |

ACLs live in `apps/infra/ntfy/server.yml`. Users and tokens live in Vault.

### 1. Generate hashes and tokens

```bash
# bcrypt hash per user (prompts for a password; for the service users any
# long random password is fine, they only ever use their token)
docker run --rm -it binwiederhier/ntfy:v2.28.0 user hash

# one token per service user (tk_ + 29 chars)
docker run --rm binwiederhier/ntfy:v2.28.0 token generate
```

### 2. Store them in Vault

Single quotes matter, bcrypt hashes contain `$`.

```bash
vault kv put k3s-infra/ntfy/auth \
  NTFY_AUTH_USERS='felix:<hash>:admin,alertmanager:<hash>:user,grafana:<hash>:user' \
  NTFY_AUTH_TOKENS='alertmanager:<am-token>:Alertmanager,grafana:<grafana-token>:Grafana'

vault kv put k3s-infra/monitoring/ntfy token='<am-token>'
vault kv put k3s-infra/grafana/ntfy token='<grafana-token>'
```

The Vault policy is namespace-scoped, so each token is stored once for ntfy and
once for the namespace that uses it.

### 3. Let the new namespaces log in

Re-run the role write from `01-setup.md` 4.3 with `monitoring` and `ntfy` added
to `bound_service_account_namespaces`.

## Test

From a machine on the tailnet:

```bash
curl -u felix -d "hello from the homelab" https://ntfy.int.felixwallner.com/homelab-alerts
```

Full Alertmanager path:

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-alertmanager 9093
amtool alert add NtfyTest severity=warning --alertmanager.url=http://localhost:9093
```
