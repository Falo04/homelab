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
| `wallos`       | user  | Wallos publisher      | `wallos` write         |

ACLs live in `apps/infra/ntfy/server.yml`. Users and tokens live in
`apps/infra/ntfy/auth-secret.sops.yaml`.

### 1. Generate hashes and tokens

```bash
# bcrypt hash per user (prompts for a password; for the service users any
# long random password is fine, they only ever use their token)
docker run --rm -it binwiederhier/ntfy:v2.28.0 user hash

# one token per service user (tk_ + 29 chars)
docker run --rm binwiederhier/ntfy:v2.28.0 token generate
```

### 2. Store them

With `sops edit` (see [secrets.md](secrets.md)):

- `apps/infra/ntfy/auth-secret.sops.yaml`:
  `NTFY_AUTH_USERS: "felix:<hash>:admin,alertmanager:<hash>:user,grafana:<hash>:user,wallos:<hash>:user"`
  and `NTFY_AUTH_TOKENS: "alertmanager:<am-token>:Alertmanager,grafana:<grafana-token>:Grafana,wallos:<wallos-token>:Wallos"`,
  then restart ntfy.
- `apps/infra/monitoring/ntfy-secret.sops.yaml`: `token: <am-token>`
- `apps/infra/grafana/ntfy-secret.sops.yaml`: `token: <grafana-token>`

Each token is stored once for ntfy and once for the namespace that uses it.

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
